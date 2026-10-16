import CoreGraphics

/// Single source of truth for where things sit inside the pet window.
/// Coordinates are top-left origin (SwiftUI space), in points.
struct PetLayout: Equatable {
    let pixel: CGFloat

    static let bubbleHeight: CGFloat = 96   // room for a 2-line callout with buttons
    static let gap: CGFloat = 4
    static let barHeight: CGFloat = 34
    static let barWidth: CGFloat = 222

    /// Headroom above the cat so the biggest hop (5 sprite px) never reaches the bubble.
    var hopRoom: CGFloat { (pixel * 5 + 4).rounded() }

    var catSize: CGSize {
        CGSize(width: CGFloat(CatSprite.width) * pixel, height: CGFloat(CatSprite.height) * pixel)
    }

    var windowSize: CGSize {
        CGSize(
            width: max(240, catSize.width + 48),
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

    var barFrame: CGRect {
        CGRect(
            x: (windowSize.width - Self.barWidth) / 2,
            y: windowSize.height - Self.barHeight,
            width: Self.barWidth,
            height: Self.barHeight
        )
    }
}
