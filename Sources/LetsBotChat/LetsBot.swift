import UIKit
#if canImport(Combine)
import Combine
#endif

/// LetsBot In-App Chat.
///
/// ```swift
/// LetsBot.configure(appKey: "lb_app_…", locale: "ar", theme: .auto)
/// try await LetsBot.identify(userId: user.id, identityToken: tokenFromYourBackend, name: user.name)
/// LetsBot.present(from: self)
/// ```
///
/// Call the UI methods (`present`, `hide`, `handleNotification`) from the main thread. Everything else is
/// thread-safe. Delegate callbacks and observers are delivered on the main thread.
public enum LetsBot {
    /// SDK version (`0.2.1`).
    public static let sdkVersion = DeviceInfo.sdkVersion

    /// Posted on the main thread when ``unreadCount`` changes. `userInfo[LetsBot.unreadCountUserInfoKey]` is an `Int`.
    public static let unreadCountDidChangeNotification = Notification.Name("LetsBotUnreadCountDidChange")
    /// `userInfo` key of ``unreadCountDidChangeNotification``.
    public static let unreadCountUserInfoKey = "count"

    /// Receives open/close/message/unread/error events. Held weakly.
    public static var delegate: LetsBotDelegate? {
        get { runtime.delegate }
        set { runtime.delegate = newValue }
    }

    /// Whether ``configure(appKey:baseURL:locale:theme:color:)`` has been called.
    public static var isConfigured: Bool { runtime.engine != nil }

    // MARK: - Configuration

    /// Configures the SDK. Call once, as early as possible (`application(_:didFinishLaunchingWithOptions:)` or your
    /// SwiftUI `App.init`).
    ///
    /// - Parameters:
    ///   - appKey: The public App Key from LetsBot panel → Channels → In-App Chat. Safe to ship in the app.
    ///   - baseURL: LetsBot host. Defaults to `https://letsbot.net`; override only for staging.
    ///   - locale: The app's current language (`ar`, `en`, `es`, `pt`; others fall back to English). `nil` = automatic.
    ///   - theme: `.auto` (follow the presenting screen), `.light` or `.dark`.
    ///   - color: Optional brand colour; `nil` uses the colour configured in the LetsBot panel.
    public static func configure(
        appKey: String,
        baseURL: URL = URL(string: "https://letsbot.net")!,
        locale: String? = nil,
        theme: LetsBotTheme = .auto,
        color: UIColor? = nil
    ) {
        let configuration = LetsBotConfiguration(
            appKey: appKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL,
            locale: locale,
            theme: theme,
            colorHex: color.flatMap(ColorHex.string(from:))
        )
        let device = onMainSync { DeviceInfo.current() }
        let urlSession = URLSession(configuration: .ephemeral)
        configure(configuration: configuration, device: device, urlSession: urlSession, store: KeychainStore())
    }

    /// Internal entry point (tests inject the URL session, device info and store).
    static func configure(
        configuration: LetsBotConfiguration,
        device: DeviceInfo,
        urlSession: URLSession,
        store: SecureStore
    ) {
        guard !configuration.appKey.isEmpty else {
            Log.error("configure(appKey:) was called with an empty App Key")
            runtime.engine = nil
            notifyFailure(.notConfigured)
            return
        }
        let api = APIClient(configuration: configuration, device: device, session: urlSession)
        let engine = ChatEngine(
            api: api,
            store: store,
            onUnread: { count in LetsBot.runtime.setUnread(count) },
            onError: { error in LetsBot.notifyFailure(error) }
        )
        runtime.install(engine: engine, theme: configuration.theme)
        Task { await engine.refreshUnread() }
    }

    // MARK: - Identity

    /// Links the logged-in user of your app, verified by an identity token from **your** backend
    /// (JWT HS256 signed with the app's Identity Secret; `sub` = `userId`; `exp` ≤ 24 h recommended).
    ///
    /// Call right after login and on every app start while logged in. On ``LetsBotError/identityExpired`` fetch a new
    /// token and call again. If a different user was identified on this device before, that user is logged out first.
    public static func identify(
        userId: String,
        identityToken: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) async throws {
        guard let engine = runtime.engine else { throw LetsBotError.notConfigured }
        do {
            try await engine.identify(userId: userId, identityToken: identityToken, name: name, email: email, phone: phone)
            await engine.refreshUnread()
        } catch let error as LetsBotError {
            notifyFailure(error)
            throw error
        }
    }

