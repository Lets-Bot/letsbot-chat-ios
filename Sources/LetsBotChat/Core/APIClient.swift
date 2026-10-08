import Foundation

/// HTTP method + path of one LetsBot SDK API route (API.md §4).
struct Endpoint: Equatable, Sendable {
    var method: String
    var path: String
    /// Whether the route requires `X-LB-Visitor`.
    var needsVisitor: Bool

    static let config = Endpoint(method: "GET", path: "config", needsVisitor: false)
    static let session = Endpoint(method: "POST", path: "session", needsVisitor: false)
    static let identify = Endpoint(method: "POST", path: "identify", needsVisitor: true)
    static let logout = Endpoint(method: "POST", path: "logout", needsVisitor: true)
    static let putDevice = Endpoint(method: "PUT", path: "device", needsVisitor: true)
    static let deleteDevice = Endpoint(method: "DELETE", path: "device", needsVisitor: true)
    static let unread = Endpoint(method: "GET", path: "unread", needsVisitor: true)
    static let ui = Endpoint(method: "GET", path: "ui", needsVisitor: false)
}

// MARK: - Bodies

struct SessionBody: Encodable, Equatable {
    struct Device: Encodable, Equatable {
        var platform: String
        var app_id: String
        var app_version: String?
        var sdk: String
        var os_version: String
    }

    var locale: String?
    var device: Device
    var ctx: [String: String]?
}

struct IdentifyBody: Encodable, Equatable {
    var identity_token: String
    var name: String?
    var email: String?
    var phone: String?
}

struct DeviceBody: Encodable, Equatable {
    var provider: String
    var token: String
    var platform: String
    var app_id: String
    var app_version: String?
    var sdk: String
    var locale: String?
    var sandbox: Bool
}

struct DeleteDeviceBody: Encodable, Equatable {
    var token: String
}

// MARK: - Responses

struct SessionResponse: Decodable { var token: String }
struct IdentifyResponse: Decodable { var verified: Bool }
struct OkResponse: Decodable { var ok: Bool? }
struct UnreadResponse: Decodable {
    struct Last: Decodable { var t: String?; var at: String? }
    var count: Int
    var last: Last?
}

struct ErrorResponse: Decodable { var error: String }

/// Thin, typed client for `https://<base>/api/sdk/v1/{appKey}/…`.
///
/// Never logs request bodies, tokens or response bodies.
final class APIClient: @unchecked Sendable {
    let configuration: LetsBotConfiguration
    let device: DeviceInfo
    private let session: URLSession
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    init(configuration: LetsBotConfiguration, device: DeviceInfo, session: URLSession) {
        self.configuration = configuration
        self.device = device
        self.session = session
    }

    func url(for endpoint: Endpoint, query: [URLQueryItem] = []) -> URL {
        let url = configuration.apiRoot.appendingPathComponent(endpoint.path)
        guard !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = query
        return components.url ?? url
    }

    func makeRequest<Body: Encodable>(_ endpoint: Endpoint, body: Body?, visitor: String?) throws -> URLRequest {
        var request = URLRequest(url: url(for: endpoint))
        request.httpMethod = endpoint.method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(device.appId, forHTTPHeaderField: "X-LB-App-Id")
        request.setValue(DeviceInfo.platform, forHTTPHeaderField: "X-LB-Platform")
        request.setValue(DeviceInfo.sdkHeader, forHTTPHeaderField: "X-LB-SDK")
        if let visitor {
            request.setValue(visitor, forHTTPHeaderField: "X-LB-Visitor")
        }
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends a request and decodes a 2xx JSON body as `Response`. Non-2xx → ``LetsBotError``.
    func send<Body: Encodable, Response: Decodable>(
        _ endpoint: Endpoint,
        body: Body?,
        visitor: String?,
        as _: Response.Type
    ) async throws -> Response {
        if endpoint.needsVisitor && visitor == nil { throw LetsBotError.invalidVisitor }
        let request: URLRequest
        do {
            request = try makeRequest(endpoint, body: body, visitor: visitor)
        } catch {
            throw LetsBotError.invalid
        }
        let (data, response) = try await perform(request)
        try Self.validate(data: data, response: response)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw LetsBotError.invalidResponse(status: response.statusCode)
        }
    }

    func send<Response: Decodable>(_ endpoint: Endpoint, visitor: String?, as type: Response.Type) async throws -> Response {
        try await send(endpoint, body: Optional<EmptyBody>.none, visitor: visitor, as: type)
    }

    /// Maps non-2xx responses to typed errors (API.md §3).
    static func validate(data: Data, response: HTTPURLResponse) throws {
        let status = response.statusCode
        guard !(200..<300).contains(status) else { return }
        let retryAfter = (response.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
        if let code = try? JSONDecoder().decode(ErrorResponse.self, from: data).error, !code.isEmpty {
            throw LetsBotError(code: code, status: status, retryAfter: retryAfter)
        }
        switch status {
        case 404: throw LetsBotError.notFound
        case 429: throw LetsBotError.slowDown(retryAfter: retryAfter)
        default: throw LetsBotError.invalidResponse(status: status)
        }
    }

    /// `URLSession.data(for:)` is iOS 15+, so bridge the callback API for iOS 13/14.
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        let code = (error as? URLError)?.code.rawValue ?? URLError.Code.unknown.rawValue
                        continuation.resume(throwing: LetsBotError.network(urlErrorCode: code))
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        continuation.resume(throwing: LetsBotError.invalidResponse(status: 0))
                        return
                    }
                    continuation.resume(returning: (data ?? Data(), http))
                }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }
}

struct EmptyBody: Encodable {}

private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionDataTask?
    var task: URLSessionDataTask? {
        get { lock.lock(); defer { lock.unlock() }; return _task }
        set { lock.lock(); _task = newValue; lock.unlock() }
    }
}
