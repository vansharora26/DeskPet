import SwiftUI

/// Everything needed to draw one frame of the cat.
struct CatPose: Hashable {
    enum Eyes: Hashable { case open, blink, happy, sleepy, closed }
    var eyes: Eyes = .open
    var mouthOpen = false
    var blush = false
    var tailFrame = 0
}

/// Original pixel-art orange tabby, drawn from character grids.
enum CatSprite {
    /// Canvas size in sprite pixels (body + tail).
    static let width = 24
    static let height = 19
    /// Horizontal extent of the body (tail excluded), used for hit-testing.
    static let bodyColumns = 0..<18

    // K outline · O orange · D stripe · L cream · P pink
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
        PixelSprite([
            "...KK.",
            "..KOOK",
            "..KODK",
            "..KOK.",
            ".KOK..",
            ".KDK..",
            "KOK...",
            "KK....",
        ]),
        PixelSprite([
            "......",
            "....K.",
            "...KOK",
            "...KDK",
            "..KOK.",
            "..KOK.",
            ".KDK..",
            "KOK...",
            "KK....",
        ]),
    ]

    /// Eye pixels for each style, relative to the left eye's top-left (col 4, row 6).
    /// The right eye is the same pattern shifted 8 columns.
    private static func eyePixels(_ eyes: CatPose.Eyes) -> [(dx: Int, dy: Int, ch: Character)] {
        switch eyes {
        case .open:   return [(0, 0, "K"), (1, 0, "W"), (0, 1, "K"), (1, 1, "K")]
        case .blink:  return [(-1, 1, "K"), (0, 1, "K"), (1, 1, "K")]
        case .happy:  return [(-1, 1, "K"), (0, 0, "K"), (1, 0, "K"), (2, 1, "K")]
        case .sleepy: return [(0, 0, "D"), (1, 0, "D"), (0, 1, "K"), (1, 1, "K")]
        case .closed: return [(-1, 0, "K"), (0, 1, "K"), (1, 1, "K"), (2, 0, "K")]
        }
    }

    /// Rasterises one pose at 1 pixel per sprite pixel.
    static func makeImage(_ pose: CatPose) -> CGImage? {
        var bitmap = PixelBitmap(width: width, height: height)
        tails[pose.tailFrame % tails.count]
            .paint(into: &bitmap, at: (17, 9), palette: PixelPalette.standard)

        body.paint(into: &bitmap) { ch in
            switch ch {
            case "C": return pose.blush ? PixelPalette.blushRGBA : PixelPalette.orangeRGBA
            case "M": return PixelPalette.outlineRGBA
            case "N": return pose.mouthOpen ? PixelPalette.pinkRGBA : PixelPalette.outlineRGBA
            default: return PixelPalette.standard(ch)
            }
        }

        for eyeX in [4, 12] {
            for p in eyePixels(pose.eyes) {
                if let c = PixelPalette.standard(p.ch) { bitmap.set(eyeX + p.dx, 6 + p.dy, c) }
            }
        }
        return bitmap.makeImage()
    }

    /// There are only a few dozen distinct poses, so each is rendered once and reused.
    @MainActor private static var cache: [CatPose: CGImage] = [:]

    @MainActor static func image(_ pose: CatPose) -> CGImage? {
        if let hit = cache[pose] { return hit }
        let image = makeImage(pose)
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
