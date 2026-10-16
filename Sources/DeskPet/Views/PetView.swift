import AppKit
import DeskPetCore
import SwiftUI

/// What the hover bar and badge can do. Supplied by the coordinator.
struct PetBarActions {
    var logWater: () -> Void
    var toggleFocus: () -> Void
    var openFocus: () -> Void
    var openChat: () -> Void
    var openCapture: () -> Void
    var enterWorld: () -> Void
    var moreMenu: () -> NSMenu?
}

/// The whole floating scene: speech or callout bubble, animated cat with props,
/// and the hover action bar / focus badge. Positions come from PetLayout so
/// click-through hit-testing matches exactly.
struct PetView: View {
    @ObservedObject var pet: PetViewModel
    @ObservedObject var windowState: PetWindowState
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    let driver: PetAnimationDriver
    var onDragChanged: (Bool) -> Void
    var onDragEnded: () -> Void
    var contextMenu: () -> NSMenu?
    var actions: PetBarActions
    var onKey: (NSEvent) -> Bool

    var body: some View {
        let layout = windowState.layout
        let animate = settings.effectiveAnimations

        ZStack(alignment: .topLeading) {
            Color.clear

            // Bubble area, centred over the cat's body.
            ZStack(alignment: .bottom) {
                if let callout = pet.callout {
                    CalloutBubble(callout: callout, onClose: {
                        callout.onDismiss?()
                        pet.clearCallout(id: callout.id)
                    })
                    .id(callout.id)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: CalloutFrameKey.self, value: proxy.frame(in: .named("pet")))
                    })
                    .transition(animate ? .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity) : .opacity)
                } else if let line = pet.speech {
                    SpeechBubble(text: line)
                        .id(line)
                        .allowsHitTesting(false)
                        .transition(animate ? .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity) : .opacity)
                }
            }
            .frame(width: layout.windowSize.width - 12,
                   height: layout.bubbleAreaHeight(lifted: pet.reaction == .playing || pet.reaction == .celebrating),
                   alignment: .bottom)
            .padding(.leading, 6)

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
                contextMenu: contextMenu,
                onKey: onKey
            )
            .frame(width: layout.catSize.width, height: layout.catSize.height)
            .overlay {
                if windowState.keyboardMode {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(DP.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
            }
            .padding(.leading, layout.catOrigin.x)
            .padding(.top, layout.catOrigin.y)
            .accessibilityElement()
            .accessibilityLabel("\(pet.name) the cat")
            .accessibilityHint("Click to pet. Drag to move. Right-click for the menu.")
            .accessibilityAddTraits(.isButton)

            Group {
                if windowState.isHovered && !windowState.isDragging {
                    ActionBar(model: model, actions: actions)
                        .transition(.opacity.combined(with: .offset(y: animate ? 6 : 0)))
                } else if let timer = model.focusTimerState, !windowState.isDragging {
                    FocusBadge(timer: timer, onTap: actions.openFocus)
                        .transition(.opacity)
                }
            }
            .frame(width: layout.barFrame.width, height: layout.barFrame.height)
            .padding(.leading, layout.barFrame.minX)
            .padding(.top, layout.barFrame.minY)
        }
        .frame(width: layout.windowSize.width, height: layout.windowSize.height)
        .coordinateSpace(name: "pet")
        .onPreferenceChange(CalloutFrameKey.self) { frame in
            windowState.calloutFrame = pet.callout == nil ? nil : frame
        }
        .onChange(of: pet.callout?.id) { _, id in if id == nil { windowState.calloutFrame = nil } }
        .onChange(of: model.focusTimerState != nil) { _, active in windowState.badgeVisible = active }
        .onAppear { windowState.badgeVisible = model.focusTimerState != nil }
        .animation(animate ? .spring(response: 0.3, dampingFraction: 0.7) : nil, value: pet.speech)
        .animation(animate ? .spring(response: 0.3, dampingFraction: 0.75) : nil, value: pet.callout?.id)
        .animation(.easeOut(duration: 0.18), value: windowState.isHovered)
        .animation(animate ? .easeOut(duration: 0.2) : nil, value: pet.reaction)
    }
}

