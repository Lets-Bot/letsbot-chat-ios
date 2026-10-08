import Foundation
@testable import LetsBotChat

/// A recorded request, with the body read from `httpBodyStream` (URLProtocol never sees `httpBody`).
struct RecordedRequest {
    let request: URLRequest
    let body: Data?

    var method: String { request.httpMethod ?? "GET" }
    var path: String { request.url?.path ?? "" }
    /// Last path component, i.e. the API route (`session`, `identify`, …).
    var route: String { request.url?.lastPathComponent ?? "" }
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    var json: [String: Any]? {
        body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

/// Local mock of the LetsBot SDK API (API.md §4), served through `URLProtocol`.
final class MockServer: @unchecked Sendable {
    struct Response {
        var status: Int = 200
        var json: Any = [String: Any]()
        var headers: [String: String] = [:]
        var networkError: URLError.Code?
    }

    typealias Handler = (RecordedRequest) -> Response

    static let shared = MockServer()

    private let lock = NSLock()
    private var handlers: [String: [Handler]] = [:] // "METHOD route" → queue (last one repeats)
    private var _requests: [RecordedRequest] = []

    var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func requests(_ route: String) -> [RecordedRequest] { requests.filter { $0.route == route } }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        handlers = [:]
        _requests = []
    }

    /// Adds a response for `METHOD route`. Several responses for the same route are served in order; the last one
    /// keeps being served.
    func on(_ method: String, _ route: String, _ handler: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers["\(method) \(route)", default: []].append(handler)
    }

    func on(_ method: String, _ route: String, status: Int = 200, json: Any, headers: [String: String] = [:]) {
        on(method, route) { _ in Response(status: status, json: json, headers: headers) }
    }

    fileprivate func respond(to request: URLRequest) -> Response {
        let recorded = RecordedRequest(request: request, body: Self.readBody(request))
        lock.lock()
        _requests.append(recorded)
        let key = "\(recorded.method) \(recorded.route)"
        var queue = handlers[key] ?? []
        let handler = queue.first
        if queue.count > 1 { queue.removeFirst(); handlers[key] = queue }
        lock.unlock()
        return handler?(recorded) ?? Response(status: 404, json: ["error": "not_found"])
    }

    private static func readBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    /// A session whose requests are all answered by this mock.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

final class MockURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = MockServer.shared.respond(to: request)
        if let code = response.networkError {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        var headers = response.headers
        headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
        let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: headers)!
        let data: Data
        if let raw = response.json as? String {
            data = Data(raw.utf8)
        } else {
            data = (try? JSONSerialization.data(withJSONObject: response.json)) ?? Data()
        }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

enum Fixtures {
    static let appKey = "lbk_test_123"
    static let token = "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0.abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"
    static let token2 = "Z1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0.zbcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ"
    static let device = DeviceInfo(appId: "com.acme.app", appVersion: "2.3.0", osVersion: "17.5")

    static func configuration(
        baseURL: URL = URL(string: "https://letsbot.test")!,
        locale: String? = "ar"
    ) -> LetsBotConfiguration {
        LetsBotConfiguration(appKey: appKey, baseURL: baseURL, locale: locale, theme: .auto, colorHex: nil)
    }

    static func api(_ configuration: LetsBotConfiguration = configuration()) -> APIClient {
        APIClient(configuration: configuration, device: device, session: MockServer.makeSession())
    }
}

/// Thread-safe collector for callback values.
final class Collector<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []
    var values: [T] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ value: T) { lock.lock(); _values.append(value); lock.unlock() }
}
