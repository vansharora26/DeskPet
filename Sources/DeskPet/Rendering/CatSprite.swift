import DeskPetCore
import SwiftUI

/// Everything needed to draw one frame of the cat.
struct CatPose: Hashable {
    enum Eyes: Hashable { case open, blink, happy, sleepy, closed }
    var eyes: Eyes = .open
    var mouthOpen = false
    var blush = false
    var tailFrame = 0
    var coat: CoatTheme = .ginger
    var accessory: Accessory?
    /// Worn during focus sessions.
    var headband = false
}

/// Colour roles that change with the coat theme.
struct CoatPalette {
    var fur: RGBA, stripe: RGBA, cream: RGBA, innerEar: RGBA, eye: RGBA, outline: RGBA

    static func of(_ coat: CoatTheme) -> CoatPalette {
        switch coat {
        case .ginger:
            return CoatPalette(fur: PixelPalette.orangeRGBA, stripe: PixelPalette.stripeRGBA, cream: PixelPalette.creamRGBA,
                               innerEar: PixelPalette.pinkRGBA, eye: PixelPalette.outlineRGBA, outline: PixelPalette.outlineRGBA)
        case .smoky:
            return CoatPalette(fur: RGBA(r: 158, g: 164, b: 178), stripe: RGBA(r: 116, g: 122, b: 138),
                               cream: RGBA(r: 233, g: 234, b: 240), innerEar: PixelPalette.pinkRGBA,
                               eye: RGBA(r: 44, g: 46, b: 58), outline: RGBA(r: 44, g: 46, b: 58))
        case .tuxedo:
            return CoatPalette(fur: RGBA(r: 62, g: 60, b: 70), stripe: RGBA(r: 46, g: 44, b: 54),
                               cream: RGBA(r: 246, g: 244, b: 240), innerEar: RGBA(r: 214, g: 140, b: 158),
                               eye: RGBA(r: 150, g: 214, b: 92), outline: RGBA(r: 22, g: 20, b: 26))
        case .biscuit:
            return CoatPalette(fur: RGBA(r: 238, g: 210, b: 166), stripe: RGBA(r: 212, g: 176, b: 124),
                               cream: RGBA(r: 255, g: 247, b: 232), innerEar: PixelPalette.pinkRGBA,
                               eye: PixelPalette.outlineRGBA, outline: RGBA(r: 92, g: 62, b: 40))
        }
    }
}

/// Original pixel-art cat, drawn from character grids.
enum CatSprite {
    /// Rows of headroom above the ears for hats and headphones.
    static let top = 4
    /// Canvas size in sprite pixels (body + tail + headroom).
    static let width = 24
    static let height = 19 + top

    // K outline · O fur · D stripe · L cream · P inner ear
    // C cheek (blush when happy) · M mouth corner · N mouth centre (tongue when open)
    static let body = PixelSprite([
        ".KK............KK.",
        ".KPK..........KPK.",
        ".KPOK........KOPK.",
        ".KPOOKKKKKKKKOOPK.",
        "KOOOOOODOODOOOOOOK",
        "KOOOOOOODDOOOOOOOK",
        "KOOOOOOOOOOOOOOOOK",
        "KOOOOOOOOOOOOOOOOK",
        "KOCOOLLLPPLLLOOCOK",
        "KOOOOLLMLLMLLOOOOK",
        ".KOOOOLLNNLLOOOOK.",
        "..KOOOLLLLLLOOOK..",
        ".KOODOLLLLLLODOOK.",
        ".KOOOOLLLLLLOOOOK.",
        "KOODOOLLLLLLOODOOK",
        "KOOOOOLLLLLLOOOOOK",
        "KOODOOOLLLLOOODOOK",
        "KOOOKLLLKKLLLKOOOK",
        ".KKKKKKKKKKKKKKKK.",
    ])

    /// Two tail positions; both are anchored at body column 17, row 9.
    static let tails = [
        PixelSprite(["...KK.", "..KOOK", "..KODK", "..KOK.", ".KOK..", ".KDK..", "KOK...", "KK...."]),
        PixelSprite(["......", "....K.", "...KOK", "...KDK", "..KOK.", "..KOK.", ".KDK..", "KOK...", "KK...."]),
    ]