    /// Completion-handler variant of ``identify(userId:identityToken:name:email:phone:)``. `completion` runs on main.
    public static func identify(
        userId: String,
        identityToken: String,
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        completion: ((Result<Void, LetsBotError>) -> Void)?
    ) {
        let completion = UncheckedSendable(completion)
        Task {
            let result: Result<Void, LetsBotError>
            do {
                try await identify(userId: userId, identityToken: identityToken, name: name, email: email, phone: phone)
                result = .success(())
            } catch let error as LetsBotError {
                result = .failure(error)
            } catch {
                result = .failure(.other(code: "unknown", status: nil))
            }
            onMain { completion.value?(result) }
        }
    }

    /// Call **before** clearing your own session when the user logs out: closes the chat, removes this device's push
    /// registration and starts a fresh anonymous conversation next time.
    public static func logout() async {
        await MainActor.run { hide(animated: false) }
        await runtime.engine?.logout()
    }

    /// Completion-handler variant of ``logout()``. `completion` runs on main.
    public static func logout(completion: (() -> Void)? = nil) {
        let completion = UncheckedSendable(completion)
        Task {
            await logout()
            onMain { completion.value?() }
        }
    }

    // MARK: - Chat screen

    /// Presents the chat screen modally from `viewController`.
    @MainActor
    public static func present(from viewController: UIViewController, animated: Bool = true) {
        guard isConfigured else {
            notifyFailure(.notConfigured)
            return
        }
        if let existing = runtime.presented, existing.presentingViewController != nil { return }
        let chat = LetsBotChatViewController()
        runtime.presented = chat
        viewController.present(chat, animated: animated)
    }

    /// Dismisses the chat screen opened with ``present(from:animated:)`` or ``handleNotification(_:)``.
    @MainActor
    public static func hide(animated: Bool = true) {
        guard let chat = runtime.presented, chat.presentingViewController != nil else { return }
        chat.dismiss(animated: animated)
        runtime.presented = nil
    }

    // MARK: - Context, locale, theme

    /// Tells the team and the AI assistant what the user is looking at (shown like "current page" on the web),
    /// e.g. `["screen": "order_details", "order_id": "1234"]`. Replaces the previous context.
    public static func setContext(_ context: [String: String]) {
        guard let engine = runtime.engine else { return }
        Task {
            await engine.setContext(context)
            await MainActor.run { runtime.forEachChat { $0.pushContext(context) } }
        }
    }

    /// Updates the chat language when the user switches the app's language. `nil` = automatic.
    public static func setLocale(_ locale: String?) {
        guard let engine = runtime.engine else { return }
        runtime.locale = locale
        Task {
            await engine.setLocale(locale)
            await MainActor.run { runtime.forEachChat { $0.reloadForLocaleChange() } }
        }
    }

    /// Updates the chat colour scheme.
    public static func setTheme(_ theme: LetsBotTheme) {
        runtime.theme = theme
        Task { @MainActor in runtime.forEachChat { $0.applyTheme() } }
    }

    // MARK: - Push

    /// Registers the APNs device token (call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`).
    ///
    /// - Parameter sandbox: APNs environment override. `nil` (default) detects it from the provisioning profile
    ///   (`aps-environment`), falling back to sandbox for simulator / `DEBUG` builds.
    public static func setPushToken(_ deviceToken: Data, sandbox: Bool? = nil) {
        guard !deviceToken.isEmpty else { return }
        let registration = ChatEngine.PushRegistration(
            provider: "apns",
            token: PushEnvironment.hex(deviceToken),
            sandbox: sandbox ?? PushEnvironment.current
        )
        setPush(registration)
    }

    /// Registers the Firebase Cloud Messaging registration token (call on start and in the token-refresh callback).
    public static func setPushToken(fcmToken: String) {
        let token = fcmToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        setPush(.init(provider: "fcm", token: token, sandbox: false))
    }

    private static func setPush(_ registration: ChatEngine.PushRegistration) {
        guard let engine = runtime.engine else {
            notifyFailure(.notConfigured)
            return
        }
        Task { await engine.setPush(registration) }
    }

