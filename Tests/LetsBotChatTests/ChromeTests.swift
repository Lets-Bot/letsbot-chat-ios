import UIKit
import XCTest
@testable import LetsBotChat

final class ChromeTests: XCTestCase {
    func testNeutralChromeUsesBrandColourForTheHeader() {
        let branded = ChatChrome.neutral(dark: false, brandColor: "#0E7C66")
        XCTAssertEqual(branded, ChatChrome(lightStatusBar: true, header: "#0e7c66", background: "#ffffff"))
        XCTAssertFalse(ChatChrome.neutral(dark: false, brandColor: nil).lightStatusBar)
        XCTAssertTrue(ChatChrome.neutral(dark: true, brandColor: nil).lightStatusBar)
        XCTAssertEqual(ChatChrome.neutral(dark: true, brandColor: "nope").header, "#111418")
    }

    func testStatusBarStyleFollowsTheHeader() {
        XCTAssertEqual(ChatChrome(lightStatusBar: true, header: "#0e7c66", background: "#fff000").statusBarStyle,
                       .lightContent)
        XCTAssertEqual(ChatChrome(lightStatusBar: false, header: "#ffffff", background: "#ffffff").statusBarStyle,
                       .darkContent)
    }

    func testMergesAChromeEvent() {
        let base = ChatChrome(lightStatusBar: true, header: "#0e7c66", background: "#ffffff")
        let merged = base.merged(with: ChromeEvent(lightStatusBar: false, header: nil, background: "#000000"))
        XCTAssertEqual(merged, ChatChrome(lightStatusBar: false, header: "#0e7c66", background: "#000000"))
    }

    func testColourHelpers() {
        XCTAssertEqual(ChatChrome.normalizedHex("#ABCDEF"), "#abcdef")
        XCTAssertNil(ChatChrome.normalizedHex("abcdef"))
        XCTAssertNil(ChatChrome.normalizedHex("#abcdeg"))
        XCTAssertTrue(ChatChrome.isDark("#0e7c66"))
        XCTAssertFalse(ChatChrome.isDark("#f5f7f9"))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ChatChrome.color("#ff8000").getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 1, accuracy: 0.001)
        XCTAssertEqual(green, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(blue, 0, accuracy: 0.001)
    }

    func testCachesChromePerAppAndTheme() throws {
        let suite = "letsbot.chrome.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = ChromeCache(defaults: defaults)
        let base = URL(string: "https://letsbot.net")!
        let chrome = ChatChrome(lightStatusBar: true, header: "#0e7c66", background: "#f5f7f9")

        XCTAssertNil(cache.load(baseURL: base, appKey: "lbk_1", theme: "light"))
        cache.save(chrome, baseURL: base, appKey: "lbk_1", theme: "light")
        XCTAssertEqual(cache.load(baseURL: base, appKey: "lbk_1", theme: "light"), chrome)
        XCTAssertNil(cache.load(baseURL: base, appKey: "lbk_1", theme: "dark"))
        XCTAssertNil(cache.load(baseURL: base, appKey: "lbk_2", theme: "light"))

        defaults.set(Data("{}".utf8), forKey: ChromeCache.key(baseURL: base, appKey: "lbk_3", theme: "light"))
        XCTAssertNil(cache.load(baseURL: base, appKey: "lbk_3", theme: "light"))
    }

    @MainActor
    func testScreenIsFullScreenAndEdgeToEdge() {
        let chat = LetsBotChatViewController()
        XCTAssertEqual(chat.modalPresentationStyle, .fullScreen)
        XCTAssertTrue(chat.modalPresentationCapturesStatusBarAppearance)
    }
}
