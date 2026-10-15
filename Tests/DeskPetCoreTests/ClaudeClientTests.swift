import Foundation
import Testing
@testable import DeskPetCore

/// Stubbed transport: no network, no real API key.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [(Int, String)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 4096); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
            Self.bodies.append(data)
        }
        let (code, body) = Self.responses.isEmpty ? (500, "{}") : Self.responses.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct ClaudeClientTests {
    func client(model: String = "claude-opus-5", key: String? = "test-key", proxy: URL? = nil,
                responses: [(Int, String)]) -> ClaudeClient {
        StubProtocol.responses = responses
        StubProtocol.requests = []
        StubProtocol.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return ClaudeClient(config: .init(model: model, apiKey: key, proxyURL: proxy),
                            session: URLSession(configuration: config), maxRetries: 2, retryBaseDelay: 0.001)
    }

    let ok = #"{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"Hi!"}],"stop_reason":"end_turn"}"#

    @Test func missingCredentialsFailsWithoutNetwork() async {
        let c = client(key: nil, responses: [])
        await #expect(throws: AIError.notConfigured) { _ = try await c.createMessage(["model": "x"]) }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func successParsesContentAndSendsCorrectHeaders() async throws {
        let c = client(responses: [(200, ok)])
        let r = try await c.createMessage(["model": "claude-opus-5", "max_tokens": 10, "messages": []])
        #expect(r["content"]?.array?.first?["text"]?.string == "Hi!")
        let req = try #require(StubProtocol.requests.first)
        #expect(req.url == ClaudeClient.directEndpoint)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        // Opus 5 opts into server-side refusal fallback.
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(StubProtocol.bodies.first))
        #expect(body["fallbacks"]?.string == "default")
        #expect(body["max_tokens"]?.int == 10)
    }

    @Test func otherModelsDoNotSendFallbacks() async throws {
        let c = client(model: "claude-haiku-4-5", responses: [(200, ok)])
        _ = try await c.createMessage(["model": "claude-haiku-4-5"])
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(StubProtocol.bodies.first))
        #expect(body["fallbacks"] == nil)
    }

    @Test func proxyModeNeverSendsAKey() async throws {
        let proxy = URL(string: "https://proxy.example.com/v1/messages")!
        let c = client(key: "secret", proxy: proxy, responses: [(200, ok)])
        _ = try await c.createMessage(["model": "claude-opus-5"])
        #expect(StubProtocol.requests.first?.url == proxy)
        #expect(StubProtocol.requests.first?.value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test func unauthorizedIsNotRetried() async {
        let c = client(responses: [(401, #"{"type":"error","error":{"type":"authentication_error","message":"bad key"}}"#)])
        await #expect(throws: AIError.unauthorized) { _ = try await c.createMessage(["model": "x"]) }
        #expect(StubProtocol.requests.count == 1)
    }

    @Test func overloadedIsRetriedThenSucceeds() async throws {
        let c = client(responses: [(529, "{}"), (429, "{}"), (200, ok)])
        let r = try await c.createMessage(["model": "x"])
        #expect(r["stop_reason"]?.string == "end_turn")
        #expect(StubProtocol.requests.count == 3)
    }

    @Test func persistentServerErrorsSurfaceAfterRetries() async {
        let c = client(responses: [(500, "{}"), (500, "{}"), (500, "{}")])
        await #expect(throws: AIError.server(500)) { _ = try await c.createMessage(["model": "x"]) }
        #expect(StubProtocol.requests.count == 3)
    }

    @Test func badRequestCarriesTheMessage() async {
        let c = client(responses: [(400, #"{"type":"error","error":{"type":"invalid_request_error","message":"messages: roles must alternate"}}"#)])
        await #expect(throws: AIError.badRequest("messages: roles must alternate")) { _ = try await c.createMessage(["model": "x"]) }
    }

    @Test func malformedSuccessIsInvalidResponse() async {
        let c = client(responses: [(200, "not json")])
        await #expect(throws: AIError.invalidResponse) { _ = try await c.createMessage(["model": "x"]) }
    }

    @Test func jsonValueRoundTripsThinkingBlocksUnchanged() throws {
        let raw = #"{"content":[{"type":"thinking","thinking":"","signature":"abc+/="},{"type":"tool_use","id":"toolu_1","name":"log_water","input":{"ml":300}}]}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        let again = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(v))
        #expect(v == again)
        #expect(again["content"]?.array?[1]["input"]?["ml"]?.int == 300)
        #expect(again["content"]?.array?[0]["signature"]?.string == "abc+/=")
    }

    @Test func retryableClassification() {
        #expect(AIError.rateLimited.isRetryable && AIError.overloaded.isRetryable && AIError.offline.isRetryable)
        #expect(!AIError.unauthorized.isRetryable && !AIError.badRequest("x").isRetryable)
        #expect(AIError.unauthorized.needsSettings && !AIError.timeout.needsSettings)
    }
}
