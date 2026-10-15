import AppKit
import DeskPetCore
import SwiftUI

/// The whole floating scene: speech bubble, animated cat with props, and the
/// hover action bar. Positions come from PetLayout so hit-testing matches.
struct PetView: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var windowState: PetWindowState
    @ObservedObject var settings: AppSettings
    let driver: PetAnimationDriver
    var onDragChanged: (Bool) -> Void
    var onDragEnded: () -> Void
    var contextMenu: () -> NSMenu?
    var onOpenSettings: () -> Void

    var body: some View {
        let layout = windowState.layout
        let animate = settings.effectiveAnimations

        ZStack(alignment: .topLeading) {
            Color.clear

            // Speech bubble, centred over the cat's body.
            ZStack(alignment: .bottom) {
                if let line = pet.speech {
                    SpeechBubble(text: line)
                        .id(line)
                        .transition(animate ? .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity) : .opacity)
                }
            }
            .frame(width: layout.windowSize.width - 12,
                   height: layout.bubbleAreaHeight(lifted: pet.reaction == .playing), alignment: .bottom)
            .padding(.leading, 6)
            .allowsHitTesting(false)

            // Animated cat + props. Rendering only; input is handled below.
            PetStageHost(driver: driver)
            .padding(.leading, layout.catOrigin.x)
            .padding(.top, layout.catOrigin.y)
            .allowsHitTesting(false)

            // Static input layer exactly over the cat (doesn't hop with it).
            PetInteractionView(
                onClick: { pet.pet() },
                onDragChanged: onDragChanged,
                onDragEnded: onDragEnded,
                contextMenu: contextMenu
            )
            .frame(width: layout.catSize.width, height: layout.catSize.height)
            .padding(.leading, layout.catOrigin.x)
            .padding(.top, layout.catOrigin.y)
            .accessibilityElement()
            .accessibilityLabel("\(pet.name) the cat")
            .accessibilityHint("Click to pet. Drag to move. Right-click for options.")
            .accessibilityAddTraits(.isButton)

            if windowState.isHovered && !windowState.isDragging {
                ActionBar(pet: pet, onOpenSettings: onOpenSettings)
                    .frame(width: layout.barFrame.width, height: layout.barFrame.height)
                    .padding(.leading, layout.barFrame.minX)
                    .padding(.top, layout.barFrame.minY)
                    .transition(.opacity.combined(with: .offset(y: animate ? 6 : 0)))
            }
        }
        .frame(width: layout.windowSize.width, height: layout.windowSize.height)
        .animation(animate ? .spring(response: 0.3, dampingFraction: 0.7) : nil, value: pet.speech)
        .animation(.easeOut(duration: 0.18), value: windowState.isHovered)
        .animation(animate ? .easeOut(duration: 0.2) : nil, value: pet.reaction)
    }
}

/// Cat plus reaction props for a single moment in time. Built from plain
/// values (not the clock) so unchanged frames compare equal and are skipped.
struct PetStage: View, Equatable {
    enum Props: Equatable {
        case none
        case sleeping(t: TimeInterval)
        case petted(age: TimeInterval)
        case eating(age: TimeInterval)
        case playing(age: TimeInterval)
    }

    let frame: PetFrame
    let props: Props
    let animate: Bool
    let pixel: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            CatCanvas(pose: frame.pose, pixel: pixel)
                .scaleEffect(x: 1, y: frame.stretch, anchor: .bottom)
                .offset(x: frame.shake * pixel, y: -frame.hop * pixel)
            propsView
        }
        .frame(width: CGFloat(CatSprite.width) * pixel, height: CGFloat(CatSprite.height) * pixel,
               alignment: .topLeading)
    }

    @ViewBuilder
    private var propsView: some View {
        let p = pixel
        switch props {
        case .none:
            EmptyView()
        case .sleeping(let t):
            ForEach(0..<3, id: \.self) { i in
                let phase = animate ? (t / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1) : Double(i) * 0.3
                Text("z")
                    .font(.system(size: p * (2.4 + phase * 1.6), weight: .heavy, design: .monospaced))
                    .foregroundStyle(PixelPalette.outline.opacity(0.85))
                    .opacity(animate ? sin(phase * .pi) : 1)
                    .offset(x: p * (15 + phase * 5), y: p * (1 - phase * 9))
            }
        case .petted(let age):
            ForEach(0..<3, id: \.self) { i in
                let local = max(0, age - Double(i) * 0.2)
                let progress = min(1, local / 1.2)
                if local > 0 {
                    // Hearts drift up from alternating cheeks, staying clear of the bubble.
                    PixelImageView(image: PropSprites.heartImage, pixel: p * 0.6)
                        .offset(x: p * (i % 2 == 0 ? -3.5 + Double(i) * 0.5 : 17.5),
                                y: p * (6 - progress * 7))
                        .opacity(1 - progress)
                }
            }
        case .eating(let age):
            let eaten = animate ? min(1, age / PetViewModel.Reaction.eating.duration) : 0.3
            PixelImageView(image: PropSprites.fishImage, pixel: p * 0.85)
                .scaleEffect(x: -(1 - eaten * 0.85), y: 1 - eaten * 0.5, anchor: .trailing)
                .offset(x: -p * 8, y: p * 8.5)
                .opacity(1 - eaten * 0.7)
        case .playing(let age):
            let bounce = animate ? abs(sin(age * .pi * 2.2 + .pi / 2)) : 0
            PixelImageView(image: PropSprites.yarnImage, pixel: p * 0.8)
                .rotationEffect(.degrees(animate ? age * 360 : 0))
                .offset(x: -p * (5 + sin(age * 3) * 1.5), y: p * (15 - bounce * 7))
        }
    }
}

/// Observes only the driver, so frame changes don't re-evaluate the whole scene.
private struct PetStageHost: View {
    @ObservedObject var driver: PetAnimationDriver
    var body: some View { driver.stage }
}

/// Retro-styled speech bubble with a little tail.
struct SpeechBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(PixelPalette.outline)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                BubbleShape()
                    .fill(Color(red: 1, green: 0.99, blue: 0.96))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            )
            .overlay(BubbleShape().stroke(PixelPalette.outline, lineWidth: 2))
            .padding(.bottom, BubbleShape.tailHeight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}

/// Rounded rectangle with a downward tail, drawn into the bottom padding.
struct BubbleShape: Shape {
    static let tailHeight: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 9, style: .continuous)
        let mid = rect.midX
        var tail = Path()
        tail.move(to: CGPoint(x: mid - 6, y: rect.maxY - 1))
        tail.addLine(to: CGPoint(x: mid, y: rect.maxY + Self.tailHeight))
        tail.addLine(to: CGPoint(x: mid + 6, y: rect.maxY - 1))
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}

/// Compact hover bar: Feed · Play · Sleep/Wake · Settings.
private struct ActionBar: View {
    @ObservedObject var pet: PetViewModel
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ActionButton(symbol: "fork.knife", label: "Feed", action: pet.feed)
            ActionButton(symbol: "teddybear.fill", label: "Play", action: pet.play)
            ActionButton(symbol: pet.isSleeping ? "sun.max.fill" : "moon.zzz.fill",
                         label: pet.isSleeping ? "Wake up" : "Nap", action: pet.toggleSleep)
            ActionButton(symbol: "gearshape.fill", label: "Settings", action: onOpenSettings)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(PixelPalette.outline.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}

private struct ActionButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? PixelPalette.orange.opacity(0.3) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PixelPalette.outline)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering = $0 }
    }
}
