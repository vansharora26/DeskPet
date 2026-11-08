import AppKit
import Combine
import DeskPetCore

/// Lets the pet wander: strolls along the bottom of the screen, hops onto the tops
/// of other apps' windows (and rides along when they move), trots after the cursor
/// now and then, and naps when you step away.
///
/// It only ever reads window *rectangles* (no titles, no contents, no screen
/// recording) and the time since the last input event. It stays put whenever
/// you might want to click it: while hovered, dragged, in keyboard mode, during
/// a focus session or voice chat, or while a reminder bubble is showing.
@MainActor
final class PetRoamer {
    private let window: PetWindowController
    private let settings: AppSettings
    private let pet: PetViewModel
    private let isAllowed: () -> Bool

    private enum Motion {
        case sitting(until: Date)
        case walking(toX: CGFloat, speed: CGFloat)
        case jumping(from: CGPoint, to: CGPoint, surface: RoamSurface, start: Date, duration: TimeInterval)
    }

    private var motion: Motion = .sitting(until: .distantPast)
    private var surface: RoamSurface?
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTick = Date()
    private var lastPerchCheck = Date.distantPast
    private var lastDragEnd = Date.distantPast
    private var rng = SystemRandomNumberGenerator()
    private var cancellables = Set<AnyCancellable>()

    /// Points per second.
    private static let walkSpeed: CGFloat = 70
    private static let chaseSpeed: CGFloat = 120
    /// After you drop the pet somewhere in mid-air, it waits this long before hopping down.
    private static let midAirGrace: TimeInterval = 20

    init(window: PetWindowController, settings: AppSettings, pet: PetViewModel, isAllowed: @escaping () -> Bool) {
        self.window = window
        self.settings = settings
        self.pet = pet
        self.isAllowed = isAllowed

        // A drag ends wherever the user put it: work out what (if anything) it's standing on.
        window.state.$isDragging.removeDuplicates().dropFirst()
            .sink { [weak self] dragging in
                guard let self else { return }
                if dragging { self.halt() } else { self.landAfterDrag() }
            }
            .store(in: &cancellables)

        // Re-evaluate promptly when anything that can pause roaming changes.
        Publishers.MergeMany(
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            window.state.$isHovered.map { _ in () }.eraseToAnyPublisher(),
            window.state.$isVisible.map { _ in () }.eraseToAnyPublisher(),
            pet.$mode.map { _ in () }.eraseToAnyPublisher(),
            pet.$callout.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.schedule() }
        .store(in: &cancellables)
    }

    func start() {
        surface = surfaceUnderFoot()
        schedule()
    }

    // MARK: - Gating

    private var enabled: Bool {
        settings.roamingEnabled && settings.effectiveAnimations && window.state.isVisible && isAllowed()
    }

    /// Conditions under which the pet holds still (it may resume later).
    private var shouldHold: Bool {
        let s = window.state
        return s.isHovered || s.isDragging || s.keyboardMode || pet.isSleeping || pet.mode != .none || pet.callout != nil
    }

    private var isMoving: Bool {
        if case .sitting = motion { return false }
        return true
    }

    // MARK: - Timer

    private func schedule() {
        guard enabled else {
            stopTimer()
            halt()
            if window.state.napping { window.state.napping = false }
            return
        }
        setTimer(isMoving ? 1.0 / 30 : 0.5)
    }

    private func setTimer(_ interval: TimeInterval) {
        guard interval != timerInterval else { return }
        timer?.invalidate()
        timerInterval = interval
        lastTick = Date()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerInterval = 0
    }

    // MARK: - Tick

