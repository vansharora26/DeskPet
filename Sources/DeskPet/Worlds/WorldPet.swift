import DeskPetCore
import SwiftUI

enum WorldSessionState: Equatable { case idle, running, paused, completed }

/// DeskPet inside a world: the same pixel cat (coat & accessory included),
/// with behaviour suited to the environment. Low frame rate, still when motion is off,
/// and it never speaks during a running focus session.
struct WorldPet: View {
    let world: FocusWorld
    let state: WorldSessionState
    let coat: CoatTheme
    let accessory: Accessory?
    let motion: MotionLevel
    var pixel: CGFloat = 7
    /// Brief celebration (milestone ticked, sprint finished).
    var celebrateUntil: Date = .distantPast
    var active = true

    var body: some View {
        Group {
            if motion == .still || !active {
                CatCanvas(pose: Self.frame(world: world, state: state, t: 0, animate: false, celebrating: false,
                                           coat: coat, accessory: accessory).pose, pixel: pixel)
            } else {
                Ticking(every: motion == .full ? 1.0 / 8 : 1.0 / 5) { tl in
                    let t = tl.timeIntervalSinceReferenceDate
                    let f = Self.frame(world: world, state: state, t: t, animate: true,
                                       celebrating: tl < celebrateUntil, coat: coat, accessory: accessory)
                    CatCanvas(pose: f.pose, pixel: pixel)
                        .scaleEffect(x: 1, y: f.stretch, anchor: .bottom)
                        .offset(y: -f.hop * pixel)
                }
            }
        }
        .frame(width: CGFloat(CatSprite.width) * pixel, height: CGFloat(CatSprite.height) * pixel)
        .accessibilityElement()
        .accessibilityLabel(Self.description(world: world, state: state))
    }

    static func description(world: FocusWorld, state: WorldSessionState) -> String {
        switch (world, state) {
        case (_, .completed): return "Your pet is celebrating"
        case (_, .paused): return "Your pet is waiting patiently"
        case (.deepFocus, _): return "Your pet is sitting quietly"
        case (.study, _): return "Your pet is studying with you"
        case (.workSprint, _): return "Your pet is cheering you on"
        case (.recharge, _): return "Your pet is relaxing"
        case (.planning, _): return "Your pet is ready to plan"
        }
    }

    static func frame(world: FocusWorld, state: WorldSessionState, t: TimeInterval, animate: Bool,
                      celebrating: Bool, coat: CoatTheme, accessory: Accessory?) -> PetFrame {
        var f = PetFrame()
        f.pose.coat = coat
        f.pose.accessory = accessory
        if celebrating || state == .completed {
            let bounce = animate ? abs(sin(t * .pi * 1.6)) : 0.6
            f.pose.eyes = .happy
            f.pose.mouthOpen = true
            f.pose.blush = true
            f.pose.tailFrame = Int(t / 0.15) % 2
            f.hop = bounce * 3
            return f
        }
        if state == .paused {
            f.pose.eyes = .sleepy
            return f
        }
        let blink = animate && PetAnimator.isBlinking(t)
        switch world {
        case .deepFocus:
            // Barely moving: slow blinks (every other cycle) and a lazy tail.
            f.pose.eyes = (blink && Int(t / 4.3) % 2 == 0) ? .blink : .open
            f.pose.tailFrame = animate ? Int(t / 2.6) % 2 : 0
        case .study:
            let reading = animate && Int(t / 5) % 3 == 1
            f.pose.eyes = blink ? .blink : (reading ? .lookUp : .open)
            f.pose.tailFrame = animate ? Int(t / 1.2) % 2 : 0
            f.pose.blush = state == .running
        case .workSprint:
            f.pose.headband = true
            f.pose.eyes = blink ? .blink : .open
            f.pose.tailFrame = animate ? Int(t / 0.35) % 2 : 0
            if animate && state == .running {
                let p = t.truncatingRemainder(dividingBy: 3.2)
                if p < 0.3 { f.hop = sin(p / 0.3 * .pi) * 1.5 }
            }
        case .recharge:
            f.pose.eyes = .closed
            f.pose.blush = true
            f.pose.tailFrame = 0
            // Gentle "breathing", matching the 8-second breathing guide.
            if animate { f.stretch = 1 + 0.025 * sin(2 * .pi * t / 8) }
        case .planning:
            f.pose.eyes = blink ? .blink : .open
            f.pose.blush = true
            f.pose.tailFrame = animate ? Int(t / 0.8) % 2 : 0
            if animate {
                let p = t.truncatingRemainder(dividingBy: 7)
                if p < 0.3 { f.hop = sin(p / 0.3 * .pi) * 2 }
            }
        }
        return f
    }
}
