import AppKit
import DeskPetCore
import SwiftUI

/// Renders the cat offscreen into PNGs. Used by the build script to produce
/// the app icon (`DeskPet --export-iconset <dir>`), so no binary art assets
/// need to be checked in.
@MainActor
enum IconRenderer {
    /// The icon artwork: the cat on a soft rounded-square badge.
    struct IconView: View {
        var size: CGFloat
        var body: some View {
            let pixel = size * 0.62 / CGFloat(CatSprite.width)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.93, blue: 0.80), Color(red: 1.0, green: 0.80, blue: 0.62)],
                        startPoint: .top, endPoint: .bottom))
                    .padding(size * 0.08)
                CatCanvas(pose: CatPose(eyes: .happy, blush: true), pixel: pixel)
                    .offset(x: pixel * 3, y: size * 0.02) // body (not tail) visually centred
            }
            .frame(width: size, height: size)
        }
    }

    static func png(size: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: IconView(size: size))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// Writes a standard .iconset folder for `iconutil -c icns`.
    static func exportIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                guard let data = png(size: CGFloat(base * scale)) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: dir.appendingPathComponent(name))
            }
        }
    }

    /// One labelled preview tile: a pet state with its props and a bubble.
    private struct PreviewTile: View {
        var title: String
        var stage: PetStage
        var speech: String?
        var callout: PetCallout?
        let layout = PetLayout(pixel: 5)

        var body: some View {
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Color(red: 0.36, green: 0.52, blue: 0.74) // stand-in desktop wallpaper
                    ZStack(alignment: .bottom) {
                        if let callout {
                            CalloutBubble(callout: callout, onClose: {})
                        } else if let speech {
                            SpeechBubble(text: speech)
                        }
                    }
                    .frame(width: layout.windowSize.width - 12,
                           height: layout.bubbleAreaHeight(lifted: title == "Playing" || title == "Celebrating"), alignment: .bottom)
                    .padding(.leading, 6)
                    stage
                        .padding(.leading, layout.catOrigin.x)
                        .padding(.top, layout.catOrigin.y)
                }
                .frame(width: layout.windowSize.width, height: layout.windowSize.height - PetLayout.barHeight)
                .clipped()
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
    }

    /// `DeskPet --export-previews <dir>`: renders animation states and wardrobe
    /// combinations to PNG for visual QA and marketing. Draws only the app's own art.
    static func exportPreviews(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func stage(_ input: PetAnimator.Input, at t: TimeInterval, props: PetStage.Props) -> PetStage {
            PetStage(frame: PetAnimator.frame(at: t, input), props: props, animate: true, pixel: 5)
        }
        func input(_ r: PetViewModel.Reaction?, age: TimeInterval = 0, sleeping: Bool = false, mood: PetMood = .content,
                   mode: PetMode = .none, coat: CoatTheme = .ginger, accessory: Accessory? = nil) -> PetAnimator.Input {
            .init(reaction: r, reactionAge: age, sleeping: sleeping, mood: mood, mode: mode, hovered: false, animate: true,
                  coat: coat, accessory: accessory)
        }
        let reminder = PetCallout(kind: .hydration, symbol: "drop.fill",
                                  message: "Sip break? 1.2 L of 2 L so far.",
                                  actions: [.init(title: "Log 250 ml", isPrimary: true) {}, .init(title: "Snooze 15m") {}])
        let states: [PreviewTile] = [
            PreviewTile(title: "Idle", stage: stage(input(nil), at: 1, props: .none)),
            PreviewTile(title: "Focused", stage: stage(input(nil, mode: .focused), at: 1, props: .none),
                        speech: "Focus mode on. I’ll keep quiet."),
            PreviewTile(title: "Thirsty", stage: stage(input(nil, mode: .thirsty), at: 1, props: .droplet(t: 1)), callout: reminder),
            PreviewTile(title: "Resting", stage: stage(input(nil, mode: .resting), at: 1, props: .mug(t: 1)),
                        speech: "Break time! Stretch, sip, look far away."),
            PreviewTile(title: "Celebrating", stage: stage(input(.celebrating, age: 0.3), at: 1, props: .confetti(age: 0.6)),
                        speech: "Session complete! 🎉"),
            PreviewTile(title: "Sipping", stage: stage(input(.sipping, age: 0.5), at: 1, props: .sip(age: 0.5)),
                        speech: "Gulp gulp! 💧"),
            PreviewTile(title: "Sleepy", stage: stage(input(nil, mood: .tired), at: 1, props: .none), speech: "So… sleepy…"),
            PreviewTile(title: "Sleeping", stage: stage(input(nil, sleeping: true), at: 1, props: .sleeping(t: 1.4))),
        ]
        let wardrobe: [PreviewTile] = [
            PreviewTile(title: "Smoky + bow", stage: stage(input(nil, coat: .smoky, accessory: .bow), at: 1, props: .none)),
            PreviewTile(title: "Tuxedo + glasses", stage: stage(input(nil, coat: .tuxedo, accessory: .glasses), at: 1, props: .none)),
            PreviewTile(title: "Biscuit + party hat", stage: stage(input(nil, coat: .biscuit, accessory: .partyHat), at: 1, props: .none)),
            PreviewTile(title: "Ginger + crown", stage: stage(input(nil, accessory: .crown), at: 1, props: .none)),
            PreviewTile(title: "Smoky + headphones", stage: stage(input(nil, coat: .smoky, accessory: .headphones), at: 1, props: .none)),
            PreviewTile(title: "Ginger + scarf", stage: stage(input(nil, accessory: .scarf), at: 1, props: .none)),
            PreviewTile(title: "Tuxedo focusing", stage: stage(input(nil, mode: .focused, coat: .tuxedo), at: 1, props: .none)),
            PreviewTile(title: "Petted", stage: stage(input(.petted, age: 0.6), at: 1, props: .petted(age: 0.6)),
                        speech: "More chin scritches pls"),
        ]
        try render(sheet(states), to: dir.appendingPathComponent("states.png"))
        try render(sheet(wardrobe), to: dir.appendingPathComponent("wardrobe.png"))
    }

    private static func sheet(_ tiles: [PreviewTile]) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) { ForEach(0..<4, id: \.self) { tiles[$0] } }
            HStack(spacing: 16) { ForEach(4..<8, id: \.self) { tiles[$0] } }
        }
        .padding(20)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private static func render<V: View>(_ view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