    private func tick() {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        guard enabled else { schedule(); return }

        if handleNap() { return }

        // Jumps always finish (they're short); walks stop the moment you reach for the pet.
        if case .jumping = motion {} else if shouldHold {
            halt()
            return
        }

        if now.timeIntervalSince(lastPerchCheck) > 1 {
            lastPerchCheck = now
            checkFooting(now: now)
        }

        switch motion {
        case .sitting(let until):
            if now >= until { decide() }
        case .walking(let toX, let speed):
            var foot = window.catFoot
            let step = speed * dt
            if abs(toX - foot.x) <= step {
                foot.x = toX
                window.moveCat(footAt: foot)
                sit(for: .random(in: 1.5...4, using: &rng))
            } else {
                foot.x += toX > foot.x ? step : -step
                window.moveCat(footAt: foot)
            }
        case .jumping(let from, let to, let target, let start, let duration):
            let t = now.timeIntervalSince(start) / duration
            let p = RoamJump.position(from: (from.x, from.y), to: (to.x, to.y), t: t)
            window.moveCat(footAt: CGPoint(x: p.x, y: p.y))
            if t >= 1 {
                surface = target
                sit(for: .random(in: 2...5, using: &rng))
            }
        }
    }

    /// Curls up when you've been away a while; wakes when you're back. Returns true while napping.
    private func handleNap() -> Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0) ?? .null)
        if window.state.napping {
            if idle < 2 || !settings.roamNapWhenIdle || pet.mode != .none {
                window.state.napping = false
                pet.react(.waking)
                sit(for: 3)
            }
            return window.state.napping
        }
        guard settings.roamNapWhenIdle, !isMoving, !shouldHold, idle >= RoamPlanner.napAfter else { return false }
        window.state.napping = true
        setGait(.still)
        return true
    }

    // MARK: - Decisions

    private func decide() {
        guard let screen = window.catScreen else { return }
        let foot = window.catFoot
        let floor = floorSurface(screen)
        let half = window.catHalfWidth

        guard let current = surface else {
            // Standing on nothing (dropped mid-air, or launched there): hop down after a moment.
            if Date().timeIntervalSince(lastDragEnd) > Self.midAirGrace {
                jump(to: floor, x: floor.clamp(foot.x, halfWidth: half))
            } else {
                sit(for: 2)
            }
            return
        }

        let situation = RoamPlanner.Situation(
            x: foot.x, halfWidth: half, surface: current, floor: floor,
            perches: settings.roamClimbWindows ? perches(on: screen) : [],
            cursorX: screen.frame.contains(NSEvent.mouseLocation) ? NSEvent.mouseLocation.x : nil,
            idleSeconds: 0, // naps are handled separately so they can end the moment you return
            preferences: RoamPreferences(chaseCursor: settings.roamChaseCursor, climbWindows: settings.roamClimbWindows,
                                         napWhenIdle: false))
        // Low battery makes the cat lazy: longer rests, slower walks, fewer jumps;
        // at critical it mostly stays put.
        let battery = BatteryMonitor.shared.effectiveMood
        let speed = CGFloat(battery.walkSpeedFactor)
        let tooTired = battery == .critical && Double.random(in: 0...1, using: &rng) < 0.75
        switch RoamPlanner.next(situation, using: &rng) {
        case .sit(let seconds): sit(for: seconds * battery.restFactor)
        case .walk(let x): tooTired ? sit(for: 8) : walk(to: x, speed: Self.walkSpeed * speed)
        case .chase(let x):
            if battery.isDrained { sit(for: 6 * battery.restFactor) } else { walk(to: x, speed: Self.chaseSpeed) }
        case .jump(let target, let x):
            // Hopping *down* is fine; climbing up takes energy it doesn't have.
            if battery.isDrained && target.y > foot.y + 4 && (battery == .critical || Bool.random(using: &rng)) {
                sit(for: 6 * battery.restFactor)
            } else {
                jump(to: target, x: x)
            }
        case .nap: sit(for: 5)
        }
    }

    private func sit(for seconds: TimeInterval) {
        motion = .sitting(until: Date().addingTimeInterval(seconds))
        setGait(.still)
        window.savePosition()
        setTimer(0.5)
    }

    private func walk(to x: CGFloat, speed: CGFloat) {
        motion = .walking(toX: x, speed: speed)
        window.state.facingLeft = x < window.catFoot.x
        setGait(.walking)
        setTimer(1.0 / 30)
    }

    private func jump(to target: RoamSurface, x: CGFloat) {
        let from = window.catFoot
        let to = CGPoint(x: x, y: target.y)
        if abs(to.x - from.x) > 4 { window.state.facingLeft = to.x < from.x }
        let duration = RoamJump.duration(from: (from.x, from.y), to: (to.x, to.y))
        motion = .jumping(from: from, to: to, surface: target, start: Date(), duration: duration)
        setGait(to.y < from.y - 4 ? .falling : .jumping)
        setTimer(1.0 / 30)
    }

    /// Stops wherever the pet is (walks can be interrupted; position is kept).
    private func halt() {
        if case .jumping = motion { return }
        if isMoving { window.savePosition() }
        motion = .sitting(until: Date().addingTimeInterval(.random(in: 3...6, using: &rng)))
        setGait(.still)
        if timer != nil { setTimer(0.5) }
    }

    private func setGait(_ gait: PetGait) {
        if window.state.gait != gait { window.state.gait = gait }
    }

    // MARK: - Surfaces

    private func floorSurface(_ screen: NSScreen) -> RoamSurface {
        let v = screen.visibleFrame
        return RoamSurface(windowID: nil, minX: v.minX, maxX: v.maxX, y: v.minY)
    }

    /// What the pet is standing on after a drag: the floor, a window top, or nothing.
    private func landAfterDrag() {
        lastDragEnd = Date()
        motion = .sitting(until: Date().addingTimeInterval(4))
        surface = surfaceUnderFoot()
        schedule()
    }

    private func surfaceUnderFoot() -> RoamSurface? {
        guard let screen = window.catScreen else { return nil }
        let foot = window.catFoot
        let floor = floorSurface(screen)
        if abs(foot.y - floor.y) < 6 { return floor }
        return perches(on: screen).first { abs($0.y - foot.y) < 12 && foot.x >= $0.minX && foot.x <= $0.maxX }
            .map { perch in
                window.moveCat(footAt: CGPoint(x: foot.x, y: perch.y)) // settle exactly onto the edge
                return perch
            }
    }

    /// The window under the pet moved, resized or closed: ride along, or fall.
    private func checkFooting(now: Date) {
        guard case .sitting = motion else { return }
        guard let current = surface, let screen = window.catScreen else { return }
        if current.isFloor {
            let floor = floorSurface(screen)
            if abs(floor.y - current.y) > 0.5 || floor.minX != current.minX {
                surface = floor // Dock or display changed
                window.moveCat(footAt: CGPoint(x: floor.clamp(window.catFoot.x, halfWidth: window.catHalfWidth), y: floor.y))
            }
            return
        }
        let updated = perches(on: screen).first { $0.windowID == current.windowID }
        if let (s, x) = RoamPlanner.follow(current, x: window.catFoot.x, halfWidth: window.catHalfWidth, updated: updated) {
            surface = s
            window.moveCat(footAt: CGPoint(x: x, y: s.y))
        } else {
            let floor = floorSurface(screen)
            jump(to: floor, x: floor.clamp(window.catFoot.x, halfWidth: window.catHalfWidth))
        }
    }

    /// Tops of other apps' visible windows on this screen that the pet could sit on.
    /// Uses window bounds only (available without Screen Recording permission).
    private func perches(on screen: NSScreen) -> [RoamSurface] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let me = ProcessInfo.processInfo.processIdentifier
        let visible = screen.visibleFrame
        let catHeight = window.catHeight
        var inFront: [CGRect] = []
        var result: [RoamSurface] = []

        for info in list { // front to back
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            let rect = CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
            defer { inFront.append(rect) }
            guard let id = info[kCGWindowNumber as String] as? Int,
                  (info[kCGWindowOwnerPID as String] as? Int32) != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  rect.width >= 160, rect.height >= 80 else { continue }
            let top = rect.maxY
            // Needs headroom for the pet, and must be on this screen.
            guard top + catHeight <= visible.maxY - 2, top > visible.minY + 40,
                  rect.maxX > visible.minX + 60, rect.minX < visible.maxX - 60 else { continue }
            // Skip edges hidden behind a window that's in front.
            let probes = [0.25, 0.5, 0.75].map { CGPoint(x: rect.minX + rect.width * $0, y: top - 3) }
            if probes.contains(where: { p in inFront.contains { $0.contains(p) } }) { continue }
            result.append(RoamSurface(windowID: id,
                                      minX: max(rect.minX, visible.minX), maxX: min(rect.maxX, visible.maxX), y: top))
        }
        return result
    }
}
