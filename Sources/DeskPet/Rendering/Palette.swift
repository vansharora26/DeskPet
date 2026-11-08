import CoreGraphics
import SwiftUI

/// An 8-bit RGBA colour, usable both for bitmap rasterisation and SwiftUI.
struct RGBA: Hashable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

enum PixelPalette {
    static let outlineRGBA = RGBA(r: 59, g: 36, b: 23)
    static let orangeRGBA = RGBA(r: 245, g: 148, b: 61)
    static let stripeRGBA = RGBA(r: 214, g: 105, b: 33)
    static let creamRGBA = RGBA(r: 255, g: 227, b: 189)
    static let pinkRGBA = RGBA(r: 247, g: 153, b: 173)
    static let blushRGBA = RGBA(r: 255, g: 140, b: 140)
    static let whiteRGBA = RGBA(r: 255, g: 255, b: 255)

    static let outline = outlineRGBA.color
    static let orange = orangeRGBA.color
    static let stripe = stripeRGBA.color

    static func standard(_ ch: Character) -> RGBA? {
        switch ch {
        case "K": return outlineRGBA
        case "O": return orangeRGBA
        case "D": return stripeRGBA
        case "L": return creamRGBA
        case "P": return pinkRGBA
        case "W": return whiteRGBA
        case "R": return RGBA(r: 237, g: 69, b: 92)       // heart red
        case "B": return RGBA(r: 115, g: 184, b: 230)     // fish blue
        case "Y": return RGBA(r: 140, g: 107, b: 219)     // yarn
        case "y": return RGBA(r: 189, g: 163, b: 250)     // yarn highlight
        default: return nil
        }
    }
}

/// Smooth vector versions of the reaction props. Each keeps its pixel sprite's
/// footprint (in sprite units) so existing offsets still line up.
struct PropView: View {
    enum Kind { case heart, fish, yarn, droplet, mug }
    var kind: Kind
    /// Points per sprite unit.
    var unit: CGFloat

    private var size: CGSize {
        switch kind {
        case .heart: return CGSize(width: 7, height: 6)
        case .fish: return CGSize(width: 9, height: 5)
        case .yarn: return CGSize(width: 6, height: 5)
        case .droplet: return CGSize(width: 5, height: 5)
        case .mug: return CGSize(width: 7, height: 7)
        }
    }

    var body: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: unit, y: unit)
            Self.draw(kind, in: &ctx)
        }
        .frame(width: size.width * unit, height: size.height * unit)
        .accessibilityHidden(true)
    }

    private static func draw(_ kind: Kind, in ctx: inout GraphicsContext) {
        let ink = PixelPalette.outline
        func outlined(_ p: Path, _ fill: Color, _ w: CGFloat = 0.5) {
            ctx.fill(p, with: .color(fill))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w, lineJoin: .round))
        }
        switch kind {
        case .heart:
            var p = Path()
            p.move(to: CGPoint(x: 3.5, y: 5.6))
            p.addCurve(to: CGPoint(x: 3.5, y: 1.4), control1: CGPoint(x: -0.6, y: 2.8), control2: CGPoint(x: 1.6, y: -0.6))
            p.addCurve(to: CGPoint(x: 3.5, y: 5.6), control1: CGPoint(x: 5.4, y: -0.6), control2: CGPoint(x: 7.6, y: 2.8))
            outlined(p, PixelPalette.standard("R")!.color, 0.45)
            ctx.fill(Path(ellipseIn: CGRect(x: 1.4, y: 1.4, width: 1.1, height: 0.9)), with: .color(.white.opacity(0.75)))
        case .fish:
            var body = Path(ellipseIn: CGRect(x: 0.3, y: 0.6, width: 6.4, height: 3.8))
            body.addPath(Path { t in
                t.move(to: CGPoint(x: 6.0, y: 2.5)); t.addLine(to: CGPoint(x: 8.7, y: 0.6))
                t.addLine(to: CGPoint(x: 8.7, y: 4.4)); t.closeSubpath()
            })
            outlined(body, PixelPalette.standard("B")!.color)
            ctx.fill(Path(ellipseIn: CGRect(x: 1.4, y: 1.7, width: 0.9, height: 0.9)), with: .color(ink))
        case .yarn:
            let ball = Path(ellipseIn: CGRect(x: 0.6, y: 0.1, width: 4.8, height: 4.8))
            outlined(ball, PixelPalette.standard("Y")!.color)
            var lines = ctx
            lines.clip(to: ball)
            for i in 0..<3 {
                var arc = Path()
                arc.move(to: CGPoint(x: 0.4, y: 1.2 + Double(i) * 1.3))
                arc.addQuadCurve(to: CGPoint(x: 5.6, y: 2.0 + Double(i) * 1.3), control: CGPoint(x: 3, y: 0.4 + Double(i) * 1.3))
                lines.stroke(arc, with: .color(PixelPalette.standard("y")!.color), lineWidth: 0.45)
            }
        case .droplet:
            var p = Path()
            p.move(to: CGPoint(x: 2.5, y: 0.2))
            p.addCurve(to: CGPoint(x: 2.5, y: 4.8), control1: CGPoint(x: 1.6, y: 1.6), control2: CGPoint(x: 0.4, y: 4.8))
            p.addCurve(to: CGPoint(x: 2.5, y: 0.2), control1: CGPoint(x: 4.6, y: 4.8), control2: CGPoint(x: 3.4, y: 1.6))
            outlined(p, PixelPalette.standard("B")!.color, 0.4)
            ctx.fill(Path(ellipseIn: CGRect(x: 1.6, y: 2.6, width: 0.7, height: 1.1)), with: .color(.white.opacity(0.8)))
        case .mug:
            let steam = StrokeStyle(lineWidth: 0.45, lineCap: .round)
            for x in [2.0, 3.6] as [CGFloat] {
                var s = Path()
                s.move(to: CGPoint(x: x, y: 2.0))
                s.addQuadCurve(to: CGPoint(x: x, y: 0.2), control: CGPoint(x: x + 1.0, y: 1.1))
                ctx.stroke(s, with: .color(.white.opacity(0.9)), style: steam)
            }
            var handle = Path()
            handle.addArc(center: CGPoint(x: 5.2, y: 4.4), radius: 1.0, startAngle: .degrees(-80), endAngle: .degrees(80), clockwise: false)
            ctx.stroke(handle, with: .color(ink), lineWidth: 0.9)
            outlined(Path(roundedRect: CGRect(x: 0.4, y: 2.6, width: 4.8, height: 4.0), cornerRadius: 0.9),
                     PixelPalette.standard("R")!.color)
            ctx.fill(Path(CGRect(x: 0.9, y: 3.3, width: 3.8, height: 0.5)), with: .color(.white.opacity(0.6)))
        }
    }
}
