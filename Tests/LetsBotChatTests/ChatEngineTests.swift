import XCTest
@testable import LetsBotChat

final class ChatEngineTests: XCTestCase {
    private var store: MemoryStore!
    private var unread: Collector<Int>!
    private var errors: Collector<LetsBotError>!

    override func setUp() {
        super.setUp()
        MockServer.shared.reset()
        store = MemoryStore()
        unread = Collector()
        errors = Collector()
    }

    private func makeEngine(locale: String? = "ar") -> ChatEngine {
        let unread = self.unread!
        let errors = self.errors!
        return ChatEngine(
            api: Fixtures.api(Fixtures.configuration(locale: locale)),
            store: store,
            onUnread: { unread.append($0) },
            onError: { errors.append($0) }
        )
    }

    // MARK: Session

    func testCreatesSessionWithDeviceBodyAndStoresToken() async throws {
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        let engine = makeEngine()
        await engine.setContext(["screen": "order_details", "order_id": "1234"])

        let token = try await engine.ensureSession()

        XCTAssertEqual(token, Fixtures.token)
        XCTAssertEqual(store.string(for: "visitor.\(Fixtures.appKey)"), Fixtures.token)
        let body = try XCTUnwrap(MockServer.shared.requests("session").first?.json)
        XCTAssertEqual(body["locale"] as? String, "ar")
        let device = try XCTUnwrap(body["device"] as? [String: Any])
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(device["app_id"] as? String, "com.acme.app")
        XCTAssertEqual(device["app_version"] as? String, "2.3.0")
        XCTAssertEqual(device["sdk"] as? String, "ios/0.2.0")
        XCTAssertEqual(device["os_version"] as? String, "17.5")
        XCTAssertEqual(body["ctx"] as? [String: String], ["screen": "order_details", "order_id": "1234"])
    }

    func testReusesStoredToken() async throws {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        let token = try await makeEngine().ensureSession()
        XCTAssertEqual(token, Fixtures.token)
        XCTAssertTrue(MockServer.shared.requests("session").isEmpty)
    }

    func testConcurrentCallersShareOneSessionRequest() async throws {
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        let engine = makeEngine()
        let tokens = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for _ in 0..<8 { group.addTask { try await engine.ensureSession() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(Set(tokens), [Fixtures.token])
        XCTAssertEqual(MockServer.shared.requests("session").count, 1)
    }

    func testSessionErrorsPropagate() async {
        MockServer.shared.on("POST", "session", status: 403, json: ["error": "app_not_registered"])
        do {
            _ = try await makeEngine().ensureSession()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .appNotRegistered)
        }
        XCTAssertNil(store.string(for: "visitor.\(Fixtures.appKey)"))
    }

    // MARK: Identify

    func testIdentifySendsBodyAndRemembersUserHash() async throws {
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        MockServer.shared.on("POST", "identify", json: ["verified": true])
        let engine = makeEngine()

        try await engine.identify(userId: "u_42", identityToken: "jwt.value.sig", name: "Sara", email: "sara@x.com", phone: nil)

        let request = try XCTUnwrap(MockServer.shared.requests("identify").first)
        XCTAssertEqual(request.header("X-LB-Visitor"), Fixtures.token)
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["identity_token"] as? String, "jwt.value.sig")
        XCTAssertEqual(body["name"] as? String, "Sara")
        XCTAssertEqual(body["email"] as? String, "sara@x.com")
        XCTAssertNil(body["phone"], "nil fields are omitted")
        XCTAssertEqual(store.string(for: "user.\(Fixtures.appKey)"), ChatEngine.hash("u_42"))
        XCTAssertNotEqual(store.string(for: "user.\(Fixtures.appKey)"), "u_42", "raw user id never stored")
    }

    func testIdentifyMapsExpiredToken() async {
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        MockServer.shared.on("POST", "identify", status: 401, json: ["error": "identity_expired"])
        do {
            try await makeEngine().identify(userId: "u", identityToken: "jwt", name: nil, email: nil, phone: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .identityExpired)
        }
    }

