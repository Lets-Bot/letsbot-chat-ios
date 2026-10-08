import Foundation
import os.log
import UIKit

/// Minimal logging. Logs only event names and error codes — never tokens, identity tokens, user data or message text.
enum Log {
    private static let log = OSLog(subsystem: "net.letsbot.chat", category: "LetsBotChat")

    static func error(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: log, type: .error, message())
    }

    static func debug(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: log, type: .debug, message())
    }
}

enum ColorHex {
    /// `UIColor` → `#rrggbb` (light appearance, sRGB, alpha ignored).
    static func string(from color: UIColor) -> String? {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b))
    }
}
