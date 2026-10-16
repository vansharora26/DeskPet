import DeskPetCore
import SwiftUI

/// Deterministic pseudo-random numbers so scenes are identical every frame
/// (static layers never need redrawing).
struct SceneRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

/// The illustrated environment behind a world. Static shapes are drawn with
/// Canvas; only a sparse particle layer animates, at a low frame rate, and it
/// stops completely for "Still" motion, Reduce Motion, or a hidden window.
struct WorldScene: View {
    let world: FocusWorld
    let style: SceneryStyle
    let motion: MotionLevel
    var active = true
    /// Show rain streaks (Deep Focus with rain ambience).
    var raining = false

    var body: some View {
        let theme = WorldTheme.of(world)
        ZStack {
            LinearGradient(colors: theme.gradient, startPoint: .top, endPoint: .bottom)
            if style == .illustrated {
                Canvas { ctx, size in Self.drawStatic(world, in: &ctx, size: size) }
                if motion != .still && active {
                    ParticleLayer(world: world, density: motion == .full ? 1 : 0.55, raining: raining)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: Static layers

    static func drawStatic(_ world: FocusWorld, in ctx: inout GraphicsContext, size: CGSize) {
        switch world {
        case .deepFocus: nightForest(&ctx, size)
        case .study: studyRoom(&ctx, size)
        case .workSprint: sprintGrid(&ctx, size)
        case .recharge: garden(&ctx, size)
        case .planning: morningDesk(&ctx, size)
        }
    }

    private static func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(red: r, green: g, blue: b).opacity(a)
    }

    private static func glow(_ ctx: inout GraphicsContext, at p: CGPoint, radius: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                 with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: p, startRadius: 0, endRadius: radius))
    }

    /// Stacked-triangle pine tree.
    private static func pine(_ ctx: inout GraphicsContext, x: CGFloat, base: CGFloat, height: CGFloat, color: Color) {
        let w = height * 0.42
        var p = Path()
        for tier in 0..<3 {
            let top = base - height + CGFloat(tier) * height * 0.22
            let bottom = base - height * (0.45 - CGFloat(tier) * 0.2)
            let half = w * (0.55 + CGFloat(tier) * 0.25) / 2
            p.move(to: CGPoint(x: x, y: top))
            p.addLine(to: CGPoint(x: x - half, y: bottom))
            p.addLine(to: CGPoint(x: x + half, y: bottom))
            p.closeSubpath()
        }
        p.addRect(CGRect(x: x - w * 0.05, y: base - height * 0.1, width: w * 0.1, height: height * 0.1))
        ctx.fill(p, with: .color(color))
    }

    private static func nightForest(_ ctx: inout GraphicsContext, _ s: CGSize) {
        var r = SceneRandom(7)
        // Stars
        for _ in 0..<90 {
            let p = CGPoint(x: r.next() * s.width, y: r.next() * s.height * 0.55)
            let d = 0.6 + r.next() * 1.4
            ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: d, height: d)), with: .color(.white.opacity(0.25 + r.next() * 0.5)))
        }
        // Moon
        let m = CGPoint(x: s.width * 0.8, y: s.height * 0.17)
        let mr = min(s.width, s.height) * 0.035
        glow(&ctx, at: m, radius: mr * 6, color: c(0.75, 0.82, 0.95, 0.18))
        ctx.fill(Path(ellipseIn: CGRect(x: m.x - mr, y: m.y - mr, width: mr * 2, height: mr * 2)), with: .color(c(0.95, 0.94, 0.88)))
        // Distant hills
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: s.height * 0.62))
        for i in 0...24 {
            let x = s.width * CGFloat(i) / 24
            hills.addLine(to: CGPoint(x: x, y: s.height * (0.6 + 0.04 * sin(Double(i) * 0.9) + 0.02 * cos(Double(i) * 2.3))))
        }
        hills.addLine(to: CGPoint(x: s.width, y: s.height)); hills.addLine(to: CGPoint(x: 0, y: s.height)); hills.closeSubpath()
        ctx.fill(hills, with: .color(c(0.09, 0.14, 0.21)))
        // Three depths of pines
        let layers: [(Double, Double, Color, Int)] = [(0.72, 0.16, c(0.07, 0.12, 0.17), 26), (0.82, 0.24, c(0.05, 0.09, 0.12), 16),
                                                       (0.95, 0.36, c(0.03, 0.05, 0.07), 9)]
        for (baseFrac, hFrac, color, count) in layers {
            for i in 0..<count {
                let x = s.width * (CGFloat(i) + CGFloat(r.next()) * 0.8) / CGFloat(count)
                pine(&ctx, x: x, base: s.height * baseFrac, height: s.height * hFrac * (0.7 + r.next() * 0.5), color: color)
            }
        }
        // Cabin with a warm window
        let cabin = CGRect(x: s.width * 0.76, y: s.height * 0.79, width: s.width * 0.09, height: s.height * 0.08)
        var roof = Path()
        roof.move(to: CGPoint(x: cabin.minX - cabin.width * 0.1, y: cabin.minY))
        roof.addLine(to: CGPoint(x: cabin.midX, y: cabin.minY - cabin.height * 0.55))
        roof.addLine(to: CGPoint(x: cabin.maxX + cabin.width * 0.1, y: cabin.minY))
        roof.closeSubpath()
        ctx.fill(roof, with: .color(c(0.04, 0.05, 0.06)))
        ctx.fill(Path(cabin), with: .color(c(0.06, 0.07, 0.08)))
        let win = CGRect(x: cabin.minX + cabin.width * 0.2, y: cabin.minY + cabin.height * 0.25, width: cabin.width * 0.22, height: cabin.height * 0.32)
        glow(&ctx, at: CGPoint(x: win.midX, y: win.midY), radius: cabin.width * 0.9, color: c(0.98, 0.72, 0.35, 0.22))
        ctx.fill(Path(win), with: .color(c(0.99, 0.8, 0.45)))
        // Ground
        ctx.fill(Path(CGRect(x: 0, y: s.height * 0.94, width: s.width, height: s.height * 0.06)), with: .color(c(0.02, 0.03, 0.04)))
    }

    private static func studyRoom(_ ctx: inout GraphicsContext, _ s: CGSize) {
        var r = SceneRandom(11)
        // Window (evening sky) on the left
        let win = CGRect(x: s.width * 0.07, y: s.height * 0.12, width: s.width * 0.26, height: s.height * 0.38)
        ctx.fill(Path(roundedRect: win, cornerRadius: 6),
                 with: .linearGradient(Gradient(colors: [c(0.2, 0.25, 0.45), c(0.62, 0.42, 0.45)]),
                                       startPoint: CGPoint(x: win.midX, y: win.minY), endPoint: CGPoint(x: win.midX, y: win.maxY)))
        for _ in 0..<14 {
            let p = CGPoint(x: win.minX + r.next() * win.width, y: win.minY + r.next() * win.height * 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.4, height: 1.4)), with: .color(.white.opacity(0.6)))
        }
        ctx.stroke(Path(roundedRect: win, cornerRadius: 6), with: .color(c(0.5, 0.33, 0.22)), lineWidth: 10)
        var mullion = Path()
        mullion.move(to: CGPoint(x: win.midX, y: win.minY)); mullion.addLine(to: CGPoint(x: win.midX, y: win.maxY))
        mullion.move(to: CGPoint(x: win.minX, y: win.midY)); mullion.addLine(to: CGPoint(x: win.maxX, y: win.midY))
        ctx.stroke(mullion, with: .color(c(0.5, 0.33, 0.22)), lineWidth: 5)
        // Bookshelf on the right
        let shelf = CGRect(x: s.width * 0.7, y: s.height * 0.08, width: s.width * 0.26, height: s.height * 0.56)
        ctx.fill(Path(shelf), with: .color(c(0.27, 0.17, 0.12)))
        let books = [c(0.62, 0.3, 0.25), c(0.3, 0.42, 0.38), c(0.75, 0.6, 0.35), c(0.35, 0.33, 0.5), c(0.55, 0.45, 0.4), c(0.8, 0.72, 0.6)]
        for row in 0..<4 {
            let y = shelf.minY + shelf.height * (CGFloat(row) + 1) / 4
            ctx.fill(Path(CGRect(x: shelf.minX, y: y - 6, width: shelf.width, height: 6)), with: .color(c(0.42, 0.27, 0.18)))
            var x = shelf.minX + 8
            while x < shelf.maxX - 14 {
                let w = 8 + r.next() * 12
                let h = shelf.height / 4 * (0.55 + r.next() * 0.35)
                ctx.fill(Path(CGRect(x: x, y: y - 6 - h, width: w, height: h)), with: .color(books[Int(r.next() * 6) % 6]))
                x += w + 1.5
            }
        }
        // Lamp glow, desk, lamp, mug
        let lamp = CGPoint(x: s.width * 0.52, y: s.height * 0.6)
        glow(&ctx, at: lamp, radius: s.width * 0.3, color: c(0.99, 0.78, 0.45, 0.28))
        let desk = CGRect(x: 0, y: s.height * 0.74, width: s.width, height: s.height * 0.26)
        ctx.fill(Path(desk), with: .linearGradient(Gradient(colors: [c(0.5, 0.33, 0.21), c(0.32, 0.2, 0.13)]),
                                                   startPoint: CGPoint(x: 0, y: desk.minY), endPoint: CGPoint(x: 0, y: desk.maxY)))
        ctx.fill(Path(CGRect(x: 0, y: desk.minY, width: s.width, height: 4)), with: .color(c(0.66, 0.46, 0.3)))
        let u = s.width / 1280   // scale props with the scene (previews are small)
        var shade = Path()
        shade.move(to: CGPoint(x: lamp.x - 40 * u, y: lamp.y + 10 * u))
        shade.addLine(to: CGPoint(x: lamp.x - 18 * u, y: lamp.y - 30 * u))
        shade.addLine(to: CGPoint(x: lamp.x + 18 * u, y: lamp.y - 30 * u))
        shade.addLine(to: CGPoint(x: lamp.x + 40 * u, y: lamp.y + 10 * u))
        shade.closeSubpath()
        ctx.fill(shade, with: .color(c(0.86, 0.55, 0.3)))
        ctx.fill(Path(CGRect(x: lamp.x - 3 * u, y: lamp.y + 10 * u, width: 6 * u, height: desk.minY - lamp.y - 10 * u)), with: .color(c(0.3, 0.22, 0.16)))
        ctx.fill(Path(roundedRect: CGRect(x: lamp.x - 26 * u, y: desk.minY - 6 * u, width: 52 * u, height: 8 * u), cornerRadius: 3 * u),
                 with: .color(c(0.3, 0.22, 0.16)))
        let mug = CGRect(x: s.width * 0.62, y: desk.minY - 30 * u, width: 26 * u, height: 30 * u)
        ctx.fill(Path(roundedRect: mug, cornerRadius: 4 * u), with: .color(c(0.92, 0.88, 0.8)))
        ctx.stroke(Path(ellipseIn: CGRect(x: mug.maxX - 6 * u, y: mug.minY + 6 * u, width: 14 * u, height: 14 * u)),
                   with: .color(c(0.92, 0.88, 0.8)), lineWidth: 4 * u)
        // Stacked books on desk
        for i in 0..<3 {
            ctx.fill(Path(CGRect(x: s.width * 0.3, y: desk.minY - CGFloat(i + 1) * 11 * u, width: (90 - CGFloat(i) * 8) * u, height: 10 * u)),
                     with: .color(books[(i * 2) % 6]))
        }
    }

    private static func sprintGrid(_ ctx: inout GraphicsContext, _ s: CGSize) {
        glow(&ctx, at: CGPoint(x: s.width * 0.1, y: s.height * 0.12), radius: s.width * 0.35, color: c(0.35, 0.55, 1, 0.22))
        glow(&ctx, at: CGPoint(x: s.width * 0.92, y: s.height * 0.9), radius: s.width * 0.3, color: c(0.55, 0.9, 0.4, 0.18))
        var grid = Path()
        var x: CGFloat = 0
        while x < s.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: s.height)); x += 32 }
        var y: CGFloat = 0
        while y < s.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: s.width, y: y)); y += 32 }
        ctx.stroke(grid, with: .color(c(0.2, 0.35, 0.7, 0.06)), lineWidth: 1)
    }

    private static func garden(_ ctx: inout GraphicsContext, _ s: CGSize) {
        var r = SceneRandom(23)
        // A low sunrise sun resting on the far hill (kept clear of the centre controls).
        let sun = CGPoint(x: s.width * 0.78, y: s.height * 0.66)
        let sr = s.width * 0.045
        glow(&ctx, at: sun, radius: s.width * 0.35, color: c(1, 0.86, 0.6, 0.4))
        ctx.fill(Path(ellipseIn: CGRect(x: sun.x - sr, y: sun.y - sr, width: sr * 2, height: sr * 2)), with: .color(c(1, 0.9, 0.7)))
        // Soft clouds
        for _ in 0..<5 {
            let p = CGPoint(x: r.next() * s.width, y: s.height * (0.1 + r.next() * 0.25))
            for k in 0..<3 {
                let w = 90 + r.next() * 80
                ctx.fill(Path(ellipseIn: CGRect(x: p.x + CGFloat(k) * 40, y: p.y - CGFloat(k % 2) * 12, width: w, height: w * 0.45)),
                         with: .color(.white.opacity(0.35)))
            }
        }
        // Three hills
        let hills: [(Double, Double, Color)] = [(0.66, 0.05, c(0.62, 0.78, 0.62)), (0.74, 0.06, c(0.5, 0.7, 0.53)), (0.84, 0.04, c(0.42, 0.62, 0.47))]
        for (i, (base, amp, color)) in hills.enumerated() {
            var h = Path()
            h.move(to: CGPoint(x: 0, y: s.height))
            for k in 0...40 {
                let xx = s.width * CGFloat(k) / 40
                h.addLine(to: CGPoint(x: xx, y: s.height * (base + amp * sin(Double(k) / 40 * .pi * 2 + Double(i) * 1.7))))
            }
            h.addLine(to: CGPoint(x: s.width, y: s.height)); h.closeSubpath()
            ctx.fill(h, with: .color(color))
        }
        // Pixel flowers on the near hill
        let petals = [c(1, 0.7, 0.75), c(1, 0.92, 0.6), c(0.85, 0.75, 1), c(1, 1, 1)]
        for _ in 0..<40 {
            let p = CGPoint(x: r.next() * s.width, y: s.height * (0.86 + r.next() * 0.12))
            let col = petals[Int(r.next() * 4) % 4]
            let u: CGFloat = 3
            for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)] {
                ctx.fill(Path(CGRect(x: p.x + CGFloat(dx) * u, y: p.y + CGFloat(dy) * u, width: u, height: u)), with: .color(col))
            }
            ctx.fill(Path(CGRect(x: p.x, y: p.y, width: u, height: u)), with: .color(c(1, 0.8, 0.3)))
        }
    }

    private static func morningDesk(_ ctx: inout GraphicsContext, _ s: CGSize) {
        // Window at top right with light beams
        let win = CGRect(x: s.width * 0.62, y: s.height * 0.06, width: s.width * 0.3, height: s.height * 0.32)
        ctx.fill(Path(roundedRect: win, cornerRadius: 8),
                 with: .linearGradient(Gradient(colors: [c(0.62, 0.82, 1), c(0.95, 0.97, 1)]),
                                       startPoint: CGPoint(x: win.midX, y: win.minY), endPoint: CGPoint(x: win.midX, y: win.maxY)))
        ctx.stroke(Path(roundedRect: win, cornerRadius: 8), with: .color(.white), lineWidth: 8)
        for i in 0..<3 {
            var beam = Path()
            let x0 = win.minX + win.width * CGFloat(i) / 3
            beam.move(to: CGPoint(x: x0, y: win.maxY))
            beam.addLine(to: CGPoint(x: x0 + win.width / 4, y: win.maxY))
            beam.addLine(to: CGPoint(x: x0 - s.width * 0.25, y: s.height))
            beam.addLine(to: CGPoint(x: x0 - s.width * 0.33, y: s.height))
            beam.closeSubpath()
            ctx.fill(beam, with: .color(.white.opacity(0.18)))
        }
        // Desk edge and a pixel plant
        ctx.fill(Path(CGRect(x: 0, y: s.height * 0.9, width: s.width, height: s.height * 0.1)), with: .color(c(0.93, 0.86, 0.74)))
        let pot = CGRect(x: s.width * 0.04, y: s.height * 0.82, width: 46, height: 40)
        ctx.fill(Path(roundedRect: pot, cornerRadius: 6), with: .color(c(0.85, 0.5, 0.35)))
        let leaf = c(0.35, 0.65, 0.42)
        for (dx, dy, w, h) in [(-10.0, -50.0, 22.0, 52.0), (16.0, -66.0, 18.0, 68.0), (34.0, -44.0, 22.0, 46.0)] {
            ctx.fill(Path(roundedRect: CGRect(x: pot.minX + dx, y: pot.minY + dy, width: w, height: h), cornerRadius: 10), with: .color(leaf))
        }
    }
}

