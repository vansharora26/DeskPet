import CoreGraphics
import DeskPetCore
import Foundation

/// Ongoing states that come from real app state (not guesses about the user):
/// a running focus timer, a running break, or a hydration reminder on screen.
enum PetMode: Equatable {
    case none, focused, resting, thirsty
    /// Voice conversation states (from the real mic / AI / synthesizer state).
    case listening, thinking, speaking
}

/// What the roaming pet's body is doing.
enum PetGait: Equatable { case still, walking, jumping, falling }

/// One rendered frame of the pet: sprite pose plus whole-body motion.
struct PetFrame: Equatable {
    var pose = CatPose()
    /// Upward offset in sprite pixels.
    var hop: CGFloat = 0
    /// Vertical stretch (>1) or squash (<1), anchored at the feet.
    var stretch: CGFloat = 1
    /// Horizontal shake in sprite pixels.
    var shake: CGFloat = 0
    /// Mirrored so the cat faces the way it's walking.
    var facingLeft = false
}

/// Pure function of (time, state) → frame. No stored animation state, so the
/// timeline can pause or skip frames freely without anything drifting.
enum PetAnimator {
    struct Input {
        var reaction: PetViewModel.Reaction?
        var reactionAge: TimeInterval
        var sleeping: Bool
        var mood: PetMood
        var mode: PetMode = .none
        var hovered: Bool
        var animate: Bool
        var coat: CoatTheme = .ginger
        var accessory: Accessory?
        var eyeColor: EyeColor?
        var gait: PetGait = .still
        var facingLeft = false
        /// Curled up because the user stepped away (roaming nap; doesn't touch stats).
        var napping = false
        /// How the Mac's battery makes the cat feel.
        var battery: BatteryMood = .none
    }

    static func frame(at time: TimeInterval, _ input: Input) -> PetFrame {
        // With animations off, freeze time at a representative moment.
        let t = input.animate ? time : 0
        let age = input.animate ? input.reactionAge : 0.5
        var f = PetFrame()
        f.pose.coat = input.coat
        f.pose.accessory = input.accessory
        f.pose.eyeColor = input.eyeColor
        f.pose.headband = input.mode == .focused
        f.facingLeft = input.facingLeft

        if input.sleeping || input.napping {
            f.pose.eyes = .closed
            f.pose.tailFrame = 0
            return f
        }

        let drained = input.battery.isDrained
        switch input.gait {
        case .walking:
            // Tired cats trudge: slower steps, barely lifting, droopy face.
            let step = drained ? 0.27 : 0.16
            f.pose.pawStep = Int(t / step) % 2 + 1
            f.hop = abs(sin(t * .pi / (step * 2))) * (drained ? 0.25 : 0.7)
            f.pose.tailFrame = Int(t / (step * 2)) % 2
            f.pose.eyes = isBlinking(t) ? .blink : (drained ? .sleepy : .open)
            if drained {
                f.pose.sad = true
                f.pose.earDroop = input.battery == .critical ? 1 : 0.55
            }
            return f
        case .jumping:
            f.pose.eyes = .happy
            f.pose.mouthOpen = true
            f.stretch = 1.05
            return f
        case .falling:
            f.pose.eyes = .open
            f.pose.mouthOpen = true
            f.stretch = 1.04
            return f
        case .still:
            break
        }

        switch input.reaction {
        case .petted:
            f.pose.eyes = .happy
            f.pose.blush = true
            f.pose.mouthOpen = true
            f.pose.tailFrame = Int(t / 0.18) % 2
            if age < 0.4 { f.hop = sin(age / 0.4 * .pi) * 3 }

        case .eating, .sipping:
            let chew = Int(age / 0.22) % 2 == 0
            f.pose.eyes = .happy
            f.pose.mouthOpen = chew
            f.pose.tailFrame = Int(t / 0.3) % 2
            f.stretch = chew ? 1 : 0.97

        case .playing:
            let bounce = abs(sin(age * .pi * 2.2))
            f.hop = bounce * 5
            f.pose.eyes = bounce > 0.6 ? .happy : .open
            f.pose.mouthOpen = true
            f.pose.blush = true
            f.pose.tailFrame = Int(t / 0.15) % 2
            if bounce < 0.15 { f.stretch = 0.93 } // squash on landing

        case .celebrating:
            let bounce = abs(sin(age * .pi * 1.6))
            f.hop = bounce * 4
            f.pose.eyes = .happy
            f.pose.mouthOpen = true
            f.pose.blush = true
            f.pose.tailFrame = Int(t / 0.12) % 2
            if bounce < 0.12 { f.stretch = 0.94 }

        case .waking:
            f.pose.eyes = age < 0.6 ? .sleepy : .open
            f.stretch = age < 0.6 ? 1 + 0.06 * sin(age / 0.6 * .pi) : 1 // big stretch

        case .refused:
            f.pose.eyes = .sleepy
            f.shake = sin(age * 32) * 1.2 * max(0, 1 - age)

        case nil:
            switch input.mode {
            case .focused:
                // Calm and steady: slow tail, regular blinks, no fidgeting.
                f.pose.tailFrame = Int(t / 1.8) % 2
                f.pose.eyes = isBlinking(t) ? .blink : .open
                return f
            case .resting:
                f.pose.tailFrame = Int(t / 1.2) % 2
                f.pose.eyes = .happy
                f.pose.blush = input.hovered
                return f
            case .thirsty:
                f.pose.tailFrame = Int(t / 1.0) % 2
                f.pose.eyes = isBlinking(t) ? .blink : .open
                f.pose.mouthOpen = true
                return f
            case .listening:
                // All ears: wide eyes, rosy cheeks, tail held still, a tiny attentive lean.
                f.pose.eyes = isBlinking(t) ? .blink : .open
                f.pose.blush = true
                f.pose.tailFrame = 0
                f.hop = input.animate ? 0.5 + sin(t * 4) * 0.5 : 0
                return f
            case .thinking:
                f.pose.eyes = isBlinking(t) ? .blink : .lookUp
                f.pose.tailFrame = Int(t / 0.9) % 2
                return f
            case .speaking:
                f.pose.eyes = isBlinking(t) ? .blink : .open
                f.pose.mouthOpen = input.animate ? Int(t / 0.13) % 3 != 2 : true
                f.pose.tailFrame = Int(t / 0.5) % 2
                return f
            case .none:
                break
            }
            if let tired = batteryFrame(f, t: t, input) { return tired }
            // Charging perks the cat up: ignore tired/sad pet stats meanwhile.
            let mood: PetMood = input.battery == .charging && (input.mood == .tired || input.mood == .sad) ? .content : input.mood
            f.pose.tailFrame = Int(t / (mood == .hungry ? 1.4 : 0.7)) % 2
            if input.battery == .charging {
                f.pose.blush = true
                // A happy squint now and then while it charges.
                if input.animate && t.truncatingRemainder(dividingBy: 6) < 0.9 { f.pose.eyes = .happy; return f }
            }
            switch mood {
            case .tired:
                f.pose.eyes = .sleepy
            default:
                f.pose.eyes = isBlinking(t) ? .blink : .open
            }
            if input.hovered {
                f.pose.blush = true
                if mood != .tired && !isBlinking(t) { f.pose.eyes = .open }
            }
            if mood == .happy && input.animate {
                // A contented little hop now and then.
                let p = t.truncatingRemainder(dividingBy: 9)
                if p < 0.35 { f.hop = sin(p / 0.35 * .pi) * 2; f.pose.eyes = .happy }
            }
        }
        return f
    }