struct CalloutFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
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
        case confetti(age: TimeInterval)
        case sip(age: TimeInterval)
        case droplet(t: TimeInterval)
        case mug(t: TimeInterval)
        case listening(t: TimeInterval)
        case thinking(t: TimeInterval)
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
        let top = Double(CatSprite.top)
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
                    .offset(x: p * (15 + phase * 5), y: p * (top + 1 - phase * 9))
            }
        case .petted(let age):
            ForEach(0..<3, id: \.self) { i in
                let local = max(0, age - Double(i) * 0.2)
                let progress = min(1, local / 1.2)
                if local > 0 {
                    // Hearts drift up from alternating cheeks, staying clear of the bubble.
                    PixelImageView(image: PropSprites.heartImage, pixel: p * 0.6)
                        .offset(x: p * (i % 2 == 0 ? -3.5 + Double(i) * 0.5 : 17.5),
                                y: p * (top + 6 - progress * 7))
                        .opacity(1 - progress)
                }
            }
        case .eating(let age):
            let eaten = animate ? min(1, age / PetViewModel.Reaction.eating.duration) : 0.3
            PixelImageView(image: PropSprites.fishImage, pixel: p * 0.85)
                .scaleEffect(x: -(1 - eaten * 0.85), y: 1 - eaten * 0.5, anchor: .trailing)
                .offset(x: -p * 8, y: p * (top + 8.5))
                .opacity(1 - eaten * 0.7)
        case .playing(let age):
            let bounce = animate ? abs(sin(age * .pi * 2.2 + .pi / 2)) : 0
            PixelImageView(image: PropSprites.yarnImage, pixel: p * 0.8)
                .rotationEffect(.degrees(animate ? age * 360 : 0))
                .offset(x: -p * (5 + sin(age * 3) * 1.5), y: p * (top + 15 - bounce * 7))
        case .confetti(let age):
            ForEach(0..<14, id: \.self) { i in
                ConfettiBit(index: i, age: age, pixel: p)
            }
        case .sip(let age):
            let progress = min(1, age / PetViewModel.Reaction.sipping.duration)
            // A droplet drifts down to the mouth and disappears.
            PixelImageView(image: PropSprites.dropletImage, pixel: p * 0.7)
                .offset(x: p * 7.3, y: p * (top + 5.5 + progress * 3.5))
                .opacity(1 - progress * progress)
        case .droplet(let t):
            PixelImageView(image: PropSprites.dropletImage, pixel: p * 0.8)
                .offset(x: p * 16.5, y: p * (top - 2 + sin(t * 3) * 0.6))
        case .listening(let t):
            // Three pixel "sound waves" pulsing out from the ear.
            ForEach(0..<3, id: \.self) { i in
                let phase = animate ? (t * 1.6 - Double(i) * 0.33).truncatingRemainder(dividingBy: 1) : 0.6
                // Arcs grow outward and stay centred on the ear.
                SoundArc(pixel: p * 0.7, height: 1 + i * 2)
                    .offset(x: p * (18.3 + Double(i) * 2.1), y: p * (top + 3.2 - Double(i) * 0.7))
                    .opacity(animate ? max(0.15, 1 - abs(phase - 0.5) * 1.6) : 0.8)
            }
        case .thinking(let t):
            // "…" dots that light up in turn above the head.
            ForEach(0..<3, id: \.self) { i in
                let lit = animate ? Int(t / 0.35) % 4 > i : true
                Rectangle()
                    .fill(PixelPalette.outline.opacity(lit ? 0.9 : 0.25))
                    .frame(width: p * 1.2, height: p * 1.2)
                    .offset(x: p * (12.5 + Double(i) * 2.2), y: p * (top - 2.5 - Double(i) * 0.9))
            }
        case .mug(let t):
            ZStack(alignment: .topLeading) {
                PixelImageView(image: PropSprites.mugImage, pixel: p * 0.8)
            }
            .offset(x: -p * 5.5, y: p * (top + 13 + (animate ? sin(t * 1.5) * 0.15 : 0)))
        }
    }
}

/// A small pixel bracket ")" used for the listening sound waves.
private struct SoundArc: View {
    let pixel: CGFloat
    let height: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<(height + 2), id: \.self) { row in
                let edge = row == 0 || row == height + 1
                Rectangle().fill(DP.water)
                    .frame(width: pixel, height: pixel)
                    .offset(x: edge ? 0 : pixel)
            }
        }
        .frame(width: pixel * 2, alignment: .leading)
    }
}

/// One falling confetti square (deterministic per index, so frames compare equal).
private struct ConfettiBit: View {
    let index: Int
    let age: TimeInterval
    let pixel: CGFloat
    private static let colors: [Color] = [.pink, .yellow, .mint, .orange, .purple, .cyan]

    var body: some View {
        let x = Double((index * 37) % 28) - 3
        let fall = (age * 7 + Double(index) * 1.7).truncatingRemainder(dividingBy: 16)
        let fade = max(0, 1 - age / PetViewModel.Reaction.celebrating.duration)
        Rectangle()
            .fill(Self.colors[index % Self.colors.count])
            .frame(width: pixel * 0.8, height: pixel * 0.8)
            .rotationEffect(.degrees(Double(index) * 40 + age * 180))
            .offset(x: pixel * x, y: pixel * (fall - 2))
            .opacity(fade)
    }
}

