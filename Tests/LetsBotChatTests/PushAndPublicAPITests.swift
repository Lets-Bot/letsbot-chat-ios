import XCTest
@testable import LetsBotChat

final class PushAndPublicAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockServer.shared.reset()
    }

    // MARK: Notifications

    func testRecognisesLetsBotNotifications() {
        XCTAssertTrue(LetsBot.isLetsBotNotification(["lb": "1", "lb_k": "k", "lb_c": "12", "aps": [:]]))
        XCTAssertTrue(LetsBot.isLetsBotNotification(["lb": NSNumber(value: 1)]))
        XCTAssertFalse(LetsBot.isLetsBotNotification(["lb": "0"]))
        XCTAssertFalse(LetsBot.isLetsBotNotification(["aps": ["alert": "x"]]))
        XCTAssertFalse(LetsBot.isLetsBotNotification([:]))
    }

    func testHandleNotificationIgnoresForeignPayloads() {
        XCTAssertFalse(LetsBot.handleNotification(["from": "another-sdk"]))
    }

    // MARK: APNs

    func testDeviceTokenHex() {
        let data = Data([0x00, 0x01, 0xab, 0xff, 0x10])
        XCTAssertEqual(PushEnvironment.hex(data), "0001abff10")
    }

    func testSandboxFromProvisioningProfile() {
        XCTAssertTrue(PushEnvironment.isSandbox(provisionData: profile("development"), isDebug: false, isSimulator: false))
        XCTAssertFalse(PushEnvironment.isSandbox(provisionData: profile("production"), isDebug: true, isSimulator: false))
    }

    func testSandboxFallbacks() {
        XCTAssertFalse(PushEnvironment.isSandbox(provisionData: nil, isDebug: false, isSimulator: false), "App Store")
        XCTAssertTrue(PushEnvironment.isSandbox(provisionData: nil, isDebug: true, isSimulator: false))
        XCTAssertTrue(PushEnvironment.isSandbox(provisionData: nil, isDebug: false, isSimulator: true))
        XCTAssertTrue(PushEnvironment.isSandbox(provisionData: Data("garbage".utf8), isDebug: true, isSimulator: false))
    }

    func testReadsApsEnvironment() {
        XCTAssertEqual(PushEnvironment.apsEnvironment(fromProvision: profile("development")), "development")
        XCTAssertNil(PushEnvironment.apsEnvironment(fromProvision: Data("<?xml no plist".utf8)))
    }

    /// Fake `embedded.mobileprovision`: binary CMS noise around an XML plist.
    private func profile(_ environment: String) -> Data {
        var data = Data([0x30, 0x82, 0x01, 0x02, 0x06, 0x09])
        data.append(Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>Name</key><string>Acme</string>
        <key>Entitlements</key><dict><key>aps-environment</key><string>\(environment)</string></dict>
        </dict></plist>
        """.utf8))
        data.append(Data([0xa0, 0x82, 0x0b, 0x00]))
        return data
    }

    // MARK: Errors

    func testErrorCodesRoundTrip() {
        let codes = ["not_found", "app_not_registered", "invalid_visitor", "identity_invalid", "identity_expired",
                     "blocked", "invalid", "too_long", "invalid_contact", "consent_required", "file_too_big",
                     "file_type", "slow_down", "busy"]
        for code in codes {
            let error = LetsBotError(code: code)
            XCTAssertEqual(error.code, code)
            XCTAssertNotEqual(error, .other(code: code, status: nil), code)
            XCTAssertNotNil(error.errorDescription)
        }
        XCTAssertEqual(LetsBotError(code: "push_credentials_missing").code, "push_credentials_missing")
        XCTAssertEqual(LetsBotError.notConfigured.code, "not_configured")
    }

    // MARK: Unread counter

    func testUnreadObserversNotificationAndPublisher() {
        let counter = UnreadCounter()
        var observed: [Int] = []
        let observation = counter.addObserver { observed.append($0) }
        var published: [Int] = []
        let cancellable = counter.publisher.sink { published.append($0) }
        let notified = expectation(forNotification: LetsBot.unreadCountDidChangeNotification, object: nil) { note in
            note.userInfo?[LetsBot.unreadCountUserInfoKey] as? Int == 5
        }

        counter.update(5)
        counter.update(5) // unchanged → no second callback

        wait(for: [notified], timeout: 2)
        XCTAssertEqual(observed, [0, 5])
        XCTAssertEqual(published, [0, 5])
        XCTAssertEqual(counter.value, 5)

        observation.cancel()
        counter.update(1)
        let drained = expectation(description: "main")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(observed, [0, 5], "cancelled observers get nothing")
        cancellable.cancel()
    }

    func testColorHex() {
        XCTAssertEqual(ColorHex.string(from: UIColor(red: 14 / 255, green: 124 / 255, blue: 102 / 255, alpha: 1)), "#0e7c66")
        XCTAssertEqual(ColorHex.string(from: .white), "#ffffff")
    }

    // MARK: Facade

    func testFacadeEndToEndWithMock() async throws {
        let store = MemoryStore()
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        MockServer.shared.on("POST", "identify", json: ["verified": true])
        MockServer.shared.on("GET", "unread", json: ["count": 2, "last": NSNull()])
        MockServer.shared.on("PUT", "device", json: ["ok": true])
        MockServer.shared.on("POST", "logout", json: ["ok": true])

        LetsBot.configure(configuration: Fixtures.configuration(), device: Fixtures.device,
                          urlSession: MockServer.makeSession(), store: store)
        XCTAssertTrue(LetsBot.isConfigured)

        try await LetsBot.identify(userId: "u_1", identityToken: "jwt")
        XCTAssertEqual(store.string(for: "visitor.\(Fixtures.appKey)"), Fixtures.token)
        try await waitUntil { LetsBot.unreadCount == 2 }

        LetsBot.setPushToken(Data([0xde, 0xad, 0xbe, 0xef]), sandbox: false)
        try await waitUntil { !MockServer.shared.requests("device").isEmpty }
        XCTAssertEqual(MockServer.shared.requests("device").first?.json?["token"] as? String, "deadbeef")
        XCTAssertEqual(MockServer.shared.requests("device").first?.json?["sandbox"] as? Bool, false)

        await LetsBot.logout()
        XCTAssertNil(store.string(for: "visitor.\(Fixtures.appKey)"))
        try await waitUntil { LetsBot.unreadCount == 0 }
    }

    func testCompletionVariantReportsNotConfigured() {
        LetsBot.configure(configuration: { var c = Fixtures.configuration(); c.appKey = ""; return c }(),
                          device: Fixtures.device, urlSession: MockServer.makeSession(), store: MemoryStore())
        XCTAssertFalse(LetsBot.isConfigured)
        let done = expectation(description: "completion")
        LetsBot.identify(userId: "u", identityToken: "t", completion: { result in
            XCTAssertTrue(Thread.isMainThread)
            if case let .failure(error) = result { XCTAssertEqual(error, .notConfigured) } else { XCTFail() }
            done.fulfill()
        })
        wait(for: [done], timeout: 2)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("condition not met in time"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