/// Sparse moving details: fireflies, steam, light sweep, petals, motes, rain.
private struct ParticleLayer: View {
    let world: FocusWorld
    let density: Double
    let raining: Bool

    var body: some View {
        Ticking(every: density >= 1 ? 1.0 / 15 : 1.0 / 8) { tl in
            Canvas { ctx, size in
                let t = tl.timeIntervalSinceReferenceDate
                draw(&ctx, size, t)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext, _ s: CGSize, _ t: TimeInterval) {
        var r = SceneRandom(UInt64(world.rawValue.count * 97))
        switch world {
        case .deepFocus:
            let n = Int(12 * density)
            for i in 0..<n {
                let bx = r.next(), by = 0.6 + r.next() * 0.3, sp = 0.02 + r.next() * 0.03, ph = r.next() * 6.28
                let x = s.width * (bx + 0.03 * sin(t * sp * 6 + ph))
                let y = s.height * (by + 0.02 * cos(t * sp * 5 + ph * 1.3))
                let a = 0.25 + 0.55 * max(0, sin(t * 0.8 + Double(i)))
                let p = CGRect(x: x, y: y, width: 3, height: 3)
                ctx.fill(Path(ellipseIn: p.insetBy(dx: -4, dy: -4)), with: .color(Color(red: 1, green: 0.85, blue: 0.4).opacity(a * 0.15)))
                ctx.fill(Path(ellipseIn: p), with: .color(Color(red: 1, green: 0.9, blue: 0.55).opacity(a)))
            }
            if raining {
                var streaks = Path()
                for _ in 0..<Int(70 * density) {
                    let x0 = r.next() * s.width, speed = 0.5 + r.next() * 0.4
                    let y = (r.next() + t * speed).truncatingRemainder(dividingBy: 1) * s.height
                    streaks.move(to: CGPoint(x: x0, y: y))
                    streaks.addLine(to: CGPoint(x: x0 - 3, y: y + 14))
                }
                ctx.stroke(streaks, with: .color(.white.opacity(0.12)), lineWidth: 1)
            }
        case .study:
            // Steam from the mug and dust motes in the lamp light.
            let u = s.width / 1280
            let mug = CGPoint(x: s.width * 0.62 + 13 * u, y: s.height * 0.74 - 34 * u)
            for i in 0..<3 {
                let ph = (t * 0.25 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let p = CGPoint(x: mug.x + 6 * sin(t + Double(i) * 2), y: mug.y - ph * 50)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white.opacity(0.25 * (1 - ph))))
            }
            for _ in 0..<Int(14 * density) {
                let bx = 0.4 + r.next() * 0.25, by = r.next(), sp = 0.01 + r.next() * 0.02
                let y = (by - t * sp).truncatingRemainder(dividingBy: 1)
                let p = CGPoint(x: s.width * (bx + 0.01 * sin(t + by * 9)), y: s.height * (0.35 + (y < 0 ? y + 1 : y) * 0.4))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 2, height: 2)), with: .color(Color(red: 1, green: 0.9, blue: 0.7).opacity(0.5)))
            }
        case .workSprint:
            // One slow diagonal light sweep every ~8 s.
            let ph = (t / 8).truncatingRemainder(dividingBy: 1)
            let x = -s.width * 0.3 + ph * s.width * 1.6
            var band = Path()
            band.move(to: CGPoint(x: x, y: 0)); band.addLine(to: CGPoint(x: x + 120, y: 0))
            band.addLine(to: CGPoint(x: x - 180, y: s.height)); band.addLine(to: CGPoint(x: x - 300, y: s.height)); band.closeSubpath()
            ctx.fill(band, with: .color(.white.opacity(0.18 * density)))
        case .recharge:
            for i in 0..<Int(16 * density) {
                let bx = r.next(), sp = 0.015 + r.next() * 0.02, ph = r.next()
                let y = (ph + t * sp).truncatingRemainder(dividingBy: 1)
                let x = (bx + 0.05 * sin(t * 0.5 + Double(i))).truncatingRemainder(dividingBy: 1)
                var petal = Path(ellipseIn: CGRect(x: 0, y: 0, width: 6, height: 3.5))
                petal = petal.applying(CGAffineTransform(rotationAngle: t + Double(i)))
                ctx.translateBy(x: s.width * x, y: s.height * y)
                ctx.fill(petal, with: .color(Color(red: 1, green: 0.72, blue: 0.78).opacity(0.7)))
                ctx.translateBy(x: -s.width * x, y: -s.height * y)
            }
        case .planning:
            for _ in 0..<Int(10 * density) {
                let bx = 0.4 + r.next() * 0.45, by = r.next(), sp = 0.008 + r.next() * 0.01
                let y = (by + t * sp).truncatingRemainder(dividingBy: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: s.width * bx, y: s.height * (0.3 + y * 0.6), width: 2.5, height: 2.5)),
                         with: .color(.white.opacity(0.8)))
            }
        }
    }
}
