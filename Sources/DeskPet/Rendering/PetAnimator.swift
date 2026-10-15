import CoreGraphics
import DeskPetCore
import Foundation

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
        var hovered: Bool
        var animate: Bool
    }

    static func frame(at time: TimeInterval, _ input: Input) -> PetFrame {
        // With animations off, freeze time at a representative moment.
        let t = input.animate ? time : 0
        let age = input.animate ? input.reactionAge : 0.5
        var f = PetFrame()

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

        case .eating:
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

        case .waking:
            f.pose.eyes = age < 0.6 ? .sleepy : .open
            f.stretch = age < 0.6 ? 1 + 0.06 * sin(age / 0.6 * .pi) : 1 // big stretch

        case .refused:
            f.pose.eyes = .sleepy
            f.shake = sin(age * 32) * 1.2 * max(0, 1 - age)

        case nil:
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
