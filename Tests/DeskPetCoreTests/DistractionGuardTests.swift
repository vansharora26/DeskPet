import Foundation
import Testing
@testable import DeskPetCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Suite struct DistractionGuardTests {
    @Test func normalisesSites() {
        #expect(DistractionGuard.normalizedSite("https://www.YouTube.com/watch?v=1") == "youtube.com")
        #expect(DistractionGuard.normalizedSite("  reddit.com/r/swift ") == "reddit.com")
        #expect(DistractionGuard.normalizedSite("http://user@m.facebook.com:443/x") == "m.facebook.com")
        #expect(DistractionGuard.normalizedSite("not a site") == nil)
        #expect(DistractionGuard.normalizedSite("localhost") == nil)
    }

    @Test func matchesDomainsAndSubdomainsOnly() {
        let sites = ["youtube.com", "x.com"]
        #expect(DistractionGuard.matchingSite(url: "https://m.youtube.com/feed", sites: sites) == "youtube.com")
        #expect(DistractionGuard.matchingSite(url: "https://x.com/home", sites: sites) == "x.com")
        // Look-alikes don't count.
        #expect(DistractionGuard.matchingSite(url: "https://notyoutube.com", sites: sites) == nil)
        #expect(DistractionGuard.matchingSite(url: "https://box.com", sites: sites) == nil)
        #expect(DistractionGuard.matchingSite(url: "about:blank", sites: sites) == nil)
    }

    @Test func appsTakePriorityOverSites() {
        let rules = DistractionRules(apps: ["com.valvesoftware.steam"], sites: ["reddit.com"])
        #expect(DistractionGuard.match(bundleID: "com.valvesoftware.steam", url: nil, rules: rules) == .app(bundleID: "com.valvesoftware.steam"))
        #expect(DistractionGuard.match(bundleID: "com.apple.Safari", url: "https://reddit.com", rules: rules) == .site(domain: "reddit.com"))
        #expect(DistractionGuard.match(bundleID: "com.apple.dt.Xcode", url: nil, rules: rules) == nil)
    }

    @Test func waitsForTheGracePeriodThenCoolsDown() {
        var t = DistractionTracker()
        let yt = DistractionMatch.site(domain: "youtube.com")
        #expect(t.observe(yt, now: at(0)) == nil)
        #expect(t.observe(yt, now: at(5)) == nil)        // quick look is fine
        #expect(t.observe(yt, now: at(11)) == .nudge(yt))
        #expect(t.observe(yt, now: at(30)) == nil)       // no nagging
        #expect(t.observe(yt, now: at(11 + 181)) == .nudge(yt))
        #expect(t.nudges == 2)
    }

    @Test func quickVisitsNeverNudge() {
        var t = DistractionTracker()
        let yt = DistractionMatch.site(domain: "youtube.com")
        for i in stride(from: 0.0, to: 120, by: 12) {
            #expect(t.observe(yt, now: at(i)) == nil)
            #expect(t.observe(nil, now: at(i + 6)) == nil) // left before the grace ran out
        }
    }

    @Test func notesWhenYouComeBackAndHonoursSnooze() {
        var t = DistractionTracker()
        let app = DistractionMatch.app(bundleID: "com.valvesoftware.steam")
        _ = t.observe(app, now: at(0))
        #expect(t.observe(app, now: at(12)) == .nudge(app))
        #expect(t.observe(nil, now: at(20)) == .cameBack)

        var s = DistractionTracker()
        _ = s.observe(app, now: at(0))
        s.snooze(minutes: 5, now: at(1))
        #expect(s.observe(app, now: at(200)) == nil)
        #expect(s.observe(app, now: at(302)) == .nudge(app))
    }
}
