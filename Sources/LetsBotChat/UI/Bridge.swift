import Foundation

/// Page → native events of the hosted chat screen (API.md §5).
enum BridgeEvent: Equatable {
    case ready
    case tokenInvalid
    case close
    case openURL(URL)
    case unread(Int)
    case message(String)
    case error(String)

    /// Parses a `postMessage` body: a JSON string `{"lb":"<event>", ...}` (or the already-decoded dictionary).
    /// Returns `nil` for anything malformed or unknown.
    static func parse(_ body: Any) -> BridgeEvent? {
        let object: [String: Any]
        if let string = body as? String {
            guard let data = string.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            object = decoded
        } else if let dictionary = body as? [String: Any] {
            object = dictionary
        } else {
            return nil
        }
        guard let name = object["lb"] as? String else { return nil }
        switch name {
        case "ready": return .ready
        case "token_invalid": return .tokenInvalid
        case "close": return .close
        case "open_url":
            guard let raw = object["url"] as? String, let url = URL(string: raw), NavigationPolicy.isWeb(url) else {
                return nil
            }
            return .openURL(url)
        case "unread":
            if let count = object["count"] as? Int { return .unread(max(0, count)) }
            if let count = (object["count"] as? String).flatMap(Int.init) { return .unread(max(0, count)) }
            return nil
        case "message":
            return .message(object["t"] as? String ?? "")
        case "error":
            guard let code = object["code"] as? String, !code.isEmpty else { return nil }
            return .error(code)
        default:
            return nil
        }
    }
}

/// What the WebView may load.
enum NavigationPolicy {
    enum Decision: Equatable {
        case allow
        case openExternally(URL)
        case cancel
    }

    /// Only the hosted `ui` URL (any query) and `about:blank`/`about:srcdoc` load inside the WebView; other http(s)
    /// URLs open in the system browser; everything else is cancelled.
    static func decide(_ url: URL?, uiURL: URL) -> Decision {
        guard let url else { return .cancel }
        if url.scheme?.lowercased() == "about" {
            let target = url.absoluteString.lowercased()
            return (target == "about:blank" || target == "about:srcdoc") ? .allow : .cancel
        }
        if isSameOrigin(url, uiURL), normalizedPath(url) == normalizedPath(uiURL) {
            return .allow
        }
        return isWeb(url) ? .openExternally(url) : .cancel
    }

    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host?.isEmpty == false
    }

    /// Same scheme, host (case-insensitive) and effective port.
    static func isSameOrigin(_ a: URL?, _ b: URL) -> Bool {
        guard let a, let schemeA = a.scheme?.lowercased(), let schemeB = b.scheme?.lowercased(),
              let hostA = a.host?.lowercased(), let hostB = b.host?.lowercased()
        else { return false }
        return schemeA == schemeB && hostA == hostB && effectivePort(a) == effectivePort(b)
    }

    private static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "http" ? 80 : 443
    }

    private static func normalizedPath(_ url: URL) -> String {
        var path = url.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// Native → page calls (`window.LetsBotHost.*`).
enum BridgeScript {
    /// `window.LetsBotHost && window.LetsBotHost.<function>(<json argument>);`
    static func call(_ function: String, _ argument: Any) -> String? {
        guard let json = jsonLiteral(argument) else { return nil }
        return "window.LetsBotHost && window.LetsBotHost.\(function)(\(json));"
    }

    /// A JSON value that is also a safe JavaScript literal.
    static func jsonLiteral(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]),
              var string = String(data: data, encoding: .utf8)
        else { return nil }
        // Unwrap the array we used to allow fragments on every iOS version.
        string.removeFirst()
        string.removeLast()
        return string
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            .replacingOccurrences(of: "</", with: "<\\/")
    }

    static func bootPayload(
        token: String,
        appId: String,
        context: [String: String],
        color: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "token": token,
            "appId": appId,
            "platform": DeviceInfo.platform,
            "sdk": DeviceInfo.sdkHeader,
            "context": context,
        ]
        if let color { payload["color"] = color }
        return payload
    }
}
