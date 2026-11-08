import DeskPetCore
import SwiftUI

/// Everything needed to draw one frame of the cat.
struct CatPose: Hashable {
    enum Eyes: Hashable { case open, blink, happy, sleepy, closed, lookUp }
    var eyes: Eyes = .open
    var mouthOpen = false
    var blush = false
    var tailFrame = 0
    var coat: CoatTheme = .ginger
    var accessory: Accessory?
    /// Worn during focus sessions.
    var headband = false
    /// nil = the coat's natural eye colour.
    var eyeColor: EyeColor?
    /// Walking: 0 both paws down, 1 left paw lifted, 2 right paw lifted.
    var pawStep = 0
    /// Worried brows and a frown (low battery).
    var sad = false
    /// 0 = ears up, 1 = fully drooped out to the sides.
    var earDroop: CGFloat = 0
}

/// How the coat's colours are laid out on the body.
enum CoatPattern { case tabby, solid, tuxedo, calico, points }

/// Colour roles that change with the coat theme.
struct CoatPalette {
    var fur: RGBA, stripe: RGBA, cream: RGBA, innerEar: RGBA, eye: RGBA, outline: RGBA
    var pattern: CoatPattern = .tabby
    /// Second patch colour (calico) or the dark points (Siamese).
    var accent = RGBA(r: 0, g: 0, b: 0)
    /// Mouth, whiskers and closed-eye lines; light on dark coats so they stay visible.
    var feature: RGBA?

    var line: RGBA { feature ?? outline }

    static func of(_ coat: CoatTheme) -> CoatPalette {
        switch coat {
        case .ginger:
            return CoatPalette(fur: PixelPalette.orangeRGBA, stripe: PixelPalette.stripeRGBA, cream: PixelPalette.creamRGBA,
                               innerEar: PixelPalette.pinkRGBA, eye: PixelPalette.outlineRGBA, outline: PixelPalette.outlineRGBA)
        case .smoky:
            return CoatPalette(fur: RGBA(r: 158, g: 164, b: 178), stripe: RGBA(r: 116, g: 122, b: 138),
                               cream: RGBA(r: 233, g: 234, b: 240), innerEar: PixelPalette.pinkRGBA,
                               eye: RGBA(r: 44, g: 46, b: 58), outline: RGBA(r: 44, g: 46, b: 58))
        case .midnight:
            return CoatPalette(fur: RGBA(r: 48, g: 46, b: 60), stripe: RGBA(r: 36, g: 34, b: 46),
                               cream: RGBA(r: 64, g: 62, b: 78), innerEar: RGBA(r: 196, g: 124, b: 146),
                               eye: RGBA(r: 247, g: 196, b: 62), outline: RGBA(r: 18, g: 16, b: 24), pattern: .solid,
                               feature: RGBA(r: 196, g: 190, b: 210))
        case .snow:
            return CoatPalette(fur: RGBA(r: 250, g: 249, b: 246), stripe: RGBA(r: 228, g: 226, b: 232),
                               cream: RGBA(r: 255, g: 255, b: 255), innerEar: PixelPalette.pinkRGBA,
                               eye: RGBA(r: 96, g: 164, b: 236), outline: RGBA(r: 92, g: 86, b: 104), pattern: .solid)
        case .tuxedo:
            return CoatPalette(fur: RGBA(r: 62, g: 60, b: 70), stripe: RGBA(r: 46, g: 44, b: 54),
                               cream: RGBA(r: 246, g: 244, b: 240), innerEar: RGBA(r: 214, g: 140, b: 158),
                               eye: RGBA(r: 150, g: 214, b: 92), outline: RGBA(r: 22, g: 20, b: 26), pattern: .tuxedo)
        case .calico:
            return CoatPalette(fur: RGBA(r: 252, g: 247, b: 238), stripe: RGBA(r: 240, g: 146, b: 64),
                               cream: RGBA(r: 255, g: 252, b: 246), innerEar: PixelPalette.pinkRGBA,
                               eye: RGBA(r: 214, g: 168, b: 52), outline: RGBA(r: 70, g: 52, b: 44), pattern: .calico,
                               accent: RGBA(r: 66, g: 60, b: 68))
        case .siamese:
            return CoatPalette(fur: RGBA(r: 244, g: 232, b: 214), stripe: RGBA(r: 226, g: 210, b: 186),
                               cream: RGBA(r: 252, g: 246, b: 236), innerEar: RGBA(r: 150, g: 112, b: 100),
                               eye: RGBA(r: 92, g: 170, b: 240), outline: RGBA(r: 74, g: 54, b: 44), pattern: .points,
                               accent: RGBA(r: 104, g: 78, b: 66))
        case .cocoa:
            return CoatPalette(fur: RGBA(r: 146, g: 100, b: 74), stripe: RGBA(r: 106, g: 70, b: 50),
                               cream: RGBA(r: 236, g: 210, b: 184), innerEar: RGBA(r: 236, g: 150, b: 160),
                               eye: RGBA(r: 136, g: 196, b: 96), outline: RGBA(r: 52, g: 32, b: 22))
        case .biscuit:
            return CoatPalette(fur: RGBA(r: 238, g: 210, b: 166), stripe: RGBA(r: 212, g: 176, b: 124),
                               cream: RGBA(r: 255, g: 247, b: 232), innerEar: PixelPalette.pinkRGBA,
                               eye: PixelPalette.outlineRGBA, outline: RGBA(r: 92, g: 62, b: 40))
        case .lilac:
            return CoatPalette(fur: RGBA(r: 198, g: 180, b: 234), stripe: RGBA(r: 168, g: 146, b: 214),
                               cream: RGBA(r: 242, g: 236, b: 252), innerEar: RGBA(r: 246, g: 168, b: 200),
                               eye: RGBA(r: 112, g: 84, b: 196), outline: RGBA(r: 70, g: 52, b: 104), pattern: .solid)
        case .mint:
            return CoatPalette(fur: RGBA(r: 164, g: 224, b: 204), stripe: RGBA(r: 116, g: 194, b: 170),
                               cream: RGBA(r: 236, g: 252, b: 246), innerEar: RGBA(r: 248, g: 170, b: 186),
                               eye: RGBA(r: 40, g: 92, b: 84), outline: RGBA(r: 36, g: 84, b: 76))
        case .bubblegum:
            return CoatPalette(fur: RGBA(r: 250, g: 182, b: 210), stripe: RGBA(r: 236, g: 138, b: 182),
                               cream: RGBA(r: 255, g: 238, b: 246), innerEar: RGBA(r: 255, g: 238, b: 246),
                               eye: RGBA(r: 92, g: 48, b: 104), outline: RGBA(r: 104, g: 40, b: 76))
        }
    }