    func testIdentifyRecoversFromInvalidVisitorOnce() async throws {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token2])
        MockServer.shared.on("POST", "identify", status: 401, json: ["error": "invalid_visitor"])
        MockServer.shared.on("POST", "identify", json: ["verified": true])

        try await makeEngine().identify(userId: "u", identityToken: "jwt", name: nil, email: nil, phone: nil)

        let identifies = MockServer.shared.requests("identify")
        XCTAssertEqual(identifies.map { $0.header("X-LB-Visitor") }, [Fixtures.token, Fixtures.token2])
        XCTAssertEqual(store.string(for: "visitor.\(Fixtures.appKey)"), Fixtures.token2)
    }

    func testIdentifyingADifferentUserLogsOutThePreviousOne() async throws {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        store.set(ChatEngine.hash("alice"), for: "user.\(Fixtures.appKey)")
        MockServer.shared.on("POST", "logout", json: ["ok": true])
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token2])
        MockServer.shared.on("POST", "identify", json: ["verified": true])

        try await makeEngine().identify(userId: "bob", identityToken: "jwt", name: nil, email: nil, phone: nil)

        XCTAssertEqual(MockServer.shared.requests("logout").first?.header("X-LB-Visitor"), Fixtures.token)
        XCTAssertEqual(MockServer.shared.requests("identify").first?.header("X-LB-Visitor"), Fixtures.token2)
        XCTAssertEqual(store.string(for: "user.\(Fixtures.appKey)"), ChatEngine.hash("bob"))
    }

    func testIdentifySameUserAgainKeepsConversation() async throws {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        store.set(ChatEngine.hash("alice"), for: "user.\(Fixtures.appKey)")
        MockServer.shared.on("POST", "identify", json: ["verified": true])

        try await makeEngine().identify(userId: "alice", identityToken: "jwt", name: nil, email: nil, phone: nil)

        XCTAssertTrue(MockServer.shared.requests("logout").isEmpty)
        XCTAssertTrue(MockServer.shared.requests("session").isEmpty)
    }

    func testIdentifyRejectsEmptyInput() async {
        do {
            try await makeEngine().identify(userId: "", identityToken: "jwt", name: nil, email: nil, phone: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .identityInvalid)
        }
        XCTAssertTrue(MockServer.shared.requests.isEmpty)
    }

    // MARK: Logout

    func testLogoutCallsServerAndClearsLocalState() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        store.set(ChatEngine.hash("alice"), for: "user.\(Fixtures.appKey)")
        MockServer.shared.on("POST", "logout", json: ["ok": true])

        await makeEngine().logout()

        XCTAssertEqual(MockServer.shared.requests("logout").count, 1)
        XCTAssertNil(store.string(for: "visitor.\(Fixtures.appKey)"))
        XCTAssertNil(store.string(for: "user.\(Fixtures.appKey)"))
        XCTAssertEqual(unread.values.last, 0)
    }

    func testLogoutClearsLocalStateWhenOffline() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("POST", "logout") { _ in .init(networkError: .notConnectedToInternet) }
        await makeEngine().logout()
        XCTAssertNil(store.string(for: "visitor.\(Fixtures.appKey)"))
    }

    func testLogoutWithoutSessionMakesNoRequest() async {
        await makeEngine().logout()
        XCTAssertTrue(MockServer.shared.requests.isEmpty)
    }

    // MARK: Push

    func testPushTokenWaitsForSessionThenRegisters() async throws {
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        MockServer.shared.on("PUT", "device", json: ["ok": true])
        let engine = makeEngine()

        await engine.setPush(.init(provider: "apns", token: "a1b2", sandbox: true))
        XCTAssertTrue(MockServer.shared.requests.isEmpty, "no session is created just for push")

        _ = try await engine.ensureSession()

        let request = try XCTUnwrap(MockServer.shared.requests("device").first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.header("X-LB-Visitor"), Fixtures.token)
        let body = try XCTUnwrap(request.json)
        XCTAssertEqual(body["provider"] as? String, "apns")
        XCTAssertEqual(body["token"] as? String, "a1b2")
        XCTAssertEqual(body["platform"] as? String, "ios")
        XCTAssertEqual(body["app_id"] as? String, "com.acme.app")
        XCTAssertEqual(body["app_version"] as? String, "2.3.0")
        XCTAssertEqual(body["sdk"] as? String, "ios/0.2.0")
        XCTAssertEqual(body["locale"] as? String, "ar")
        XCTAssertEqual(body["sandbox"] as? Bool, true)
    }

    func testPushTokenRegistersImmediatelyWithSessionAndOnlyOnce() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("PUT", "device", json: ["ok": true])
        let engine = makeEngine()
        let registration = ChatEngine.PushRegistration(provider: "fcm", token: "fcm-token", sandbox: false)

        await engine.setPush(registration)
        await engine.setPush(registration)

        XCTAssertEqual(MockServer.shared.requests("device").count, 1)
        XCTAssertEqual(MockServer.shared.requests("device").first?.json?["provider"] as? String, "fcm")
    }

    func testLocaleChangeReRegistersPushDevice() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("PUT", "device", json: ["ok": true])
        let engine = makeEngine()
        await engine.setPush(.init(provider: "fcm", token: "t", sandbox: false))
        await engine.setLocale("en")
        let locales = MockServer.shared.requests("device").map { $0.json?["locale"] as? String }
        XCTAssertEqual(locales, ["ar", "en"])
    }

    func testPushRegistrationErrorsAreReported() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("PUT", "device", status: 403, json: ["error": "app_not_registered"])
        await makeEngine().setPush(.init(provider: "fcm", token: "t", sandbox: false))
        XCTAssertEqual(errors.values, [.appNotRegistered])
    }

    // MARK: Unread

    func testRefreshUnreadReportsCount() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("GET", "unread", json: ["count": 3, "last": ["t": "Your order shipped", "at": "2026-10-08T12:00:00+03:00"]])
        let count = await makeEngine().refreshUnread()
        XCTAssertEqual(count, 3)
        XCTAssertEqual(unread.values, [3])
    }

    func testRefreshUnreadWithoutSessionIsZeroAndOffline() async {
        let count = await makeEngine().refreshUnread()
        XCTAssertEqual(count, 0)
        XCTAssertTrue(MockServer.shared.requests.isEmpty, "never creates a session")
    }

    func testRefreshUnreadDropsInvalidVisitor() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("GET", "unread", status: 401, json: ["error": "invalid_visitor"])
        let count = await makeEngine().refreshUnread()
        XCTAssertEqual(count, 0)
        XCTAssertNil(store.string(for: "visitor.\(Fixtures.appKey)"))
        XCTAssertTrue(errors.values.isEmpty)
    }

    func testRefreshUnreadOfflineKeepsLastValueSilently() async {
        store.set(Fixtures.token, for: "visitor.\(Fixtures.appKey)")
        MockServer.shared.on("GET", "unread") { _ in .init(networkError: .timedOut) }
        let count = await makeEngine().refreshUnread()
        XCTAssertNil(count)
        XCTAssertTrue(unread.values.isEmpty)
        XCTAssertTrue(errors.values.isEmpty)
    }

    // MARK: Renewal

    func testRenewSessionIgnoresAlreadyRenewedToken() async throws {
        store.set(Fixtures.token2, for: "visitor.\(Fixtures.appKey)")
        let token = try await makeEngine().renewSession(discarding: Fixtures.token)
        XCTAssertEqual(token, Fixtures.token2)
        XCTAssertTrue(MockServer.shared.requests.isEmpty)
    }
}
