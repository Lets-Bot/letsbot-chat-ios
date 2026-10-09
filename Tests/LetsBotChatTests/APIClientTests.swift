import XCTest
@testable import LetsBotChat

final class APIClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockServer.shared.reset()
    }

    func testBuildsRouteURLUnderAppKey() {
        let api = Fixtures.api()
        XCTAssertEqual(
            api.url(for: .session).absoluteString,
            "https://letsbot.test/api/sdk/v1/lbk_test_123/session"
        )
        let ui = api.url(for: .ui, query: [URLQueryItem(name: "l", value: "ar"), URLQueryItem(name: "p", value: "ios")])
        XCTAssertEqual(ui.absoluteString, "https://letsbot.test/api/sdk/v1/lbk_test_123/ui?l=ar&p=ios")
    }

    func testDefaultBaseURLIsLetsBot() {
        var config = Fixtures.configuration()
        config.baseURL = LetsBotConfiguration.defaultBaseURL
        XCTAssertEqual(config.apiRoot.absoluteString, "https://letsbot.net/api/sdk/v1/lbk_test_123")
    }

    func testAppKeyIsPathEscaped() {
        var config = Fixtures.configuration()
        config.appKey = "a/b?c"
        XCTAssertFalse(config.apiRoot.absoluteString.contains("a/b?c"))
    }

    func testSendsRequiredHeaders() async throws {
        MockServer.shared.on("POST", "session", json: ["token": Fixtures.token])
        let api = Fixtures.api()
        _ = try await api.send(.session, body: EmptyBody(), visitor: nil, as: SessionResponse.self)
        let request = try XCTUnwrap(MockServer.shared.requests("session").first)
        XCTAssertEqual(request.header("X-LB-App-Id"), "com.acme.app")
        XCTAssertEqual(request.header("X-LB-Platform"), "ios")
        XCTAssertEqual(request.header("X-LB-SDK"), "ios/0.2.0")
        XCTAssertEqual(request.header("Accept"), "application/json")
        XCTAssertEqual(request.header("Content-Type"), "application/json")
        XCTAssertNil(request.header("X-LB-Visitor"))
        XCTAssertNil(request.header("Cookie"))
    }

    func testSendsVisitorHeaderAndNoContentTypeWithoutBody() async throws {
        MockServer.shared.on("GET", "unread", json: ["count": 2, "last": NSNull()])
        let api = Fixtures.api()
        let response = try await api.send(.unread, visitor: Fixtures.token, as: UnreadResponse.self)
        XCTAssertEqual(response.count, 2)
        let request = try XCTUnwrap(MockServer.shared.requests("unread").first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.header("X-LB-Visitor"), Fixtures.token)
        XCTAssertNil(request.header("Content-Type"))
    }

    func testVisitorRoutesFailFastWithoutToken() async {
        let api = Fixtures.api()
        do {
            _ = try await api.send(.unread, visitor: nil, as: UnreadResponse.self)
            XCTFail("expected invalidVisitor")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .invalidVisitor)
        }
        XCTAssertTrue(MockServer.shared.requests.isEmpty)
    }

    func testMapsEveryAPIErrorCode() async {
        let cases: [(Int, String, LetsBotError)] = [
            (404, "not_found", .notFound),
            (403, "app_not_registered", .appNotRegistered),
            (401, "invalid_visitor", .invalidVisitor),
            (401, "identity_invalid", .identityInvalid),
            (401, "identity_expired", .identityExpired),
            (403, "blocked", .blocked),
            (422, "invalid", .invalid),
            (422, "too_long", .tooLong),
            (422, "invalid_contact", .invalidContact),
            (422, "consent_required", .consentRequired),
            (422, "file_too_big", .fileTooBig),
            (422, "file_type", .fileType),
            (429, "slow_down", .slowDown(retryAfter: nil)),
            (429, "busy", .busy(retryAfter: nil)),
            (418, "teapot", .other(code: "teapot", status: 418)),
        ]
        let api = Fixtures.api()
        for (status, code, expected) in cases {
            MockServer.shared.reset()
            MockServer.shared.on("GET", "config", status: status, json: ["error": code])
            do {
                _ = try await api.send(.config, visitor: nil, as: OkResponse.self)
                XCTFail("expected \(code)")
            } catch {
                XCTAssertEqual(error as? LetsBotError, expected, code)
                XCTAssertEqual((error as? LetsBotError)?.code, code)
            }
        }
    }

    func testHonoursRetryAfter() async {
        MockServer.shared.on("GET", "config", status: 429, json: ["error": "slow_down"], headers: ["Retry-After": "12"])
        do {
            _ = try await Fixtures.api().send(.config, visitor: nil, as: OkResponse.self)
            XCTFail("expected slow_down")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .slowDown(retryAfter: 12))
        }
    }

    func testNonJSONErrorsFallBackToStatus() async {
        MockServer.shared.on("GET", "config", status: 502, json: "<html>Bad gateway</html>")
        do {
            _ = try await Fixtures.api().send(.config, visitor: nil, as: OkResponse.self)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .invalidResponse(status: 502))
        }
    }

    func testNetworkErrorsAreTyped() async {
        MockServer.shared.on("GET", "config") { _ in .init(networkError: .notConnectedToInternet) }
        do {
            _ = try await Fixtures.api().send(.config, visitor: nil, as: OkResponse.self)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .network(urlErrorCode: URLError.Code.notConnectedToInternet.rawValue))
        }
    }

    func testUndecodableSuccessIsInvalidResponse() async {
        MockServer.shared.on("POST", "session", json: ["nope": true])
        do {
            _ = try await Fixtures.api().send(.session, body: EmptyBody(), visitor: nil, as: SessionResponse.self)
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? LetsBotError, .invalidResponse(status: 200))
        }
    }
}