    /// Iris colours for (left, right) eye.
    func irises(_ choice: EyeColor?) -> (RGBA, RGBA) {
        guard let choice else { return (eye, eye) }
        switch choice {
        case .dark: return (outline, outline)
        case .amber: return (RGBA(r: 240, g: 180, b: 50), RGBA(r: 240, g: 180, b: 50))
        case .green: return (RGBA(r: 130, g: 204, b: 84), RGBA(r: 130, g: 204, b: 84))
        case .blue: return (RGBA(r: 90, g: 162, b: 238), RGBA(r: 90, g: 162, b: 238))
        case .hazel: return (RGBA(r: 168, g: 140, b: 70), RGBA(r: 168, g: 140, b: 70))
        case .violet: return (RGBA(r: 150, g: 104, b: 226), RGBA(r: 150, g: 104, b: 226))
        case .oddEyed: return (RGBA(r: 90, g: 162, b: 238), RGBA(r: 240, g: 180, b: 50))
        }
    }
}

/// The cat, drawn with smooth vector shapes so it stays sharp at any size.
/// Coordinates are in "sprite units": a 24 × 23 canvas (the same footprint as the
/// original pixel art), so layout, hit-testing and props line up unchanged.
enum CatSprite {
    /// Units of headroom above the ears for hats and headphones.
    static let top = 4
    /// Canvas size in sprite units (body + tail + headroom).
    static let width = 24
    static let height = 19 + top

    // MARK: Shapes (canvas units, y down)

