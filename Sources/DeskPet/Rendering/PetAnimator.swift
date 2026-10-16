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

/// One rendered frame of the pet: sprite pose plus whole-body motion.
struct PetFrame: Equatable {
    var pose = CatPose()
    /// Upward offset in sprite pixels.
    var hop: CGFloat = 0
    /// Vertical stretch (>1) or squash (<1), anchored at the feet.
    var stretch: CGFloat = 1
    /// Horizontal shake in sprite pixels.
    var shake: CGFloat = 0
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
    }

    static func frame(at time: TimeInterval, _ input: Input) -> PetFrame {
        // With animations off, freeze time at a representative moment.
        let t = input.animate ? time : 0
        let age = input.animate ? input.reactionAge : 0.5
        var f = PetFrame()
        f.pose.coat = input.coat
        f.pose.accessory = input.accessory
        f.pose.headband = input.mode == .focused

        if input.sleeping {
            f.pose.eyes = .closed
            f.pose.tailFrame = 0
            return f
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
            f.pose.tailFrame = Int(t / (input.mood == .hungry ? 1.4 : 0.7)) % 2
            switch input.mood {
            case .tired:
                f.pose.eyes = .sleepy
            default:
                f.pose.eyes = isBlinking(t) ? .blink : .open
            }
            if input.hovered {
                f.pose.blush = true
                if input.mood != .tired && !isBlinking(t) { f.pose.eyes = .open }
            }
            if input.mood == .happy && input.animate {
                // A contented little hop now and then.
                let p = t.truncatingRemainder(dividingBy: 9)
                if p < 0.35 { f.hop = sin(p / 0.35 * .pi) * 2; f.pose.eyes = .happy }
            }
        }
        return f
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