    /// Low battery: sad and lazy. Critical: exhausted, nodding off. nil when the battery is fine.
    static func batteryFrame(_ base: PetFrame, t: TimeInterval, _ input: Input) -> PetFrame? {
        var f = base
        switch input.battery {
        case .low:
            f.pose.sad = true
            f.pose.earDroop = 0.55
            f.pose.eyes = isBlinking(t) ? .blink : .sleepy
            f.pose.tailFrame = Int(t / 2.6) % 2                       // lazy tail
            f.stretch = 0.955 + (input.animate ? sin(t * 1.2) * 0.01 : 0) // slouched, slow breaths
            if input.animate {
                // A big yawn every 12 s.
                let p = t.truncatingRemainder(dividingBy: 12)
                if p < 1.5 {
                    f.pose.eyes = .closed
                    f.pose.mouthOpen = true
                    f.stretch = 0.955 + 0.05 * sin(p / 1.5 * .pi)
                }
            }
            if input.hovered && !f.pose.mouthOpen { f.pose.eyes = .sleepy }
            return f
        case .critical:
            f.pose.sad = true
            f.pose.earDroop = 1
            f.pose.tailFrame = 0                                       // too tired to wag
            f.stretch = 0.91 + (input.animate ? sin(t * 0.9) * 0.012 : 0) // slumped
            // Nodding off: eyes drift shut for a couple of seconds, then jolt half-open.
            let p = input.animate ? t.truncatingRemainder(dividingBy: 7) : 0
            f.pose.eyes = p > 4.6 ? .closed : .sleepy
            if p > 4.6 { f.stretch -= 0.015 }
            return f
        default:
            return nil
        }
    }

    /// Natural-looking blinks: one every ~4.3 s, a double blink every third time.
    /// Each blink lasts slightly longer than one idle frame (1/6 s) so it's never skipped.
    static func isBlinking(_ t: TimeInterval) -> Bool {
        let period = 4.3
        let p = t.truncatingRemainder(dividingBy: period)
        if p < 0.18 { return true }
        return Int(t / period) % 3 == 0 && p > 0.42 && p < 0.60
    }
}