    static let head = Path(roundedRect: CGRect(x: 0.5, y: 6.1, width: 17, height: 10.6), cornerRadius: 5.2, style: .continuous)
    static let torso = Path(roundedRect: CGRect(x: 1.5, y: 12.4, width: 15, height: 10.1), cornerRadius: 4.8, style: .continuous)
    static let ears: [Path] = [
        poly([(0.9, 9.6), (1.6, 4.5), (7.0, 6.7)]),
        poly([(17.1, 9.6), (16.4, 4.5), (11.0, 6.7)]),
    ]
    static let innerEars: [Path] = [
        poly([(2.1, 8.2), (2.3, 5.9), (5.3, 7.0)]),
        poly([(15.9, 8.2), (15.7, 5.9), (12.7, 7.0)]),
    ]
    /// Head, ears and body as one shape (for clipping markings).
    static let silhouette: Path = silhouette(earDroop: 0)

    static func silhouette(earDroop: CGFloat) -> Path {
        var p = Path()
        p.addPath(head); p.addPath(torso)
        ears(droop: earDroop).forEach { p.addPath($0) }
        return p
    }

    /// Droopy "airplane" ears: the tips swing out sideways and down while the base
    /// stays on the head. Vertices are blended between the upright and drooped shapes.
    static func ears(droop: CGFloat) -> [Path] {
        guard droop > 0 else { return ears }
        let up: [(CGFloat, CGFloat)] = [(0.9, 9.6), (1.6, 4.5), (7.0, 6.7)]
        let down: [(CGFloat, CGFloat)] = [(1.6, 10.2), (0.15, 6.6), (6.6, 7.2)]
        return [poly(blend(up, down, droop)), poly(mirror(blend(up, down, droop)))]
    }

    static func innerEars(droop: CGFloat) -> [Path] {
        guard droop > 0 else { return innerEars }
        let up: [(CGFloat, CGFloat)] = [(2.1, 8.2), (2.3, 5.9), (5.3, 7.0)]
        let down: [(CGFloat, CGFloat)] = [(2.5, 9.0), (1.4, 7.1), (5.2, 7.6)]
        return [poly(blend(up, down, droop)), poly(mirror(blend(up, down, droop)))]
    }

    private static func blend(_ a: [(CGFloat, CGFloat)], _ b: [(CGFloat, CGFloat)], _ t: CGFloat) -> [(CGFloat, CGFloat)] {
        let k = min(1, max(0, t))
        return zip(a, b).map { (p, q) in (p.0 + (q.0 - p.0) * k, p.1 + (q.1 - p.1) * k) }
    }

    /// Mirror across the head's centre line (x = 9).
    private static func mirror(_ pts: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] { pts.map { (18 - $0.0, $0.1) } }
    static let paws = [ellipse(6.1, 22.0, 1.7, 0.95), ellipse(11.9, 22.0, 1.7, 0.95)]
    static let eyeCentres = [CGPoint(x: 5.0, y: 11.3), CGPoint(x: 13.0, y: 11.3)]