    // Accessories, positioned in canvas coordinates (headroom included).
    // G gold · g dark gold · Y/y purple · R red · W white · B blue · K outline
    private static let accessories: [Accessory: (sprite: PixelSprite, x: Int, y: Int)] = [
        .bow: (PixelSprite(["RR.RR", "RRKRR", "RR.RR"]), 11, top + 1),
        .glasses: (PixelSprite([
            "KKKK....KKKK",
            "K..KKKKKK..K",
            "K..K....K..K",
            "KKKK....KKKK",
        ]), 3, top + 5),
        .scarf: (PixelSprite([
            ".RRWRRWRRWRR.",
            "........RR...",
            "........RW...",
        ]), 2, top + 11),
        .partyHat: (PixelSprite([
            "..WW..",
            "..YY..",
            ".YyyY.",
            ".YYYY.",
            "YyYYyY",
            "YYYYYY",
        ]), 6, 1),
        .headphones: (PixelSprite([
            ".....KKKKKKKK.....",
            "...KK........KK...",
            "..K............K..",
            ".K..............K.",
            ".K..............K.",
            "BB..............BB",
            "BB..............BB",
            "BB..............BB",
            "BB..............BB",
        ]), 0, 2),
        .crown: (PixelSprite([
            "G..GG..G",
            "GG.GG.GG",
            "GGGRGGGG",
            "gggggggg",
        ]), 5, top - 1),
    ]

    private static let headband = PixelSprite([
        "................R.",
        ".RRRRRRRRRRRRRRRWR",
        "................R.",
    ])

    /// Eye pixels for each style, relative to the left eye's top-left (col 4, row 6).
    /// "E" is the coat's eye colour. The right eye is the same pattern shifted 8 columns.
    private static func eyePixels(_ eyes: CatPose.Eyes) -> [(dx: Int, dy: Int, ch: Character)] {
        switch eyes {
        case .open:   return [(0, 0, "E"), (1, 0, "W"), (0, 1, "E"), (1, 1, "E")]
        case .blink:  return [(-1, 1, "K"), (0, 1, "K"), (1, 1, "K")]
        case .happy:  return [(-1, 1, "K"), (0, 0, "K"), (1, 0, "K"), (2, 1, "K")]
        case .sleepy: return [(0, 0, "D"), (1, 0, "D"), (0, 1, "E"), (1, 1, "E")]
        case .closed: return [(-1, 0, "K"), (0, 1, "K"), (1, 1, "K"), (2, 0, "K")]
        }
    }

    /// Rasterises one pose at 1 pixel per sprite pixel.
    static func makeImage(_ pose: CatPose) -> CGImage? {
        let pal = CoatPalette.of(pose.coat)
        func color(_ ch: Character) -> RGBA? {
            switch ch {
            case "K", "M": return pal.outline
            case "O": return pal.fur
            case "D": return pal.stripe
            case "L": return pal.cream
            case "P": return pal.innerEar
            case "E": return pal.eye
            case "C": return pose.blush ? PixelPalette.blushRGBA : pal.fur
            case "N": return pose.mouthOpen ? PixelPalette.pinkRGBA : pal.outline
            case "G": return RGBA(r: 250, g: 204, b: 64)
            case "g": return RGBA(r: 214, g: 158, b: 36)
            default: return PixelPalette.standard(ch)
            }
        }

        var bitmap = PixelBitmap(width: width, height: height)
        tails[pose.tailFrame % tails.count].paint(into: &bitmap, at: (17, 9 + top), palette: color)
        body.paint(into: &bitmap, at: (0, top), palette: color)
        for eyeX in [4, 12] {
            for p in eyePixels(pose.eyes) {
                if let c = color(p.ch) { bitmap.set(eyeX + p.dx, top + 6 + p.dy, c) }
            }
        }
        if pose.headband {
            headband.paint(into: &bitmap, at: (0, top + 3), palette: color)
        }
        if let a = pose.accessory, let spec = accessories[a] {
            spec.sprite.paint(into: &bitmap, at: (spec.x, spec.y), palette: color)
        }
        return bitmap.makeImage()
    }

    /// Each distinct pose is rendered once and reused.
    @MainActor private static var cache: [CatPose: CGImage] = [:]

    @MainActor static func image(_ pose: CatPose) -> CGImage? {
        if let hit = cache[pose] { return hit }
        let image = makeImage(pose)
        if cache.count > 300 { cache.removeAll() } // bounded: poses × coats × accessories
        cache[pose] = image
        return image
    }
}

/// A SwiftUI view that shows a single cat frame.
struct CatCanvas: View {
    var pose: CatPose
    var pixel: CGFloat

    var body: some View {
        PixelImageView(image: CatSprite.image(pose), pixel: pixel)
            .frame(width: CGFloat(CatSprite.width) * pixel, height: CGFloat(CatSprite.height) * pixel)
    }
}
