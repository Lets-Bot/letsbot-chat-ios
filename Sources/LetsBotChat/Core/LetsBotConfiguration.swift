import Foundation

/// The colour scheme of the hosted chat screen.
public enum LetsBotTheme: String, Sendable, CaseIterable {
    /// Follow the light/dark appearance of the screen that shows the chat (default).
    case auto
    /// Always light.
    case light
    /// Always dark.
    case dark
}

/// Receives LetsBot events. All methods are called on the main thread and are optional.
public protocol LetsBotDelegate: AnyObject {
    /// The chat screen appeared.
    func letsBotDidOpen()
    /// The chat screen was dismissed.
    func letsBotDidClose()
    /// A new message from the team or the AI assistant arrived while the chat screen was open.
    func letsBotDidReceiveMessage(_ text: String)
    /// The number of unread team/assistant messages changed.
    func letsBotUnreadCountDidChange(_ count: Int)
    /// Something failed. See ``LetsBotError/code`` and the README troubleshooting table.
    func letsBotDidFail(_ error: LetsBotError)
}

public extension LetsBotDelegate {
    func letsBotDidOpen() {}
    func letsBotDidClose() {}
    func letsBotDidReceiveMessage(_ text: String) {}
    func letsBotUnreadCountDidChange(_ count: Int) {}
    func letsBotDidFail(_ error: LetsBotError) {}
}

/// Immutable snapshot of `LetsBot.configure(...)` values.
struct LetsBotConfiguration: Equatable, Sendable {
    static let defaultBaseURL = URL(string: "https://letsbot.net")!

    var appKey: String
    var baseURL: URL
    var locale: String?
    var theme: LetsBotTheme
    /// Brand colour as `#rrggbb`, or `nil` to use the colour configured in the LetsBot panel.
    var colorHex: String?

    /// `https://letsbot.net/api/sdk/v1/{appKey}`
    var apiRoot: URL {
        var root = baseURL
        for component in ["api", "sdk", "v1"] {
            root.appendPathComponent(component)
        }
        // appendPathComponent percent-encodes reserved characters in the key.
        root.appendPathComponent(appKey)
        return root
    }

    /// Locale sent to LetsBot: the configured one, or `"auto"`.
    var localeParameter: String {
        guard let locale, !locale.isEmpty else { return "auto" }
        return locale
    }
}
