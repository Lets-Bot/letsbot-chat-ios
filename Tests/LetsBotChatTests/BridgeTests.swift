import XCTest
@testable import LetsBotChat

final class BridgeTests: XCTestCase {
    private let ui = URL(string: "https://letsbot.net/api/sdk/v1/lbk_1/ui?l=ar&theme=dark&p=ios")!

    // MARK: Events

    func testParsesEveryEvent() {
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"ready"}"#), .ready)
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"token_invalid"}"#), .tokenInvalid)
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"close"}"#), .close)
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"open_url","url":"https://acme.com/x"}"#),
                       .openURL(URL(string: "https://acme.com/x")!))
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"unread","count":4}"#), .unread(4))
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"unread","count":-1}"#), .unread(0))
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"message","t":"Hi"}"#), .message("Hi"))
        XCTAssertEqual(BridgeEvent.parse(#"{"lb":"error","code":"blocked"}"#), .error("blocked"))
    }

    func testAcceptsDictionaryBodies() {
        XCTAssertEqual(BridgeEvent.parse(["lb": "unread", "count": 2]), .unread(2))
    }

    func testRejectsMalformedOrUnsafe() {
        XCTAssertNil(BridgeEvent.parse("not json"))
        XCTAssertNil(BridgeEvent.parse(#"{"event":"ready"}"#))
        XCTAssertNil(BridgeEvent.parse(#"{"lb":"unknown"}"#))
        XCTAssertNil(BridgeEvent.parse(#"{"lb":"open_url","url":"javascript:alert(1)"}"#))
        XCTAssertNil(BridgeEvent.parse(#"{"lb":"open_url","url":"file:///etc/passwd"}"#))
        XCTAssertNil(BridgeEvent.parse(#"{"lb":"unread"}"#))
        XCTAssertNil(BridgeEvent.parse(#"{"lb":"error"}"#))
        XCTAssertNil(BridgeEvent.parse(42))
    }

    // MARK: Navigation

    func testOnlyTheUIURLLoadsInside() {
        XCTAssertEqual(NavigationPolicy.decide(ui, uiURL: ui), .allow)
        let otherQuery = URL(string: "https://letsbot.net/api/sdk/v1/lbk_1/ui?l=en")!
        XCTAssertEqual(NavigationPolicy.decide(otherQuery, uiURL: ui), .allow)
        XCTAssertEqual(NavigationPolicy.decide(URL(string: "about:blank"), uiURL: ui), .allow)
    }

    func testOtherWebURLsOpenExternally() {
        let sameHostOtherPath = URL(string: "https://letsbot.net/pricing")!
        XCTAssertEqual(NavigationPolicy.decide(sameHostOtherPath, uiURL: ui), .openExternally(sameHostOtherPath))
        let other = URL(string: "http://acme.com/order/1")!
        XCTAssertEqual(NavigationPolicy.decide(other, uiURL: ui), .openExternally(other))
        let lookalike = URL(string: "https://letsbot.net.evil.com/api/sdk/v1/lbk_1/ui")!
        XCTAssertEqual(NavigationPolicy.decide(lookalike, uiURL: ui), .openExternally(lookalike))
        let httpDowngrade = URL(string: "http://letsbot.net/api/sdk/v1/lbk_1/ui")!
        XCTAssertEqual(NavigationPolicy.decide(httpDowngrade, uiURL: ui), .openExternally(httpDowngrade))
    }

    func testNonWebSchemesAreCancelled() {
        for raw in ["tel:+123", "mailto:a@b.c", "javascript:alert(1)", "file:///tmp/x", "about:config", "data:text/html,x"] {
            XCTAssertEqual(NavigationPolicy.decide(URL(string: raw), uiURL: ui), .cancel, raw)
        }
        XCTAssertEqual(NavigationPolicy.decide(nil, uiURL: ui), .cancel)
    }

    func testSameOrigin() {
        let base = URL(string: "https://letsbot.net")!
        XCTAssertTrue(NavigationPolicy.isSameOrigin(URL(string: "https://LetsBot.net:443/x"), base))
        XCTAssertFalse(NavigationPolicy.isSameOrigin(URL(string: "https://letsbot.net:8443/x"), base))
        XCTAssertFalse(NavigationPolicy.isSameOrigin(URL(string: "https://sub.letsbot.net/x"), base))
        XCTAssertFalse(NavigationPolicy.isSameOrigin(nil, base))
        let local = URL(string: "http://localhost:8000")!
        XCTAssertTrue(NavigationPolicy.isSameOrigin(URL(string: "http://localhost:8000/api"), local))
    }

    // MARK: Native → page

    func testBootScript() throws {
        let payload = BridgeScript.bootPayload(token: "tok", appId: "com.acme.app", context: ["screen": "home"], color: "#0e7c66")
        let script = try XCTUnwrap(BridgeScript.call("boot", payload))
        XCTAssertEqual(
            script,
            ##"window.LetsBotHost && window.LetsBotHost.boot({"appId":"com.acme.app","color":"#0e7c66","context":{"screen":"home"},"platform":"ios","sdk":"ios\/0.1.0","token":"tok"});"##
        )
    }

    func testBootPayloadOmitsColorWhenNotSet() {
        let payload = BridgeScript.bootPayload(token: "t", appId: "a", context: [:], color: nil)
        XCTAssertNil(payload["color"])
    }

    func testScriptArgumentsAreEscaped() throws {
        XCTAssertEqual(BridgeScript.call("setTheme", "dark"), #"window.LetsBotHost && window.LetsBotHost.setTheme("dark");"#)
        let literal = try XCTUnwrap(BridgeScript.jsonLiteral(["k": "a\u{2028}b\"</script>"]))
        XCTAssertFalse(literal.contains("\u{2028}"))
        XCTAssertFalse(literal.contains("</"))
        XCTAssertTrue(literal.contains(#"\""#))
    }
}
