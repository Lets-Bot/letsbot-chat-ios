import CryptoKit
import Foundation

/// Visitor session, identity, push registration and unread counter — the networking core behind ``LetsBot``.
///
/// An actor so that concurrent callers (chat screen, push token callback, foreground refresh) share one session and
/// never create two visitors at once.
actor ChatEngine {
    struct PushRegistration: Equatable, Sendable {
        var provider: String // "apns" | "fcm"
        var token: String
        var sandbox: Bool
    }

    nonisolated let api: APIClient
    nonisolated let configuration: LetsBotConfiguration
    private let store: SecureStore
    private let tokenKey: String
    private let userKey: String

    private var sessionTask: Task<String, Error>?
    private(set) var context: [String: String] = [:]
    private(set) var locale: String?
    private(set) var push: PushRegistration?
    private var registeredPushSignature: String?

    /// Called (from the actor) whenever the server reports a new unread count, or on logout (0).
    private let onUnread: @Sendable (Int) -> Void
    /// Called (from the actor) for failures of background work (push registration, unread refresh).
    private let onError: @Sendable (LetsBotError) -> Void

    init(
        api: APIClient,
        store: SecureStore,
        onUnread: @escaping @Sendable (Int) -> Void = { _ in },
        onError: @escaping @Sendable (LetsBotError) -> Void = { _ in }
    ) {
        self.api = api
        configuration = api.configuration
        self.store = store
        tokenKey = "visitor.\(api.configuration.appKey)"
        userKey = "user.\(api.configuration.appKey)"
        locale = api.configuration.locale
        self.onUnread = onUnread
        self.onError = onError
    }

    // MARK: Session

    /// The stored visitor token, if any. Never creates a session.
    var storedToken: String? { store.string(for: tokenKey) }

    /// Returns the stored visitor token or creates a session. Concurrent callers share one request.
    func ensureSession() async throws -> String {
        if let token = storedToken { return token }
        return try await createSession()
    }

    /// Discards `staleToken` (if it is still the stored one) and creates a new session.
    func renewSession(discarding staleToken: String?) async throws -> String {
        if let current = storedToken {
            if current != staleToken { return current } // someone already renewed it
            store.remove(tokenKey)
            registeredPushSignature = nil
        }
        return try await createSession()
    }

    private func createSession() async throws -> String {
        if let sessionTask { return try await sessionTask.value }
        let body = SessionBody(
            locale: locale,
            device: .init(
                platform: DeviceInfo.platform,
                app_id: api.device.appId,
                app_version: api.device.appVersion,
                sdk: DeviceInfo.sdkHeader,
                os_version: api.device.osVersion
            ),
            ctx: context.isEmpty ? nil : context
        )
        let api = self.api
        let task = Task<String, Error> {
            try await api.send(.session, body: body, visitor: nil, as: SessionResponse.self).token
        }
        sessionTask = task
        defer { sessionTask = nil }
        let token = try await task.value
        guard !token.isEmpty else { throw LetsBotError.invalidResponse(status: 200) }
        store.set(token, for: tokenKey)
        registeredPushSignature = nil
        await registerPushIfNeeded()
        return token
    }

    /// Runs `operation` with a visitor token; on `invalid_visitor` creates a new session and retries once.
    func withVisitor<T>(_ operation: (String) async throws -> T) async throws -> T {
        let token = try await ensureSession()
        do {
            return try await operation(token)
        } catch LetsBotError.invalidVisitor {
            let fresh = try await renewSession(discarding: token)
            return try await operation(fresh)
        }
    }

    // MARK: Identity

    /// Verifies the logged-in user (API.md `POST identify`).
    ///
    /// If a *different* user was identified on this device without `logout()` in between, the previous visitor is
    /// logged out first, so the new user never sees the previous user's conversation.
    func identify(userId: String, identityToken: String, name: String?, email: String?, phone: String?) async throws {
        guard !userId.isEmpty, !identityToken.isEmpty else { throw LetsBotError.identityInvalid }
        let userHash = Self.hash(userId)
        if let previous = store.string(for: userKey), previous != userHash {
            await logout()
        }
        let body = IdentifyBody(identity_token: identityToken, name: name, email: email, phone: phone)
        let api = self.api
        let result = try await withVisitor { token in
            try await api.send(.identify, body: body, visitor: token, as: IdentifyResponse.self)
        }
        guard result.verified else { throw LetsBotError.identityInvalid }
        store.set(userHash, for: userKey)
    }

    /// Unlinks this device: server `logout` (removes push devices), then drops the local token and identity.
    /// Local state is always cleared, even when offline.
    func logout() async {
        if let token = storedToken {
            _ = try? await api.send(.logout, body: EmptyBody(), visitor: token, as: OkResponse.self)
        }
        store.remove(tokenKey)
        store.remove(userKey)
        registeredPushSignature = nil
        sessionTask?.cancel()
        sessionTask = nil
        onUnread(0)
    }

    // MARK: Push

    /// Remembers the push token; registers it now if a session exists, otherwise right after the first session is
    /// created (opening the chat or `identify`). Re-registers automatically after `logout()` / session renewal.
    func setPush(_ registration: PushRegistration) async {
        if push != registration { registeredPushSignature = nil }
        push = registration
        await registerPushIfNeeded()
    }

    func registerPushIfNeeded() async {
        guard let push, let visitor = storedToken else { return }
        let signature = "\(visitor.hashValue)|\(push.provider)|\(push.token)|\(locale ?? "")|\(push.sandbox)"
        guard signature != registeredPushSignature else { return }
        let body = DeviceBody(
            provider: push.provider,
            token: push.token,
            platform: DeviceInfo.platform,
            app_id: api.device.appId,
            app_version: api.device.appVersion,
            sdk: DeviceInfo.sdkHeader,
            locale: locale,
            sandbox: push.sandbox
        )
        do {
            _ = try await api.send(.putDevice, body: body, visitor: visitor, as: OkResponse.self)
            registeredPushSignature = signature
        } catch LetsBotError.invalidVisitor {
            store.remove(tokenKey) // a fresh session (and registration) is created lazily
        } catch let error as LetsBotError {
            onError(error)
        } catch {
            onError(.other(code: "unknown", status: nil))
        }
    }

    // MARK: Unread

    /// Fetches `GET unread`. Never creates a session: without one there is nothing unread.
    @discardableResult
    func refreshUnread() async -> Int? {
        guard let token = storedToken else {
            onUnread(0)
            return 0
        }
        do {
            let response = try await api.send(.unread, visitor: token, as: UnreadResponse.self)
            let count = max(0, response.count)
            onUnread(count)
            return count
        } catch LetsBotError.invalidVisitor {
            store.remove(tokenKey)
            registeredPushSignature = nil
            onUnread(0)
            return 0
        } catch let error as LetsBotError {
            if case .network = error { return nil } // offline: keep the last known count silently
            onError(error)
            return nil
        } catch {
            return nil
        }
    }

    // MARK: Context & locale

    func setContext(_ context: [String: String]) {
        self.context = context
    }

    func setLocale(_ locale: String?) async {
        guard self.locale != locale else { return }
        self.locale = locale
        registeredPushSignature = nil
        await registerPushIfNeeded()
    }

    // MARK: Helpers

    /// SHA-256 of the user id, so the Keychain never holds the raw id.
    static func hash(_ userId: String) -> String {
        SHA256.hash(data: Data(userId.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
