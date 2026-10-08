import Foundation

/// Errors reported by the LetsBot SDK.
///
/// Server errors map one-to-one to the `{"error": "<code>"}` codes of the LetsBot In-App Chat API.
/// Use ``code`` to get the stable wire code (for example `"identity_expired"`), which is what the
/// troubleshooting table in the README refers to.
public enum LetsBotError: Error, Equatable, Sendable {
    // MARK: SDK-side

    /// `LetsBot.configure(appKey:)` has not been called, or was called with an empty App Key.
    case notConfigured
    /// The request did not reach LetsBot (offline, DNS, TLS, timeout…). `urlErrorCode` is the `URLError.Code` raw value.
    case network(urlErrorCode: Int)
    /// LetsBot answered with something the SDK could not understand.
    case invalidResponse(status: Int)

    // MARK: API codes (API.md §3)

    /// `404 not_found` — unknown App Key, app disabled or deleted, workspace hibernated, or In-App Chat locked for the workspace.
    case notFound
    /// `403 app_not_registered` — this bundle ID is not in the app's registered list in the LetsBot panel.
    case appNotRegistered
    /// `401 invalid_visitor` — the visitor token is missing, invalid or idle for too long. The SDK recovers automatically.
    case invalidVisitor
    /// `401 identity_invalid` — the identity token has a bad signature, is malformed, or no Identity Secret is configured.
    case identityInvalid
    /// `401 identity_expired` — the identity token `exp` has passed. Fetch a fresh token from your backend and call `identify` again.
    case identityExpired
    /// `403 blocked` — the visitor or their IP address was blocked by the business.
    case blocked
    /// `422 invalid` — the request failed validation.
    case invalid
    /// `422 too_long` — a value was longer than allowed.
    case tooLong
    /// `422 invalid_contact` — the e-mail or phone number is not valid.
    case invalidContact
    /// `422 consent_required` — the user must accept the consent text first.
    case consentRequired
    /// `422 file_too_big` — the attachment exceeds the size limit.
    case fileTooBig
    /// `422 file_type` — the attachment type is not allowed.
    case fileType
    /// `429 slow_down` — rate limited. `retryAfter` is the server's `Retry-After` in seconds, when sent.
    case slowDown(retryAfter: TimeInterval?)
    /// `429 busy` — the workspace's chat budget is exhausted for now. `retryAfter` as above.
    case busy(retryAfter: TimeInterval?)

    /// Any other error code reported by the API or by the hosted chat screen.
    case other(code: String, status: Int?)

    /// The stable wire code of this error, e.g. `"app_not_registered"`.
    public var code: String {
        switch self {
        case .notConfigured: return "not_configured"
        case .network: return "network_error"
        case .invalidResponse: return "invalid_response"
        case .notFound: return "not_found"
        case .appNotRegistered: return "app_not_registered"
        case .invalidVisitor: return "invalid_visitor"
        case .identityInvalid: return "identity_invalid"
        case .identityExpired: return "identity_expired"
        case .blocked: return "blocked"
        case .invalid: return "invalid"
        case .tooLong: return "too_long"
        case .invalidContact: return "invalid_contact"
        case .consentRequired: return "consent_required"
        case .fileTooBig: return "file_too_big"
        case .fileType: return "file_type"
        case .slowDown: return "slow_down"
        case .busy: return "busy"
        case let .other(code, _): return code
        }
    }

    /// Builds the typed error for an API / bridge error code.
    ///
    /// - Parameters:
    ///   - code: The `error` value of the response body (or of a bridge `error` event).
    ///   - status: The HTTP status, when the error came from an HTTP response.
    ///   - retryAfter: Parsed `Retry-After` header, if any.
    public init(code: String, status: Int? = nil, retryAfter: TimeInterval? = nil) {
        switch code {
        case "not_found": self = .notFound
        case "app_not_registered": self = .appNotRegistered
        case "invalid_visitor": self = .invalidVisitor
        case "identity_invalid": self = .identityInvalid
        case "identity_expired": self = .identityExpired
        case "blocked": self = .blocked
        case "invalid": self = .invalid
        case "too_long": self = .tooLong
        case "invalid_contact": self = .invalidContact
        case "consent_required": self = .consentRequired
        case "file_too_big": self = .fileTooBig
        case "file_type": self = .fileType
        case "slow_down": self = .slowDown(retryAfter: retryAfter)
        case "busy": self = .busy(retryAfter: retryAfter)
        case "not_configured": self = .notConfigured
        default: self = .other(code: code, status: status)
        }
    }
}

extension LetsBotError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LetsBot is not configured. Call LetsBot.configure(appKey:) at app start."
        case let .network(code):
            return "Could not reach LetsBot (URLError \(code)). Check the connection and try again."
        case let .invalidResponse(status):
            return "Unexpected response from LetsBot (HTTP \(status))."
        case .notFound:
            return "App Key not found, the app is disabled, or In-App Chat is not available for this workspace."
        case .appNotRegistered:
            return "This bundle ID is not registered. Add it in LetsBot panel → Channels → In-App Chat → Platforms."
        case .invalidVisitor:
            return "The chat session expired. A new one will be created."
        case .identityInvalid:
            return "The identity token is invalid. Check that your backend signs it (HS256) with the app's Identity Secret."
        case .identityExpired:
            return "The identity token expired. Fetch a new one from your backend and call identify again."
        case .blocked:
            return "This user was blocked by the business."
        case .invalid, .tooLong, .invalidContact, .consentRequired, .fileTooBig, .fileType:
            return "LetsBot rejected the request (\(code))."
        case .slowDown, .busy:
            return "LetsBot is busy right now (\(code)). Try again shortly."
        case let .other(code, status):
            if let status { return "LetsBot error \(code) (HTTP \(status))." }
            return "LetsBot error \(code)."
        }
    }
}

extension LetsBotError: CustomStringConvertible {
    public var description: String { "LetsBotError.\(code)" }
}