    /// `true` when the notification payload was sent by LetsBot (`lb == "1"`).
    public static func isLetsBotNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        switch userInfo["lb"] {
        case let value as String: return value == "1"
        case let value as NSNumber: return value.intValue == 1
        default: return false
        }
    }

    /// Opens the chat for a LetsBot notification (foreground, background tap or cold start) and refreshes the
    /// unread count. Returns `false` (and does nothing) for notifications that are not from LetsBot.
    @discardableResult
    public static func handleNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard isLetsBotNotification(userInfo) else { return false }
        guard let engine = runtime.engine else {
            notifyFailure(.notConfigured)
            return true
        }
        Task { await engine.refreshUnread() }
        Task { @MainActor in runtime.openFromNotification() }
        return true
    }

    // MARK: - Unread

    /// Unread team / assistant messages (0 while the chat screen is visible).
    public static var unreadCount: Int { runtime.unread.value }

    /// Calls `handler` on main with the current count now and on every change. Keep the returned token.
    public static func observeUnreadCount(_ handler: @escaping (Int) -> Void) -> LetsBotObservation {
        runtime.unread.addObserver(handler)
    }

    #if canImport(Combine)
    /// Publishes the unread count (current value first), on the main thread.
    public static var unreadCountPublisher: AnyPublisher<Int, Never> { runtime.unread.publisher }
    #endif

    /// Fetches the unread count from LetsBot now. Called automatically on configure, when the app returns to the
    /// foreground and when the chat closes.
    public static func refreshUnreadCount() {
        guard let engine = runtime.engine else { return }
        Task { await engine.refreshUnread() }
    }

    // MARK: - Internal

    static let runtime = LetsBotRuntime()

    static func notifyFailure(_ error: LetsBotError) {
        Log.error("error \(error.code)")
        onMain { runtime.delegate?.letsBotDidFail(error) }
    }
}

/// Carries a main-thread-only value (e.g. a caller's completion handler) across a `Task` boundary.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Process-wide SDK state.
final class LetsBotRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var _engine: ChatEngine?
    private var _theme: LetsBotTheme = .auto
    private var _locale: String?

    let unread = UnreadCounter()

    // Main-thread state.
    weak var delegate: LetsBotDelegate?
    weak var presented: LetsBotChatViewController?
    private let visibleChats = NSHashTable<LetsBotChatViewController>.weakObjects()
    private var observers: [NSObjectProtocol] = []
    private var pendingNotificationOpen = false

    var engine: ChatEngine? {
        get { lock.lock(); defer { lock.unlock() }; return _engine }
        set { lock.lock(); _engine = newValue; lock.unlock() }
    }

    var theme: LetsBotTheme {
        get { lock.lock(); defer { lock.unlock() }; return _theme }
        set { lock.lock(); _theme = newValue; lock.unlock() }
    }

    var locale: String? {
        get { lock.lock(); defer { lock.unlock() }; return _locale }
        set { lock.lock(); _locale = newValue; lock.unlock() }
    }

    var configuration: LetsBotConfiguration? { engine?.configuration }

    func install(engine: ChatEngine, theme: LetsBotTheme) {
        self.engine = engine
        self.theme = theme
        locale = engine.configuration.locale
        unread.update(0)
        onMain { [self] in
            guard observers.isEmpty else { return }
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { _ in
                LetsBot.refreshUnreadCount()
            })
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.presentPendingNotificationChat() }
            })
        }
    }

    func setUnread(_ count: Int) {
        // While a chat screen is visible the page owns the count (it reports 0).
        unread.update(count) { [weak self] value in
            self?.delegate?.letsBotUnreadCountDidChange(value)
        }
    }

    func register(_ chat: LetsBotChatViewController) { visibleChats.add(chat) }
    func unregister(_ chat: LetsBotChatViewController) { visibleChats.remove(chat) }
    @MainActor func forEachChat(_ body: @MainActor (LetsBotChatViewController) -> Void) { visibleChats.allObjects.forEach(body) }
    var hasVisibleChat: Bool { !visibleChats.allObjects.isEmpty }

    @MainActor func openFromNotification() {
        if hasVisibleChat { return }
        guard let top = Self.topViewController() else {
            pendingNotificationOpen = true // cold start: present once the UI is up
            return
        }
        pendingNotificationOpen = false
        LetsBot.present(from: top)
    }

    @MainActor private func presentPendingNotificationChat() {
        guard pendingNotificationOpen else { return }
        openFromNotification()
    }

    @MainActor static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.filter { $0.activationState == .foregroundActive }.flatMap { $0.windows }
            + scenes.flatMap { $0.windows }
        guard let root = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController else { return nil }
        var top = root
        while true {
            if let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            } else if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
                if visible === top { break }
                top = visible
            } else if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
                top = selected
            } else {
                break
            }
        }
        return top
    }
}
