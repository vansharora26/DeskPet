import Foundation

// MARK: - Distraction guard: gentle nudges back to focus

/// What the user marked as distracting. Apps by bundle identifier, sites by domain.
public struct DistractionRules: Equatable, Sendable {
    public var apps: [String]
    public var sites: [String]

    public init(apps: [String] = [], sites: [String] = []) {
        self.apps = apps
        self.sites = sites
    }

    /// A sensible starting list; the user can edit it freely.
    public static let suggestedSites = ["youtube.com", "reddit.com", "x.com", "twitter.com", "instagram.com",
                                        "facebook.com", "tiktok.com", "netflix.com", "twitch.tv"]
}

public enum DistractionMatch: Equatable, Sendable {
    case app(bundleID: String)
    case site(domain: String)

    /// Key used for per-target cooldowns.
    public var key: String {
        switch self {
        case .app(let id): return "app:" + id
        case .site(let d): return "site:" + d
        }
    }
}

public enum DistractionGuard {
    /// Browsers whose current tab address can be read with Apple Events, and the
    /// AppleScript object that holds the tab ("current tab" in Safari, "active tab" in Chromium browsers).
    public static let browsers: [String: String] = [
        "com.apple.Safari": "current tab",
        "com.apple.SafariTechnologyPreview": "current tab",
        "com.google.Chrome": "active tab",
        "com.google.Chrome.beta": "active tab",
        "com.microsoft.edgemac": "active tab",
        "com.brave.Browser": "active tab",
        "company.thebrowser.Browser": "active tab",
        "com.vivaldi.Vivaldi": "active tab",
        "com.operasoftware.Opera": "active tab",
    ]

    /// "https://www.YouTube.com/watch?v=1" → "youtube.com". Accepts bare domains too.
    /// Returns nil for anything that isn't a plausible domain.
    public static func normalizedSite(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(where: { "/?#".contains($0) }) { s = String(s[..<slash]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        while s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix(".") { s.removeLast() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard s.contains("."), !s.hasPrefix("."), s.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return s
    }

    /// The listed domain that this address belongs to (exact or a subdomain), if any.
    public static func matchingSite(url: String, sites: [String]) -> String? {
        guard let host = normalizedSite(url) else { return nil }
        return sites.compactMap(normalizedSite).first { host == $0 || host.hasSuffix("." + $0) }
    }

    public static func match(bundleID: String?, url: String?, rules: DistractionRules) -> DistractionMatch? {
        if let bundleID, rules.apps.contains(bundleID) { return .app(bundleID: bundleID) }
        if let url, let domain = matchingSite(url: url, sites: rules.sites) { return .site(domain: domain) }
        return nil
    }
}

/// Decides *when* to nudge, so the pet is a gentle reminder rather than a nag:
/// a short grace period (quick look-ups are fine), a cooldown per distraction,
/// and a snooze when the user asks for a few more minutes.
public struct DistractionTracker: Equatable, Sendable {
    /// Seconds on a distraction before the first nudge.
    public static let grace: TimeInterval = 10
    /// Minimum gap between nudges about the same distraction.
    public static let cooldown: TimeInterval = 180

    public private(set) var current: DistractionMatch?
    public private(set) var since: Date?
    public private(set) var snoozedUntil: Date?
    private var lastNudge: [String: Date] = [:]
    /// Nudges this focus session (shown in the summary line).
    public private(set) var nudges = 0

    public init() {}

    public enum Event: Equatable, Sendable {
        case nudge(DistractionMatch)
        /// Left the distraction after being nudged.
        case cameBack
    }

    /// Feed the latest observation; returns what the pet should do, if anything.
    public mutating func observe(_ match: DistractionMatch?, now: Date) -> Event? {
        guard let match else {
            let wasNudged = current.map { lastNudge[$0.key].map { $0 >= since ?? .distantFuture } ?? false } ?? false
            current = nil
            since = nil
            return wasNudged ? .cameBack : nil
        }
        if match != current {
            current = match
            since = now
        }
        if let s = snoozedUntil, now < s { return nil }
        guard let since, now.timeIntervalSince(since) >= Self.grace else { return nil }
        if let last = lastNudge[match.key], now.timeIntervalSince(last) < Self.cooldown { return nil }
        lastNudge[match.key] = now
        nudges += 1
        return .nudge(match)
    }

    public mutating func snooze(minutes: Double, now: Date) {
        snoozedUntil = now.addingTimeInterval(minutes * 60)
    }

    /// New focus session: forget everything.
    public mutating func reset() { self = DistractionTracker() }
}
