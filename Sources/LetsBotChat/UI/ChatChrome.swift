import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Colours of the hosted page's chrome (API.md §8.1): status-bar icon style over the header, header colour and page
/// background. Reported by the page with `{"lb":"chrome",...}`; cached per app + theme so the next chat opens with the
/// right colours before the page paints.
struct ChatChrome: Equatable, Codable {
    /// `true` = light (white) status-bar icons.
    var lightStatusBar: Bool
    /// `#rrggbb`, lower case.
    var header: String
    /// `#rrggbb`, lower case.
    var background: String

    static let lightBackground = "#ffffff"
    static let darkBackground = "#111418"

    /// Used before the page reports its chrome and nothing is cached: the app's brand colour as header (when set),
    /// otherwise the plain light/dark background.
    static func neutral(dark: Bool, brandColor: String?) -> ChatChrome {
        let background = dark ? darkBackground : lightBackground
        let header = brandColor.flatMap(normalizedHex) ?? background
        return ChatChrome(lightStatusBar: isDark(header), header: header, background: background)
    }

    /// Applies a `chrome` event; colours it omits keep their current value.
    func merged(with event: ChromeEvent) -> ChatChrome {
        ChatChrome(
            lightStatusBar: event.lightStatusBar,
            header: event.header ?? header,
            background: event.background ?? background
        )
    }

    // MARK: Colours

    /// `#RRGGBB` / `#rrggbb` → lower case; `nil` for anything else.
    static func normalizedHex(_ value: String) -> String? {
        guard value.count == 7, value.first == "#",
              value.dropFirst().allSatisfy({ $0.isHexDigit && $0.isASCII })
        else { return nil }
        return value.lowercased()
    }

    /// (r, g, b) in 0...1.
    static func components(_ hex: String) -> (Double, Double, Double)? {
        guard let hex = normalizedHex(hex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    /// WCAG relative luminance < 0.5 → needs light content on top.
    static func isDark(_ hex: String) -> Bool {
        guard let (r, g, b) = components(hex) else { return false }
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) < 0.5
    }

    #if canImport(UIKit)
    static func color(_ hex: String) -> UIColor {
        guard let (r, g, b) = components(hex) else { return .systemBackground }
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }

    var backgroundColor: UIColor { Self.color(background) }

    var statusBarStyle: UIStatusBarStyle { lightStatusBar ? .lightContent : .darkContent }
    #endif
}

/// Payload of the page's `chrome` event.
struct ChromeEvent: Equatable {
    var lightStatusBar: Bool
    var header: String?
    var background: String?
}

/// Last chrome per server + App Key + theme, in the app's `UserDefaults` (colours only, nothing secret).
struct ChromeCache {
    var defaults: UserDefaults = .standard

    static func key(baseURL: URL, appKey: String, theme: String) -> String {
        "net.letsbot.chat.chrome.\(baseURL.host ?? "").\(appKey).\(theme)"
    }

    func load(baseURL: URL, appKey: String, theme: String) -> ChatChrome? {
        guard let data = defaults.data(forKey: Self.key(baseURL: baseURL, appKey: appKey, theme: theme)),
              let chrome = try? JSONDecoder().decode(ChatChrome.self, from: data),
              ChatChrome.normalizedHex(chrome.header) != nil, ChatChrome.normalizedHex(chrome.background) != nil
        else { return nil }
        return chrome
    }

    func save(_ chrome: ChatChrome, baseURL: URL, appKey: String, theme: String) {
        guard let data = try? JSONEncoder().encode(chrome) else { return }
        defaults.set(data, forKey: Self.key(baseURL: baseURL, appKey: appKey, theme: theme))
    }
}
