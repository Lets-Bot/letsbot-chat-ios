import Security
import WebKit
import XCTest
@testable import LetsBotChat

/// Runs inside the example app (a real app host with a keychain entitlement), so the Keychain store is exercised
/// for real. The package's own hostless test bundle skips this check on the simulator.
final class HostedKeychainTests: XCTestCase {
    func testVisitorTokenIsStoredInKeychainThisDeviceOnly() throws {
        let store = KeychainStore(service: "net.letsbot.chat.hosted-tests.\(UUID().uuidString)")
        let key = "visitor.example"
        XCTAssertTrue(store.set("token-1", for: key), "OSStatus \(store.lastStatus)")
        XCTAssertEqual(store.string(for: key), "token-1")
        XCTAssertTrue(store.set("token-2", for: key))
        XCTAssertEqual(store.string(for: key), "token-2")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)

        XCTAssertTrue(store.remove(key))
        XCTAssertNil(store.string(for: key))
    }

    func testChatViewControllerLoadsWithoutRetainCycle() {
        weak var weakController: LetsBotChatViewController?
        autoreleasepool {
            let controller = LetsBotChatViewController()
            controller.loadViewIfNeeded()
            weakController = controller
        }
        XCTAssertNil(weakController, "script message handler proxy must not retain the controller")
    }

    /// Guards against delegate methods silently not matching WebKit's signatures (e.g. missing `@MainActor
    /// @Sendable` on completion handlers): an unmatched optional requirement is never called, which would disable
    /// the navigation lock.
    func testNavigationDelegateMethodsAreWitnessedAndLockNavigation() {
        let controller = LetsBotChatViewController()
        controller.loadViewIfNeeded()
        let webView = WKWebView()
        let delegate: WKNavigationDelegate = controller
        let action = FakeNavigationAction(url: URL(string: "javascript:alert(1)")!)
        var decision: WKNavigationActionPolicy?
        let called: Void? = delegate.webView?(webView, decidePolicyFor: action) { decision = $0 }
        XCTAssertNotNil(called, "decidePolicyFor navigationAction is not a protocol witness")
        XCTAssertEqual(decision, .cancel)

        let uiDelegate: WKUIDelegate = controller
        let created = uiDelegate.webView?(webView, createWebViewWith: WKWebViewConfiguration(), for: action,
                                          windowFeatures: WKWindowFeatures())
        XCTAssertNil(created ?? nil, "never opens a second web view")
        XCTAssertNotNil(controller as WKScriptMessageHandler)
    }
}

/// `WKNavigationAction` with a settable request, for driving the navigation delegate directly.
private final class FakeNavigationAction: WKNavigationAction {
    private let fakeRequest: URLRequest
    init(url: URL) {
        fakeRequest = URLRequest(url: url)
        super.init()
    }

    override var request: URLRequest { fakeRequest }
    override var targetFrame: WKFrameInfo? { nil }
    override var navigationType: WKNavigationType { .other }
}
