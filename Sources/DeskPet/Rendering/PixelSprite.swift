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

/// A tiny RGBA bitmap at 1 pixel per sprite pixel. Scaled up on screen with
/// nearest-neighbour filtering, so it stays crisp and costs almost nothing to draw.
struct PixelBitmap {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        // Premultiplied alpha; all our colours are opaque.
        bytes[i] = c.r; bytes[i + 1] = c.g; bytes[i + 2] = c.b; bytes[i + 3] = c.a
    }

    func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Pixel art described by strings: one character per pixel, '.' is transparent.
struct PixelSprite {
    let rows: [[Character]]
    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    init(_ lines: [String]) {
        rows = lines.map(Array.init)
    }

    func paint(into bitmap: inout PixelBitmap, at origin: (x: Int, y: Int) = (0, 0),
               palette: (Character) -> RGBA?) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." && ch != " " {
                if let c = palette(ch) { bitmap.set(origin.x + x, origin.y + y, c) }
            }
        }
    }

    /// Standalone image using the standard palette (for props).
    func makeImage() -> CGImage? {
        var bitmap = PixelBitmap(width: width, height: height)
        paint(into: &bitmap, palette: PixelPalette.standard)
        return bitmap.makeImage()
    }
}

/// Small prop sprites used for reactions, rasterised once.
enum PropSprites {
    static let heart = PixelSprite([
        ".RR.RR.",
        "RRRRRRR",
        "RWRRRRR",
        ".RRRRR.",
        "..RRR..",
        "...R...",
    ])

    static let fish = PixelSprite([
        "..BBBB..K",
        ".BBBBBBKK",
        "BWKBBBBBK",
        ".BBBBBBKK",
        "..BBBB..K",
    ])

    static let yarn = PixelSprite([
        ".YYYY.",
        "YyYYyY",
        "YYyyYY",
        "YyYYyY",
        ".YYYY.",
    ])

    static let heartImage = heart.makeImage()
    static let fishImage = fish.makeImage()
    static let yarnImage = yarn.makeImage()
}

/// Shows a pixel bitmap scaled up with hard edges.
struct PixelImageView: View {
    var image: CGImage?
    var pixel: CGFloat

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: CGFloat(image.width) * pixel, height: CGFloat(image.height) * pixel)
                .accessibilityHidden(true)
        }
    }
}
