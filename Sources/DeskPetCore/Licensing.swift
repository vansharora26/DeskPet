import Foundation

// MARK: - What a license unlocks

/// Features that need a license once the free trial ends. Everything else —
/// the pet, water, the focus timer, notes, tasks, reminders — is always free.
public enum PremiumFeature: String, CaseIterable, Sendable {
    case focusWorlds, aiChat, voice

    public var title: String {
        switch self {
        case .focusWorlds: return "Focus Worlds"
        case .aiChat: return "AI chat"
        case .voice: return "Voice conversation"
        }
    }
}

/// Which Dodo Payments environment license keys belong to. Test-mode keys
/// only work against the test host, and live keys only against live.
public enum DodoEnvironment: String, Codable, Sendable {
    case testMode = "test_mode"
    case liveMode = "live_mode"

    public var baseURL: URL {
        switch self {
        case .testMode: return URL(string: "https://test.dodopayments.com")!
        case .liveMode: return URL(string: "https://live.dodopayments.com")!
        }
    }
}

/// An activated license on this Mac. Holds no personal data — just the key,
/// Dodo's ID for this Mac's activation, and when it was last confirmed.
public struct LicenseRecord: Codable, Equatable, Sendable {
    public var key: String
    public var instanceID: String
    public var environment: DodoEnvironment
    public var activatedAt: Date
    /// Last time Dodo confirmed the key (offline grace is measured from here).
    public var lastValidatedAt: Date

    public init(key: String, instanceID: String, environment: DodoEnvironment, activatedAt: Date, lastValidatedAt: Date) {
        self.key = key
        self.instanceID = instanceID
        self.environment = environment
        self.activatedAt = activatedAt
        self.lastValidatedAt = lastValidatedAt
    }

    /// Shows only the end of the key, e.g. "•••• 8f43".
    public var maskedKey: String { "•••• " + String(key.suffix(4)) }
}

// MARK: - Policy

public enum LicenseAccess: Equatable, Sendable {
    /// Licensed and confirmed recently enough.
    case licensed
    /// Licensed, but not confirmed for longer than the offline grace period.
    case needsCheck
    case trial(daysLeft: Int)
    case trialEnded

    public var unlocksPremium: Bool {
        switch self {
        case .licensed, .trial: return true
        case .needsCheck, .trialEnded: return false
        }
    }
}

/// Pure rules for the trial and license checks.
public enum LicensePolicy {
    public static let trialDays = 14
    /// Re-check the key with Dodo at most this often.
    public static let revalidateAfter: TimeInterval = 7 * 86_400
    /// Keep working offline for this long after the last successful check.
    public static let offlineGrace: TimeInterval = 30 * 86_400

    public static func access(trialStart: Date, license: LicenseRecord?, now: Date, calendar: Calendar) -> LicenseAccess {
        if let license {
            // A clock set backwards doesn't extend the grace period beyond a fresh check.
            let age = now.timeIntervalSince(license.lastValidatedAt)
            return age < offlineGrace ? .licensed : .needsCheck
        }
        let left = trialDaysLeft(trialStart: trialStart, now: now, calendar: calendar)
        return left > 0 ? .trial(daysLeft: left) : .trialEnded
    }

    /// Whole days left; the day the trial starts counts as day 1 of 14.
    public static func trialDaysLeft(trialStart: Date, now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: trialStart)
        let today = calendar.startOfDay(for: now)
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return min(trialDays, max(0, trialDays - max(0, elapsed)))
    }

    public static func needsRevalidation(_ license: LicenseRecord, now: Date) -> Bool {
        let age = now.timeIntervalSince(license.lastValidatedAt)
        return age >= revalidateAfter || age < 0
    }

    /// Accepts keys pasted with spaces, newlines or surrounding quotes.
    public static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’")))
    }
}

// MARK: - Dodo Payments client

public enum LicenseError: Error, Equatable, LocalizedError {
    case notFound
    case inactive
    case activationLimitReached
    case offline
    case server(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notFound: return "That license key wasn’t found. Check it matches the one in your purchase email."
        case .inactive: return "This license key isn’t active (it may have been refunded or revoked)."
        case .activationLimitReached: return "This key is already active on the maximum number of Macs. Deactivate it on another Mac first."
        case .offline: return "Can’t reach the license server. Check your internet connection and try again."
        case .server(let code): return "The license server had a problem (\(code)). Try again in a moment."
        case .invalidResponse: return "Got an unexpected answer from the license server."
        }
    }

    /// A network problem rather than an answer about the key.
    public var isConnectivity: Bool {
        switch self {
        case .offline, .server, .invalidResponse: return true
        default: return false
        }
    }
}

/// Dodo Payments' public license endpoints. They need no API key, so no
/// secret ships inside DeskPet. Only the license key, Dodo's activation ID,
/// and (on activation) a device name are sent.
public struct DodoLicenseClient: Sendable {
    public var environment: DodoEnvironment
    public var session: URLSession

    public init(environment: DodoEnvironment, session: URLSession = .shared) {
        self.environment = environment
        self.session = session
    }

    public struct Activation: Equatable, Sendable {
        public var instanceID: String
        public var productName: String?
    }

    /// POST /licenses/activate → this Mac's activation (instance) ID.
    public func activate(key: String, deviceName: String) async throws -> Activation {
        let (code, json) = try await post("licenses/activate", ["license_key": .string(key), "name": .string(deviceName)])
        switch code {
        case 200..<300:
            guard let id = json?["id"]?.string, !id.isEmpty else { throw LicenseError.invalidResponse }
            return Activation(instanceID: id, productName: json?["product"]?["name"]?.string)
        case 403: throw LicenseError.inactive
        case 404: throw LicenseError.notFound
        case 422: throw LicenseError.activationLimitReached
        default: throw LicenseError.server(code)
        }
    }

    /// POST /licenses/validate → whether the key is active *and* this Mac's activation still exists.
    public func validate(key: String, instanceID: String) async throws -> Bool {
        let (code, json) = try await post("licenses/validate", ["license_key": .string(key),
                                                                "license_key_instance_id": .string(instanceID)])
        switch code {
        case 200..<300:
            guard case .bool(let valid)? = json?["valid"] else { throw LicenseError.invalidResponse }
            return valid
        case 404, 422: return false
        default: throw LicenseError.server(code)
        }
    }

    /// POST /licenses/deactivate → frees this Mac's activation slot.
    public func deactivate(key: String, instanceID: String) async throws {
        let (code, _) = try await post("licenses/deactivate", ["license_key": .string(key),
                                                               "license_key_instance_id": .string(instanceID)])
        switch code {
        case 200..<300: return
        case 403, 404: return // already gone — nothing left to free
        default: throw LicenseError.server(code)
        }
    }

    private func post(_ path: String, _ body: [String: JSONValue]) async throws -> (Int, JSONValue?) {
        var request = URLRequest(url: environment.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is URLError {
            throw LicenseError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw LicenseError.invalidResponse }
        return (http.statusCode, try? JSONDecoder().decode(JSONValue.self, from: data))
    }
}
