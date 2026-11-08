import Foundation

// MARK: - Roaming: where the pet wanders next

/// A flat surface the pet can stand on: the floor (top of the Dock / bottom of the
/// screen) or the top edge of another app's window. Screen coordinates, y up.
public struct RoamSurface: Equatable, Sendable {
    /// nil for the floor; otherwise the window's number, so the pet can follow it.
    public var windowID: Int?
    public var minX: Double
    public var maxX: Double
    /// Height of the surface (where the pet's feet go).
    public var y: Double

    public init(windowID: Int?, minX: Double, maxX: Double, y: Double) {
        self.windowID = windowID
        self.minX = minX
        self.maxX = maxX
        self.y = y
    }

    public var isFloor: Bool { windowID == nil }
    public var width: Double { maxX - minX }

    /// Clamps a body-centre x so a pet of the given half-width stays on this surface.
    public func clamp(_ x: Double, halfWidth: Double) -> Double {
        guard width > halfWidth * 2 else { return (minX + maxX) / 2 }
        return min(max(x, minX + halfWidth), maxX - halfWidth)
    }
}

/// One step of wandering, chosen by `RoamPlanner`.
public enum RoamAction: Equatable, Sendable {
    /// Sit still (blink, swish) for a while.
    case sit(seconds: Double)
    /// Walk along the current surface to this body-centre x.
    case walk(toX: Double)
    /// Jump onto another surface, landing at this x.
    case jump(to: RoamSurface, x: Double)
    /// Trot over to where the cursor is (on the current surface).
    case chase(toX: Double)
    /// Curl up until the user is back.
    case nap
}

public struct RoamPreferences: Equatable, Sendable {
    public var chaseCursor = true
    public var climbWindows = true
    public var napWhenIdle = true
    public init(chaseCursor: Bool = true, climbWindows: Bool = true, napWhenIdle: Bool = true) {
        self.chaseCursor = chaseCursor
        self.climbWindows = climbWindows
        self.napWhenIdle = napWhenIdle
    }
}

/// Pure decision-making for the roaming pet. The app supplies what it can see
/// (surfaces, cursor, idle time); this decides what to do next.
public enum RoamPlanner {
    /// No input for this long (seconds) and the pet curls up for a nap.
    public static let napAfter: Double = 180
    /// Shortest walk worth making, in points.
    public static let minStroll: Double = 60

    public struct Situation: Sendable {
        public var x: Double
        public var halfWidth: Double
        public var surface: RoamSurface
        public var floor: RoamSurface
        public var perches: [RoamSurface]
        public var cursorX: Double?
        public var idleSeconds: Double
        public var preferences: RoamPreferences

        public init(x: Double, halfWidth: Double, surface: RoamSurface, floor: RoamSurface, perches: [RoamSurface],
                    cursorX: Double?, idleSeconds: Double, preferences: RoamPreferences) {
            self.x = x
            self.halfWidth = halfWidth
            self.surface = surface
            self.floor = floor
            self.perches = perches
            self.cursorX = cursorX
            self.idleSeconds = idleSeconds
            self.preferences = preferences
        }
    }

    public static func next<R: RandomNumberGenerator>(_ s: Situation, using rng: inout R) -> RoamAction {
        if s.preferences.napWhenIdle && s.idleSeconds >= napAfter { return .nap }

        let perches = s.preferences.climbWindows
            ? s.perches.filter { $0.width >= s.halfWidth * 2 + 20 && $0 != s.surface }
            : []
        let roll = Double.random(in: 0..<1, using: &rng)

        // On a window: mostly lounge, sometimes stroll, and eventually hop down.
        if !s.surface.isFloor {
            if roll < 0.5 { return .sit(seconds: .random(in: 6...16, using: &rng)) }
            if roll < 0.75, let x = strollTarget(s, on: s.surface, using: &rng) { return .walk(toX: x) }
            return .jump(to: s.floor, x: s.floor.clamp(s.x + .random(in: -80...80, using: &rng), halfWidth: s.halfWidth))
        }

        if roll < 0.45 { return .sit(seconds: .random(in: 4...12, using: &rng)) }
        if roll < 0.55, s.preferences.chaseCursor, let cx = s.cursorX {
            let target = s.surface.clamp(cx, halfWidth: s.halfWidth)
            if abs(target - s.x) >= minStroll { return .chase(toX: target) }
        }
        if roll < 0.70, let perch = perches.randomElement(using: &rng) {
            let x = perch.clamp(.random(in: perch.minX...perch.maxX, using: &rng), halfWidth: s.halfWidth)
            return .jump(to: perch, x: x)
        }
        if let x = strollTarget(s, on: s.surface, using: &rng) { return .walk(toX: x) }
        return .sit(seconds: .random(in: 4...10, using: &rng))
    }

    private static func strollTarget<R: RandomNumberGenerator>(_ s: Situation, on surface: RoamSurface,
                                                               using rng: inout R) -> Double? {
        let lo = surface.minX + s.halfWidth, hi = surface.maxX - s.halfWidth
        guard hi - lo >= minStroll else { return nil }
        for _ in 0..<6 {
            let x = Double.random(in: lo...hi, using: &rng)
            if abs(x - s.x) >= minStroll { return x }
        }
        return nil
    }

    /// Where the pet should be after the window it's standing on moved or closed:
    /// ride along if the window is still under its feet; nil means it falls to the floor.
    public static func follow(_ surface: RoamSurface, x: Double, halfWidth: Double,
                              updated: RoamSurface?) -> (surface: RoamSurface, x: Double)? {
        guard !surface.isFloor, let updated else { return nil }
        if updated == surface { return (surface, x) }
        let nx = x + (updated.minX - surface.minX)
        guard nx - halfWidth * 0.5 >= updated.minX && nx + halfWidth * 0.5 <= updated.maxX else { return nil }
        return (updated, nx)
    }
}

// MARK: - Jump arc

/// Parabolic hop between two foot positions. `t` runs 0…1.
public enum RoamJump {
    public static func duration(from a: (x: Double, y: Double), to b: (x: Double, y: Double)) -> Double {
        let d = hypot(b.x - a.x, b.y - a.y)
        return min(1.1, max(0.45, 0.35 + d / 900))
    }

    public static func position(from a: (x: Double, y: Double), to b: (x: Double, y: Double), t: Double) -> (x: Double, y: Double) {
        let t = min(1, max(0, t))
        // Peak a little above whichever end is higher; falling down needs only a small hop.
        let apex = max(a.y, b.y) + (b.y >= a.y ? 36 : 14)
        // Quadratic Bézier through a control point that makes the curve reach `apex`.
        let cy = 2 * apex - (a.y + b.y) / 2
        let x = a.x + (b.x - a.x) * t
        let y = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * cy + t * t * b.y
        return (x, y)
    }
}
