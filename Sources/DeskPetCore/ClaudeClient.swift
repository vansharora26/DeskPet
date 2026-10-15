import Foundation

/// Friendly, typed failures for the chat UI.
public enum AIError: Error, Equatable, LocalizedError {
    case notConfigured
    case unauthorized
    case forbidden(String)
    case badRequest(String)
    case modelNotFound(String)
    case rateLimited
    case overloaded
    case server(Int)
    case offline
    case timeout
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI isn’t set up yet. Add an API key in Settings › AI."
        case .unauthorized: return "The API key was rejected. Check it in Settings › AI."
        case .forbidden(let m): return "This key isn’t allowed to do that. \(m)"
        case .badRequest(let m): return "The request was rejected: \(m)"
        case .modelNotFound(let m): return "Model not available for this key: \(m). Pick another in Settings › AI."
        case .rateLimited: return "Too many requests right now. Try again in a moment."
        case .overloaded: return "The AI service is busy. Try again in a moment."
        case .server(let code): return "The AI service had a problem (\(code)). Try again."
        case .offline: return "Can’t reach the AI service. Check your internet connection."
        case .timeout: return "The AI took too long to answer. Try again."
        case .invalidResponse: return "Got an unexpected response from the AI service."
        }
    }

    /// Errors the user fixes in Settings › AI.
    public var needsSettings: Bool {
        switch self {
        case .notConfigured, .unauthorized, .modelNotFound, .forbidden: return true
        default: return false
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .server, .offline, .timeout: return true
        default: return false
        }
    }
}

/// Minimal client for the Claude Messages API (raw HTTPS — there is no
/// official Swift SDK). Two credential modes:
/// - **Direct (development):** the user's own key from the Keychain.
/// - **Proxy (production):** requests go to the configured backend URL, which
///   adds the key server-side; the app never holds a secret.
public struct ClaudeClient {
    public struct Config {
        public var model: String
        public var apiKey: String?
        public var proxyURL: URL?

        public init(model: String, apiKey: String?, proxyURL: URL?) {
            self.model = model
            self.apiKey = apiKey
            self.proxyURL = proxyURL
        }
    }

    public static let directEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public var config: Config
    public var session: URLSession
    public var maxRetries: Int
    /// Base delay for retry backoff (seconds); tests set it to ~0.
    public var retryBaseDelay: Double

    public init(config: Config, session: URLSession = .shared, maxRetries: Int = 2, retryBaseDelay: Double = 1) {
        self.config = config
        self.session = session
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
    }

    public var isConfigured: Bool { config.proxyURL != nil || !(config.apiKey ?? "").isEmpty }

    /// POST /v1/messages with retries for transient failures.
    public func createMessage(_ body: [String: JSONValue]) async throws -> JSONValue {
        guard isConfigured else { throw AIError.notConfigured }
        var attempt = 0
        while true {
            do {
                return try await send(body)
            } catch let error as AIError where error.isRetryable && attempt < maxRetries {
                attempt += 1
                // Exponential backoff with jitter: ~1s, ~2s.
                let delay = retryBaseDelay * (pow(2, Double(attempt - 1)) + Double.random(in: 0...0.4))
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func send(_ body: [String: JSONValue]) async throws -> JSONValue {
        var request = URLRequest(url: config.proxyURL ?? Self.directEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if config.proxyURL == nil, let key = config.apiKey {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        var payload = body
        // Claude Opus 5: server-side refusal fallback ("default" routing by category).
        if config.model == "claude-opus-5" {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            payload["fallbacks"] = "default"
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(payload))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let e as URLError {
            switch e.code {
            case .timedOut: throw AIError.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw AIError.offline
            case .cancelled: throw CancellationError()
            default: throw AIError.offline
            }
        }
        guard let http = response as? HTTPURLResponse else { throw AIError.invalidResponse }
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        let message = json?["error"]?["message"]?.string ?? ""

        switch http.statusCode {
        case 200..<300:
            guard let json, json["content"] != nil else { throw AIError.invalidResponse }
            return json
        case 401: throw AIError.unauthorized
        case 403: throw AIError.forbidden(message)
        case 404: throw AIError.modelNotFound(config.model)
        case 400, 413: throw AIError.badRequest(message.isEmpty ? "HTTP \(http.statusCode)" : message)
        case 429: throw AIError.rateLimited
        case 529: throw AIError.overloaded
        default: throw AIError.server(http.statusCode)
        }
    }
}
