import CoreGraphics

/// Single source of truth for where things sit inside the pet window.
/// Coordinates are top-left origin (SwiftUI space), in points.
struct PetLayout: Equatable {
    let pixel: CGFloat

    static let bubbleHeight: CGFloat = 96   // room for a 2-line callout with buttons
    static let gap: CGFloat = 4
    static let barHeight: CGFloat = 34
    static let barWidth: CGFloat = 234

    /// Headroom above the cat so the biggest hop (5 sprite px) never reaches the bubble.
    var hopRoom: CGFloat { (pixel * 5 + 4).rounded() }

    var catSize: CGSize {
        CGSize(width: CGFloat(CatSprite.width) * pixel, height: CGFloat(CatSprite.height) * pixel)
    }

    // Hover spread: labelled pills that fly out of the cat into columns beside it.
    static let pillSize = CGSize(width: 118, height: 26)
    static let pillSpacing: CGFloat = 6
    /// How far the middle of each column bows outward, so the columns hug the cat.
    static let pillBulge: CGFloat = 10
    /// Gap from the body centre to the inner edge of a column (clears the tail on either side).
    var pillClearance: CGFloat { 15 * pixel + 2 }

    /// Speech bubbles keep their old width even though the window is wider.
    static let bubbleMaxWidth: CGFloat = 228

    var windowSize: CGSize {
        CGSize(
            width: max(240, 2 * (pillClearance + Self.pillBulge + Self.pillSize.width) + 8),
            height: Self.bubbleHeight + hopRoom + catSize.height + Self.gap + Self.barHeight
        )
    }

    /// Top-left of the cat canvas. The *body* (not the tail) is centred.
    var catOrigin: CGPoint {
        CGPoint(x: (windowSize.width / 2 - 9 * pixel).rounded(), y: Self.bubbleHeight + hopRoom)
    }

    /// Height of the area the speech bubble sits in (its bottom edge is just above
    /// the cat's head). While the cat hops around, the bubble moves up out of the way.
    func bubbleAreaHeight(lifted: Bool) -> CGFloat {
        catOrigin.y - 2 - (lifted ? hopRoom - 2 : 0)
    }

    /// Canvas frame of the cat sprite.
    var catFrame: CGRect { CGRect(origin: catOrigin, size: catSize) }

    /// The cat's clickable silhouette: body block plus the tail block.
    var catHitRects: [CGRect] {
        let o = catOrigin
        let top = CGFloat(CatSprite.top) * pixel
        return [
            CGRect(x: o.x, y: o.y + top, width: 18 * pixel, height: 19 * pixel),
            CGRect(x: o.x + 17 * pixel, y: o.y + top + 9 * pixel, width: 7 * pixel, height: 10 * pixel),
        ]
    }

    /// The body's centre point (not the tail).
    var bodyCenter: CGPoint {
        CGPoint(x: catOrigin.x + 9 * pixel, y: catOrigin.y + (CGFloat(CatSprite.top) + 9.5) * pixel)
    }

    /// Where each spread pill sits once fully out. `.split` puts the first half on the
    /// left and the rest on the right; one-sided modes stack everything in one column.
    func spreadFrames(count: Int, mode: SpreadMode) -> [CGRect] {
        let w = Self.pillSize.width, h = Self.pillSize.height
        func column(_ n: Int, side: CGFloat, spacing: CGFloat, top: CGFloat) -> [CGRect] {
            (0..<n).map { i in
                let bow = n > 1 ? Self.pillBulge * sin(.pi * (CGFloat(i) + 0.5) / CGFloat(n)) : Self.pillBulge
                let inner = bodyCenter.x + side * (pillClearance + bow)
                let x = side < 0 ? inner - w : inner
                return CGRect(x: x.rounded(), y: (top + CGFloat(i) * (h + spacing)).rounded(), width: w, height: h)
            }
        }
        switch mode {
        case .split:
            let left = (count + 1) / 2, right = count - left
            let colHeight = CGFloat(max(left, right)) * (h + Self.pillSpacing) - Self.pillSpacing
            let top = bodyCenter.y - colHeight / 2
            return column(left, side: -1, spacing: Self.pillSpacing, top: top)
                + column(right, side: 1, spacing: Self.pillSpacing, top: top)
        case .leftOnly, .rightOnly:
            let spacing: CGFloat = 3
            let colHeight = CGFloat(count) * (h + spacing) - spacing
            let top = max(4, catFrame.maxY + Self.gap - colHeight)
            return column(count, side: mode == .leftOnly ? -1 : 1, spacing: spacing, top: top)
        }
    }

    /// Moves the speech bubble clear of a one-sided column while the spread is open.
    func bubbleShift(for mode: SpreadMode) -> CGFloat {
        let overlap = Self.bubbleMaxWidth / 2 - pillClearance + 6
        switch mode {
        case .split: return 0
        case .rightOnly: return -max(0, overlap)
        case .leftOnly: return max(0, overlap)
        }
    }

    /// Room a column needs beside the cat, used to pick a spread mode near screen edges.
    var spreadSideRoom: CGFloat { pillClearance + Self.pillBulge + Self.pillSize.width - 9 * pixel }

    var barFrame: CGRect {
        CGRect(
            x: (windowSize.width - Self.barWidth) / 2,
            y: windowSize.height - Self.barHeight,
            width: Self.barWidth,
            height: Self.barHeight
        )
    }
}

/// Which side(s) of the cat the hover spread opens to.
enum SpreadMode: Equatable { case split, leftOnly, rightOnly }
