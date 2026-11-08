import Foundation
import Testing
@testable import DeskPetCore

/// Deterministic generator so planner decisions are repeatable.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private let floor = RoamSurface(windowID: nil, minX: 0, maxX: 1440, y: 80)
private let window = RoamSurface(windowID: 42, minX: 200, maxX: 900, y: 600)

private func situation(x: Double = 700, on surface: RoamSurface = floor, perches: [RoamSurface] = [window],
                       cursor: Double? = nil, idle: Double = 0,
                       prefs: RoamPreferences = RoamPreferences()) -> RoamPlanner.Situation {
    .init(x: x, halfWidth: 45, surface: surface, floor: floor, perches: perches, cursorX: cursor,
          idleSeconds: idle, preferences: prefs)
}

private func actions(_ s: RoamPlanner.Situation, count: Int = 400) -> [RoamAction] {
    var rng = SeededRNG(state: 7)
    return (0..<count).map { _ in RoamPlanner.next(s, using: &rng) }
}

@Suite struct RoamingTests {
    @Test func napsOnlyWhenIdleAndAllowed() {
        var rng = SeededRNG(state: 1)
        #expect(RoamPlanner.next(situation(idle: 200), using: &rng) == .nap)
        #expect(RoamPlanner.next(situation(idle: 200, prefs: RoamPreferences(napWhenIdle: false)), using: &rng) != .nap)
        #expect(!actions(situation(idle: 10)).contains(.nap))
    }

    @Test func staysOnItsSurface() {
        for a in actions(situation()) {
            switch a {
            case .walk(let x), .chase(let x):
                #expect(x >= floor.minX + 45 && x <= floor.maxX - 45)
            case .jump(let s, let x):
                #expect(s == window)
                #expect(x >= window.minX + 45 && x <= window.maxX - 45)
            default: break
            }
        }
    }

    @Test func respectsPreferences() {
        let noClimb = actions(situation(cursor: 100, prefs: RoamPreferences(chaseCursor: false, climbWindows: false)))
        #expect(!noClimb.contains { if case .jump = $0 { return true }; return false })
        #expect(!noClimb.contains { if case .chase = $0 { return true }; return false })

        let all = actions(situation(cursor: 100))
        #expect(all.contains { if case .jump = $0 { return true }; return false })
        #expect(all.contains(.chase(toX: 100)))
    }

    @Test func ignoresPerchesTooNarrowForThePet() {
        let ledge = RoamSurface(windowID: 9, minX: 300, maxX: 380, y: 500)
        #expect(!actions(situation(perches: [ledge])).contains { if case .jump = $0 { return true }; return false })
    }

    @Test func eventuallyHopsDownFromAWindow() {
        let a = actions(situation(x: 500, on: window))
        #expect(a.contains { if case .jump(let s, _) = $0 { return s.isFloor }; return false })
        #expect(!a.contains { if case .chase = $0 { return true }; return false }) // no chasing off a ledge
    }

    @Test func ridesAlongOrFalls() {
        // Window dragged 100 pt right: the pet moves with it.
        let moved = RoamSurface(windowID: 42, minX: 300, maxX: 1000, y: 640)
        let follow = RoamPlanner.follow(window, x: 500, halfWidth: 45, updated: moved)
        #expect(follow?.x == 600 && follow?.surface == moved)
        // Window closed or shrunk out from under it: falls.
        #expect(RoamPlanner.follow(window, x: 500, halfWidth: 45, updated: nil) == nil)
        let shrunk = RoamSurface(windowID: 42, minX: 200, maxX: 400, y: 600)
        #expect(RoamPlanner.follow(window, x: 800, halfWidth: 45, updated: shrunk) == nil)
    }

    @Test func jumpArcStartsEndsAndClears() {
        let a = (x: 100.0, y: 80.0), b = (x: 400.0, y: 600.0)
        let start = RoamJump.position(from: a, to: b, t: 0), end = RoamJump.position(from: a, to: b, t: 1)
        #expect(start.x == 100 && start.y == 80 && end.x == 400 && end.y == 600)
        let mid = RoamJump.position(from: a, to: b, t: 0.5)
        #expect(mid.y > 600) // clears the window edge before landing
        #expect(RoamJump.duration(from: a, to: b) <= 1.1)
    }
}