/// Observes only the driver, so frame changes don't re-evaluate the whole scene.
private struct PetStageHost: View {
    @ObservedObject var driver: PetAnimationDriver
    var body: some View { driver.stage }
}

// MARK: - Bubbles

/// Retro-styled speech bubble with a little tail. Adapts to light/dark.
struct SpeechBubble: View {
    var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(scheme == .dark ? Color.white : PixelPalette.outline)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(BubbleShape().fill(BubbleColors.fill(scheme)).shadow(color: .black.opacity(0.18), radius: 3, y: 1))
            .overlay(BubbleShape().stroke(BubbleColors.stroke(scheme), lineWidth: 2))
            .padding(.bottom, BubbleShape.tailHeight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }
}

enum BubbleColors {
    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.17, green: 0.15, blue: 0.14) : Color(red: 1, green: 0.99, blue: 0.96)
    }
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.62, blue: 0.3) : PixelPalette.outline
    }
}

/// A bubble with real buttons: reminders, phase changes, briefings.
struct CalloutBubble: View {
    var callout: PetCallout
    var onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: callout.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(callout.kind == .hydration ? DP.water : (callout.kind == .movement ? DP.mint : DP.accent))
                Text(callout.message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(scheme == .dark ? Color.white : PixelPalette.outline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
            if !callout.actions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(callout.actions) { action in
                        Button(action.title) { action.handler() }
                            .buttonStyle(CalloutButtonStyle(primary: action.isPrimary))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 228)
        .background(BubbleShape().fill(BubbleColors.fill(scheme)).shadow(color: .black.opacity(0.2), radius: 4, y: 1))
        .overlay(BubbleShape().stroke(BubbleColors.stroke(scheme), lineWidth: 2))
        .padding(.bottom, BubbleShape.tailHeight)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

struct CalloutButtonStyle: ButtonStyle {
    var primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(primary ? Color.white : DP.accent)
            .background(Capsule().fill(primary ? DP.accent : DP.accent.opacity(0.14)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
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

// MARK: - Bar & badge

/// Compact hover bar: Water · Focus · Chat · Capture · More.
private struct ActionBar: View {
    @ObservedObject var model: AppModel
    var actions: PetBarActions

    var body: some View {
        let timer = model.focusTimerState
        HStack(spacing: 4) {
            ActionButton(symbol: "drop.fill",
                         label: "Log \(model.hydrationSettings.defaultServingML) ml of water",
                         action: actions.logWater)
            ActionButton(symbol: timer == nil ? "timer" : (timer!.isRunning ? "pause.fill" : "play.fill"),
                         label: timer == nil ? "Start focus" : (timer!.isRunning ? "Pause timer" : "Resume timer"),
                         action: actions.toggleFocus)
            ActionButton(symbol: "bubble.left.and.text.bubble.right.fill", label: "Chat", action: actions.openChat)
            ActionButton(symbol: "square.and.pencil", label: "Quick capture", action: actions.openCapture)
            ActionButton(symbol: "mountain.2.fill", label: "Enter Focus World", action: actions.enterWorld)
            MoreButton(menu: actions.moreMenu)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? DP.accent.opacity(0.22) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering = $0 }
    }
}

/// "More" pops the full pet menu right under the button.
private struct MoreButton: NSViewRepresentable {
    var menu: () -> NSMenu?

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: "More")!,
                         target: context.coordinator, action: #selector(Coordinator.click(_:)))
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        b.toolTip = "More"
        b.setAccessibilityLabel("More options")
        return b
    }

    func updateNSView(_ b: NSButton, context: Context) { context.coordinator.menu = menu }
    func makeCoordinator() -> Coordinator { Coordinator(menu: menu) }

    final class Coordinator: NSObject {
        var menu: () -> NSMenu?
        init(menu: @escaping () -> NSMenu?) { self.menu = menu }
        @MainActor @objc func click(_ sender: NSButton) {
            guard let m = menu() else { return }
            m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        }
    }
}

/// Shown under the cat while a focus/break timer is active.
private struct FocusBadge: View {
    var timer: FocusTimer
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 5) {
                    Image(systemName: timer.phase.isBreak ? "cup.and.saucer.fill" : (timer.isRunning ? "timer" : "pause.fill"))
                    Text(CommandExecutor.clock(timer.remaining(at: ctx.date)))
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(.white)
                .background(Capsule().fill(timer.phase.isBreak ? DP.mint : DP.accent))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .accessibilityLabel("\(timer.phase.title), \(CommandExecutor.clock(timer.remaining(at: ctx.date))) remaining")
            }
        }
        .buttonStyle(.plain)
        .help("Open Focus")
    }
}
