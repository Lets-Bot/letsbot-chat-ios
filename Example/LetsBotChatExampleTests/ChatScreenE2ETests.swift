import UIKit
import WebKit
import XCTest
@testable import LetsBotChat

/// End-to-end check of the chat screen + JS bridge against `Scripts/mock_server.py`.
///
/// Skipped unless the scheme / test runner provides `LETSBOT_E2E_BASE_URL` (e.g.
/// `TEST_RUNNER_LETSBOT_E2E_BASE_URL=http://127.0.0.1:8765 xcodebuild test …`).
final class ChatScreenE2ETests: XCTestCase, LetsBotDelegate {
    private var messages: [String] = []
    private var messageExpectation: XCTestExpectation?
    private var opened = false

    private var failures: [String] = []

    func letsBotDidOpen() { opened = true }
    func letsBotDidFail(_ error: LetsBotError) { failures.append(error.code) }
    func letsBotDidReceiveMessage(_ text: String) {
        messages.append(text)
        messageExpectation?.fulfill()
    }

    func testBootsTheHostedScreenThroughTheBridge() throws {
        guard let raw = ProcessInfo.processInfo.environment["LETSBOT_E2E_BASE_URL"], let base = URL(string: raw) else {
            throw XCTSkip("Set LETSBOT_E2E_BASE_URL to run against Scripts/mock_server.py")
        }
        LetsBot.configure(
            configuration: LetsBotConfiguration(appKey: "lbk_e2e", baseURL: base, locale: "ar", theme: .dark,
                                                colorHex: "#0e7c66"),
            device: DeviceInfo(appId: "net.letsbot.chat.example", appVersion: "0.1.0", osVersion: "17.0"),
            urlSession: URLSession(configuration: .ephemeral),
            store: MemoryStore()
        )
        LetsBot.delegate = self
        LetsBot.setContext(["screen": "e2e"])

        let chat = LetsBotChatViewController()
        let closed = expectation(description: "close event")
        chat.onClose = { closed.fulfill() }
        messageExpectation = expectation(description: "boot echoed")

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = chat
        window.makeKeyAndVisible()

        wait(for: [messageExpectation!], timeout: 120) // first WebContent launch on a cold simulator can be slow
        XCTAssertTrue(opened)
        XCTAssertEqual(failures, [], "delegate errors")

        let boot = try XCTUnwrap(messages.first.flatMap { $0.data(using: .utf8) })
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: boot) as? [String: Any])
        XCTAssertEqual(payload["platform"] as? String, "ios")
        XCTAssertEqual(payload["sdk"] as? String, "ios/0.2.0")
        XCTAssertEqual(payload["appId"] as? String, "net.letsbot.chat.example")
        XCTAssertEqual(payload["color"] as? String, "#0e7c66")
        XCTAssertEqual(payload["context"] as? [String: String], ["screen": "e2e"])
        XCTAssertEqual((payload["token"] as? String)?.count, 84)
        let insets = try XCTUnwrap(payload["insets"] as? [String: Double])
        XCTAssertEqual(Set(insets.keys), ["top", "bottom", "left", "right"])
        XCTAssertEqual(try XCTUnwrap(insets["top"]), Double(chat.view.safeAreaInsets.top), accuracy: 0.01)

        // Edge-to-edge web view + chrome event (sent by the mock page before the echo).
        let webView = try XCTUnwrap(findWebView(in: chat.view) as? WKWebView)
        chat.view.layoutIfNeeded()
        XCTAssertFalse(chat.view.bounds.isEmpty)
        XCTAssertEqual(webView.frame, chat.view.bounds)
        XCTAssertEqual(webView.scrollView.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(chat.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(chat.view.backgroundColor, ChatChrome.color("#f5f7f9"))
        XCTAssertEqual(
            LetsBotChatViewController.chromeCache.load(baseURL: base, appKey: "lbk_e2e", theme: "dark"),
            ChatChrome(lightStatusBar: true, header: "#0e7c66", background: "#f5f7f9")
        )

        // Native → page after boot.
        messageExpectation = expectation(description: "context pushed")
        LetsBot.setContext(["screen": "order", "order_id": "7"])
        wait(for: [messageExpectation!], timeout: 10)
        XCTAssertEqual(messages.last, #"ctx:{"order_id":"7","screen":"order"}"#)

        // Page → native close.
        webView.evaluateJavaScript("window.lbClose()", completionHandler: nil)
        wait(for: [closed], timeout: 10)

        window.isHidden = true
        LetsBot.delegate = nil
    }

    private func findWebView(in view: UIView) -> UIView? {
        if view is WKWebView { return view }
        for sub in view.subviews { if let found = findWebView(in: sub) { return found } }
        return nil
    }
}