    /// Two tail positions, both rooted behind the right hip.
    static func tail(_ frame: Int) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 15.2, y: 20.8))
        if frame % 2 == 0 {
            p.addCurve(to: CGPoint(x: 21.9, y: 12.9), control1: CGPoint(x: 21.8, y: 21.6), control2: CGPoint(x: 23.4, y: 16.2))
        } else {
            p.addCurve(to: CGPoint(x: 20.4, y: 11.7), control1: CGPoint(x: 21.2, y: 21.6), control2: CGPoint(x: 19.2, y: 15.4))
        }
        return p
    }

    static func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
        p.closeSubpath()
        return p
    }

    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    static func stroke(_ pts: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
        return p
    }

    // MARK: Drawing

    /// Draws one pose into a context already scaled to sprite units.
    static func draw(_ pose: CatPose, in ctx: inout GraphicsContext) {
        let pal = CoatPalette.of(pose.coat)
        let outline = pal.outline.color
        let round = StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
        let tailColor = pal.pattern == .points ? pal.accent : pal.fur

        // Tail (behind the body).
        let tail = tail(pose.tailFrame)
        ctx.stroke(tail, with: .color(outline), style: StrokeStyle(lineWidth: 3.1, lineCap: .round))
        ctx.stroke(tail, with: .color(tailColor.color), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        switch pal.pattern {
        case .tabby:
            ctx.stroke(tail.trimmedPath(from: 0.3, to: 1), with: .color(pal.stripe.color),
                       style: StrokeStyle(lineWidth: 2.0, dash: [0.9, 1.5]))
        case .calico:
            ctx.stroke(tail.trimmedPath(from: 0.55, to: 1), with: .color(pal.stripe.color), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        default: break
        }

        // Outline: a thick stroke of every part, then the fills cover the inner half.
        let paws = paws.enumerated().map { i, paw in
            pose.pawStep == i + 1 ? paw.offsetBy(dx: 0, dy: -0.8) : paw
        }
        let parts = ears(droop: pose.earDroop) + [head, torso]
        for part in parts { ctx.stroke(part, with: .color(outline), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round)) }
        for paw in paws { ctx.stroke(paw, with: .color(outline), lineWidth: 1.0) }
        for part in parts { ctx.fill(part, with: .color(pal.fur.color)) }

        drawMarkings(pal, silhouette: pose.earDroop > 0 ? silhouette(earDroop: pose.earDroop) : silhouette, in: &ctx)

        let earColor = pal.pattern == .points ? pal.accent : pal.innerEar
        for ear in innerEars(droop: pose.earDroop) { ctx.fill(ear, with: .color(earColor.color)) }

        // Paws.
        let pawColor: RGBA = switch pal.pattern {
        case .tuxedo, .calico: pal.cream
        case .points: pal.accent
        case .solid: pal.fur
        case .tabby: pal.cream
        }
        for paw in paws { ctx.fill(paw, with: .color(pawColor.color)) }
        for (i, x) in ([6.1, 11.9] as [CGFloat]).enumerated() {
            let y: CGFloat = pose.pawStep == i + 1 ? -0.8 : 0
            ctx.stroke(stroke([(x - 0.55, 21.6 + y), (x - 0.55, 22.4 + y)]), with: .color(outline.opacity(0.35)), style: round.with(width: 0.3))
            ctx.stroke(stroke([(x + 0.55, 21.6 + y), (x + 0.55, 22.4 + y)]), with: .color(outline.opacity(0.35)), style: round.with(width: 0.3))
        }

        if pose.headband { drawHeadband(in: &ctx) }

        // Cheeks.
        if pose.blush {
            let blush = PixelPalette.blushRGBA.color.opacity(0.75)
            ctx.fill(ellipse(3.0, 13.4, 1.25, 0.72), with: .color(blush))
            ctx.fill(ellipse(15.0, 13.4, 1.25, 0.72), with: .color(blush))
        }

        // Whiskers.
        let whisker = pal.line.color.opacity(0.5)
        for (dy, end) in [(-0.35, -0.6), (0.35, 0.5)] as [(CGFloat, CGFloat)] {
            ctx.stroke(stroke([(3.0, 13.5 + dy), (0.6, 13.5 + dy + end)]), with: .color(whisker), style: round.with(width: 0.22))
            ctx.stroke(stroke([(15.0, 13.5 + dy), (17.4, 13.5 + dy + end)]), with: .color(whisker), style: round.with(width: 0.22))
        }

        drawEyes(pose, pal, in: &ctx)
        drawFace(pose, pal, in: &ctx)

        if let a = pose.accessory { drawAccessory(a, in: &ctx) }
    }

    private static func drawMarkings(_ pal: CoatPalette, silhouette: Path, in ctx: inout GraphicsContext) {
        var m = ctx
        m.clip(to: silhouette)
        let muzzle = ellipse(9, 14.0, 3.5, 2.1)
        let belly = ellipse(9, 19.3, 3.7, 4.4)
        let round = StrokeStyle(lineWidth: 0.75, lineCap: .round)

        switch pal.pattern {
        case .tabby:
            m.fill(belly, with: .color(pal.cream.color))
            m.fill(muzzle, with: .color(pal.cream.color))
            let s = GraphicsContext.Shading.color(pal.stripe.color)
            // Forehead "M", cheek and flank stripes.
            for (x, h) in [(7.4, 1.5), (9.0, 1.9), (10.6, 1.5)] as [(CGFloat, CGFloat)] {
                m.stroke(stroke([(x, 6.5), (x, 6.5 + h)]), with: s, style: round)
            }
            for y in [10.4, 11.9] as [CGFloat] {
                m.stroke(stroke([(0.3, y), (2.0, y + 0.3)]), with: s, style: round)
                m.stroke(stroke([(17.7, y), (16.0, y + 0.3)]), with: s, style: round)
            }
            for y in [16.4, 18.6, 20.6] as [CGFloat] {
                m.stroke(stroke([(1.2, y), (3.4, y - 0.5)]), with: s, style: round.with(width: 0.85))
                m.stroke(stroke([(16.8, y), (14.6, y - 0.5)]), with: s, style: round.with(width: 0.85))
            }
        case .solid:
            m.fill(ellipse(9, 19.6, 3.2, 3.8), with: .color(pal.cream.color.opacity(0.6)))
        case .tuxedo:
            m.fill(ellipse(9, 19.0, 4.4, 5.2), with: .color(pal.cream.color))
            m.fill(ellipse(9, 14.3, 3.4, 2.4), with: .color(pal.cream.color))
            m.fill(poly([(7.6, 12.4), (10.4, 12.4), (9, 9.4)]), with: .color(pal.cream.color))
        case .calico:
            m.fill(ellipse(2.6, 7.6, 4.2, 3.2), with: .color(pal.stripe.color))
            m.fill(ellipse(16.4, 9.6, 3.0, 2.6), with: .color(pal.accent.color))
            m.fill(ellipse(15.8, 18.4, 3.0, 3.8), with: .color(pal.stripe.color))
            m.fill(ellipse(2.4, 19.6, 2.4, 2.8), with: .color(pal.accent.color))
            m.fill(ellipse(13.8, 21.2, 1.6, 1.2), with: .color(pal.accent.color))
        case .points:
            // Darker mask around the nose, fading out across the face.
            m.fill(ellipse(9, 13.5, 3.6, 2.4),
                   with: .radialGradient(Gradient(colors: [pal.accent.color.opacity(0.85), pal.accent.color.opacity(0)]),
                                         center: CGPoint(x: 9, y: 13.2), startRadius: 0.4, endRadius: 3.4))
            m.fill(belly, with: .color(pal.cream.color.opacity(0.7)))
        }
    }

    private static func drawEyes(_ pose: CatPose, _ pal: CoatPalette, in ctx: inout GraphicsContext) {
        let line = pal.line.color
        let style = StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round)
        let (left, right) = pal.irises(pose.eyeColor)
        for (i, c) in eyeCentres.enumerated() {
            let iris = (i == 0 ? left : right).color
            switch pose.eyes {
            case .open, .lookUp, .sleepy:
                let lift: CGFloat = pose.eyes == .lookUp ? -0.45 : 0
                let eye = ellipse(c.x, c.y, 1.2, 1.4)
                ctx.fill(eye, with: .color(pal.outline.color))
                ctx.fill(ellipse(c.x, c.y + lift * 0.4, 1.0, 1.2), with: .color(iris))
                ctx.fill(ellipse(c.x, c.y + lift, 0.5, 0.85), with: .color(pal.outline.color))
                ctx.fill(ellipse(c.x + 0.38, c.y - 0.55 + lift, 0.38, 0.38), with: .color(.white))
                ctx.fill(ellipse(c.x - 0.4, c.y + 0.55 + lift, 0.16, 0.16), with: .color(.white.opacity(0.8)))
                if pose.eyes == .sleepy {
                    var lid = ctx
                    lid.clip(to: eye)
                    lid.fill(Path(CGRect(x: c.x - 1.4, y: c.y - 1.6, width: 2.8, height: 1.6)), with: .color(pal.fur.color))
                    ctx.stroke(stroke([(c.x - 1.3, c.y), (c.x + 1.3, c.y)]), with: .color(pal.outline.color), style: style)
                }
            case .blink:
                var p = Path()
                p.move(to: CGPoint(x: c.x - 1.2, y: c.y + 0.2))
                p.addQuadCurve(to: CGPoint(x: c.x + 1.2, y: c.y + 0.2), control: CGPoint(x: c.x, y: c.y + 0.7))
                ctx.stroke(p, with: .color(line), style: style)
            case .happy:
                var p = Path()
                p.move(to: CGPoint(x: c.x - 1.2, y: c.y + 0.6))
                p.addQuadCurve(to: CGPoint(x: c.x + 1.2, y: c.y + 0.6), control: CGPoint(x: c.x, y: c.y - 1.1))
                ctx.stroke(p, with: .color(line), style: style)
            case .closed:
                var p = Path()
                p.move(to: CGPoint(x: c.x - 1.2, y: c.y))
                p.addQuadCurve(to: CGPoint(x: c.x + 1.2, y: c.y), control: CGPoint(x: c.x, y: c.y + 1.3))
                ctx.stroke(p, with: .color(line), style: style)
            }
        }
    }

    private static func drawFace(_ pose: CatPose, _ pal: CoatPalette, in ctx: inout GraphicsContext) {
        let line = pal.line.color
        let style = StrokeStyle(lineWidth: 0.42, lineCap: .round, lineJoin: .round)
        if pose.sad {
            // Worried brows: inner ends raised.
            let brow = StrokeStyle(lineWidth: 0.45, lineCap: .round)
            ctx.stroke(stroke([(3.7, 9.55), (6.1, 8.85)]), with: .color(line), style: brow)
            ctx.stroke(stroke([(14.3, 9.55), (11.9, 8.85)]), with: .color(line), style: brow)
        }
        if pose.sad && !pose.mouthOpen {
            // A small frown.
            var mouth = Path()
            mouth.move(to: CGPoint(x: 9, y: 13.2))
            mouth.addLine(to: CGPoint(x: 9, y: 13.65))
            mouth.move(to: CGPoint(x: 7.9, y: 14.45))
            mouth.addQuadCurve(to: CGPoint(x: 10.1, y: 14.45), control: CGPoint(x: 9, y: 13.35))
            ctx.stroke(mouth, with: .color(line), style: style)
        } else if pose.mouthOpen {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 8.0, y: 13.75))
            mouth.addQuadCurve(to: CGPoint(x: 10.0, y: 13.75), control: CGPoint(x: 9, y: 13.6))
            mouth.addQuadCurve(to: CGPoint(x: 8.0, y: 13.75), control: CGPoint(x: 9, y: 16.0))
            ctx.fill(mouth, with: .color(RGBA(r: 150, g: 50, b: 64).color))
            var tongue = ctx
            tongue.clip(to: mouth)
            tongue.fill(ellipse(9, 15.1, 0.75, 0.55), with: .color(PixelPalette.pinkRGBA.color))
            ctx.stroke(mouth, with: .color(line), style: style)
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 9, y: 13.2))
            mouth.addLine(to: CGPoint(x: 9, y: 13.7))
            mouth.addQuadCurve(to: CGPoint(x: 7.8, y: 13.75), control: CGPoint(x: 8.4, y: 14.35))
            mouth.move(to: CGPoint(x: 9, y: 13.7))
            mouth.addQuadCurve(to: CGPoint(x: 10.2, y: 13.75), control: CGPoint(x: 9.6, y: 14.35))
            ctx.stroke(mouth, with: .color(line), style: style)
        }
        // Nose: a soft rounded triangle.
        var nose = Path()
        nose.move(to: CGPoint(x: 8.3, y: 12.55))
        nose.addQuadCurve(to: CGPoint(x: 9.7, y: 12.55), control: CGPoint(x: 9, y: 12.3))
        nose.addQuadCurve(to: CGPoint(x: 8.3, y: 12.55), control: CGPoint(x: 9, y: 13.7))
        ctx.fill(nose, with: .color(PixelPalette.pinkRGBA.color))
        ctx.stroke(nose, with: .color(pal.outline.color.opacity(0.6)), lineWidth: 0.2)
    }

    private static func drawHeadband(in ctx: inout GraphicsContext) {
        let red = RGBA(r: 237, g: 69, b: 92).color
        var band = ctx
        band.clip(to: head)
        band.fill(Path(CGRect(x: 0, y: 7.6, width: 18, height: 1.3)), with: .color(red))
        band.fill(Path(CGRect(x: 0, y: 7.85, width: 18, height: 0.25)), with: .color(.white.opacity(0.5)))
        let knot = StrokeStyle(lineWidth: 0.9, lineCap: .round)
        ctx.stroke(stroke([(16.9, 8.2), (19.0, 7.2)]), with: .color(red), style: knot)
        ctx.stroke(stroke([(16.9, 8.4), (18.8, 9.6)]), with: .color(red), style: knot)
        ctx.fill(ellipse(16.9, 8.25, 0.6, 0.6), with: .color(red))
    }

    // MARK: Accessories

    private static func drawAccessory(_ a: Accessory, in ctx: inout GraphicsContext) {
        let ink = PixelPalette.outlineRGBA.color
        let red = RGBA(r: 237, g: 69, b: 92).color
        let gold = RGBA(r: 250, g: 204, b: 64).color
        let darkGold = RGBA(r: 196, g: 140, b: 30).color
        func outlined(_ p: Path, _ fill: Color, _ w: CGFloat = 0.4) {
            ctx.fill(p, with: .color(fill))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w, lineJoin: .round))
        }

        switch a {
        case .bow:
            outlined(poly([(13.6, 6.0), (11.2, 4.6), (11.2, 7.4)]), red)
            outlined(poly([(13.6, 6.0), (16.0, 4.6), (16.0, 7.4)]), red)
            outlined(ellipse(13.6, 6.0, 0.75, 0.75), RGBA(r: 210, g: 48, b: 74).color)

        case .flower:
            let petal = RGBA(r: 255, g: 170, b: 200).color
            for i in 0..<5 {
                let a = Double(i) / 5 * 2 * .pi - .pi / 2
                outlined(ellipse(14.0 + cos(a) * 0.95, 6.0 + sin(a) * 0.95, 0.8, 0.8), petal, 0.3)
            }
            outlined(ellipse(14.0, 6.0, 0.6, 0.6), gold, 0.3)

        case .glasses:
            for c in eyeCentres {
                let lens = ellipse(c.x, c.y, 1.95, 1.95)
                ctx.fill(lens, with: .color(.white.opacity(0.18)))
                ctx.stroke(lens, with: .color(ink), lineWidth: 0.5)
            }
            ctx.stroke(stroke([(6.95, 11.0), (11.05, 11.0)]), with: .color(ink), lineWidth: 0.45)

        case .sunglasses:
            for c in eyeCentres {
                let lens = Path(roundedRect: CGRect(x: c.x - 2.0, y: c.y - 1.4, width: 4.0, height: 2.8), cornerRadius: 1.1)
                outlined(lens, RGBA(r: 30, g: 30, b: 40).color, 0.45)
                ctx.stroke(stroke([(c.x - 1.1, c.y + 0.7), (c.x + 0.3, c.y - 0.8)]), with: .color(.white.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 0.35, lineCap: .round))
            }
            ctx.stroke(stroke([(7.0, 10.6), (11.0, 10.6)]), with: .color(ink), lineWidth: 0.5)

        case .scarf:
            var band = Path(roundedRect: CGRect(x: 1.7, y: 15.4, width: 14.6, height: 1.9), cornerRadius: 0.9)
            band.addPath(Path(roundedRect: CGRect(x: 10.8, y: 16.5, width: 2.0, height: 4.0), cornerRadius: 0.5)
                .applying(CGAffineTransform(rotationAngle: 0.12).concatenating(.init(translationX: 2.0, y: -1.4))))
            outlined(band, red)
            var stripes = ctx
            stripes.clip(to: band)
            for x in stride(from: 2.6, to: 17, by: 2.2) {
                stripes.fill(Path(CGRect(x: x, y: 15, width: 0.7, height: 7)), with: .color(.white.opacity(0.85)))
            }

        case .bellCollar:
            let band = Path(roundedRect: CGRect(x: 2.4, y: 15.7, width: 13.2, height: 1.1), cornerRadius: 0.55)
            outlined(band, RGBA(r: 64, g: 140, b: 220).color, 0.35)
            outlined(ellipse(9, 17.5, 1.05, 1.05), gold, 0.35)
            ctx.stroke(stroke([(8.4, 17.8), (9.6, 17.8)]), with: .color(darkGold), lineWidth: 0.3)
            ctx.fill(ellipse(8.65, 17.15, 0.25, 0.25), with: .color(.white.opacity(0.8)))

        case .partyHat:
            let cone = poly([(6.4, 6.8), (11.6, 6.8), (9.0, 0.9)])
            outlined(cone, RGBA(r: 140, g: 107, b: 219).color)
            var dots = ctx
            dots.clip(to: cone)
            for (x, y) in [(8.2, 5.6), (10.0, 4.4), (8.9, 3.0), (10.5, 6.2)] as [(CGFloat, CGFloat)] {
                dots.fill(ellipse(x, y, 0.42, 0.42), with: .color(RGBA(r: 255, g: 226, b: 110).color))
            }
            outlined(ellipse(9, 0.9, 0.85, 0.85), .white, 0.35)

        case .headphones:
            var band = Path()
            band.move(to: CGPoint(x: 1.2, y: 10.4))
            band.addCurve(to: CGPoint(x: 16.8, y: 10.4), control1: CGPoint(x: 0.6, y: 0.4), control2: CGPoint(x: 17.4, y: 0.4))
            ctx.stroke(band, with: .color(ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            ctx.stroke(band, with: .color(RGBA(r: 90, g: 92, b: 110).color), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
            let blue = RGBA(r: 115, g: 184, b: 230).color
            outlined(Path(roundedRect: CGRect(x: 0.0, y: 9.0, width: 2.4, height: 4.2), cornerRadius: 1.0), blue, 0.45)
            outlined(Path(roundedRect: CGRect(x: 15.6, y: 9.0, width: 2.4, height: 4.2), cornerRadius: 1.0), blue, 0.45)

        case .beanie:
            var cap = Path()
            cap.move(to: CGPoint(x: 1.4, y: 8.4))
            cap.addCurve(to: CGPoint(x: 16.6, y: 8.4), control1: CGPoint(x: 1.2, y: 1.6), control2: CGPoint(x: 16.8, y: 1.6))
            cap.closeSubpath()
            let teal = RGBA(r: 64, g: 176, b: 170).color
            outlined(cap, teal)
            var ribs = ctx
            ribs.clip(to: cap)
            for x in stride(from: 3.0, to: 16, by: 1.6) {
                ribs.stroke(stroke([(x, 3), (x, 8)]), with: .color(.black.opacity(0.12)), lineWidth: 0.35)
            }
            outlined(Path(roundedRect: CGRect(x: 1.0, y: 7.3, width: 16, height: 1.8), cornerRadius: 0.9),
                     RGBA(r: 44, g: 140, b: 136).color)
            outlined(ellipse(9, 3.0, 1.3, 1.3), RGBA(r: 255, g: 236, b: 200).color, 0.35)

        case .crown:
            let crown = poly([(5.6, 6.6), (5.6, 3.0), (7.3, 4.6), (9.0, 2.2), (10.7, 4.6), (12.4, 3.0), (12.4, 6.6)])
            outlined(crown, gold)
            ctx.fill(Path(CGRect(x: 5.8, y: 5.6, width: 6.4, height: 0.8)), with: .color(darkGold))
            outlined(ellipse(9, 4.8, 0.55, 0.55), red, 0.25)
            for (x, y) in [(5.6, 3.0), (9.0, 2.2), (12.4, 3.0)] as [(CGFloat, CGFloat)] {
                outlined(ellipse(x, y, 0.4, 0.4), gold, 0.25)
            }

        case .wizardHat:
            let navy = RGBA(r: 60, g: 66, b: 160).color
            var cone = Path()
            cone.move(to: CGPoint(x: 5.2, y: 6.3))
            cone.addQuadCurve(to: CGPoint(x: 11.4, y: 0.2), control: CGPoint(x: 8.0, y: 1.0))
            cone.addQuadCurve(to: CGPoint(x: 12.8, y: 6.3), control: CGPoint(x: 11.0, y: 2.6))
            cone.closeSubpath()
            outlined(cone, navy)
            outlined(ellipse(9, 6.5, 6.6, 1.05), navy)
            for (x, y, r) in [(8.6, 4.4, 0.55), (10.8, 2.6, 0.4)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.fill(star(x, y, r), with: .color(gold))
            }
        }
    }

    private static func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        var p = Path()
        for i in 0..<10 {
            let a = Double(i) / 10 * 2 * .pi - .pi / 2
            let rr = i % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: cx + cos(a) * rr, y: cy + sin(a) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

private extension StrokeStyle {
    func with(width: CGFloat) -> StrokeStyle {
        var s = self
        s.lineWidth = width
        return s
    }
}

/// A SwiftUI view that shows a single cat frame. `pixel` is points per sprite unit.
struct CatCanvas: View {
    var pose: CatPose
    var pixel: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: pixel, y: pixel)
            CatSprite.draw(pose, in: &ctx)
        }
        .frame(width: CGFloat(CatSprite.width) * pixel, height: CGFloat(CatSprite.height) * pixel)
        .accessibilityHidden(true)
    }
}
