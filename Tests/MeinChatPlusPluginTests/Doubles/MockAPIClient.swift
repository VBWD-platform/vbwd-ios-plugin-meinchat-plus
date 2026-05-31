import Foundation
import VBWDCore

/// In-memory `APIClient` double for testing the meinchat-plus HTTP wrappers.
/// Stub the HTTP-verb maps with `(path, response)` pairs; the test asserts
/// on `recordedRequests` to verify the wire shape.
final class MockAPIClient: APIClient, @unchecked Sendable {

    enum RecordedRequest: Equatable {
        case get(path: String)
        case post(path: String, body: Data?)
        case put(path: String, body: Data?)
        case patch(path: String, body: Data?)
        case delete(path: String)
    }

    enum MockError: Error, Equatable { case noStub(String) }

    /// JSON bytes returned for the next call matching the given (verb, path).
    var responses: [String: Data] = [:]
    /// Path-keyed errors that override `responses` when set.
    var errors: [String: Error] = [:]
    /// Append-only log; tests inspect this to verify path/body/order.
    private(set) var recordedRequests: [RecordedRequest] = []

    static func key(_ verb: String, _ path: String) -> String { "\(verb) \(path)" }

    func stubGet(_ path: String, json: String) {
        responses[Self.key("GET", path)] = Data(json.utf8)
    }
    func stubPost(_ path: String, json: String) {
        responses[Self.key("POST", path)] = Data(json.utf8)
    }
    func stubDelete(_ path: String, json: String = "{}") {
        responses[Self.key("DELETE", path)] = Data(json.utf8)
    }
    func stubError(_ verb: String, _ path: String, error: Error) {
        errors[Self.key(verb, path)] = error
    }

    // MARK: APIClient

    func get<R: Decodable>(_ path: String) async throws -> R {
        recordedRequests.append(.get(path: path))
        if let err = errors[Self.key("GET", path)] { throw err }
        guard let data = responses[Self.key("GET", path)] else {
            throw MockError.noStub("GET \(path)")
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    func post<R: Decodable>(_ path: String, body: (any Encodable)?) async throws -> R {
        let bodyData = body.flatMap { try? JSONEncoder().encode(AnyEncodableShim($0)) }
        recordedRequests.append(.post(path: path, body: bodyData))
        if let err = errors[Self.key("POST", path)] { throw err }
        let data = responses[Self.key("POST", path)] ?? Data("{}".utf8)
        return try JSONDecoder().decode(R.self, from: data)
    }

    func put<R: Decodable>(_ path: String, body: (any Encodable)?) async throws -> R {
        recordedRequests.append(.put(path: path, body: nil))
        if let err = errors[Self.key("PUT", path)] { throw err }
        let data = responses[Self.key("PUT", path)] ?? Data("{}".utf8)
        return try JSONDecoder().decode(R.self, from: data)
    }

    func patch<R: Decodable>(_ path: String, body: (any Encodable)?) async throws -> R {
        recordedRequests.append(.patch(path: path, body: nil))
        if let err = errors[Self.key("PATCH", path)] { throw err }
        let data = responses[Self.key("PATCH", path)] ?? Data("{}".utf8)
        return try JSONDecoder().decode(R.self, from: data)
    }

    func delete<R: Decodable>(_ path: String) async throws -> R {
        recordedRequests.append(.delete(path: path))
        if let err = errors[Self.key("DELETE", path)] { throw err }
        let data = responses[Self.key("DELETE", path)] ?? Data("{}".utf8)
        return try JSONDecoder().decode(R.self, from: data)
    }

    func setToken(_ token: String?) {}
    func on(_ event: APIEvent, _ handler: @escaping @Sendable () -> Void) {}
}

/// Local `AnyEncodable` shim — the SDK's internal one isn't public, but we
/// need to JSON-encode the body for assertions.
private struct AnyEncodableShim: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: any Encodable) { _encode = { try wrapped.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
