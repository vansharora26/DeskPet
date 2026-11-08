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
    var screenshot: () -> Void
    var copyText: () -> Void
    var pdfTools: () -> Void = {}
    /// Files dropped onto the cat.
    var dropFiles: ([URL]) -> Void = { _ in }
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
            .frame(width: min(layout.windowSize.width - 12, PetLayout.bubbleMaxWidth),
                   height: layout.bubbleAreaHeight(lifted: pet.reaction == .playing || pet.reaction == .celebrating),
                   alignment: .bottom)
            .padding(.leading, ((layout.windowSize.width - min(layout.windowSize.width - 12, PetLayout.bubbleMaxWidth)) / 2).rounded())
            .offset(x: windowState.isHovered && !windowState.isDragging ? layout.bubbleShift(for: windowState.spread) : 0)

            // Hover spread: labelled pills that fly out from behind the cat.
            ActionSpread(model: model, windowState: windowState, actions: actions, animate: animate,
                         shown: windowState.isHovered && !windowState.isDragging)

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
                onKey: onKey,
                onDropFiles: actions.dropFiles
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
                if !windowState.isHovered, let timer = model.focusTimerState, !windowState.isDragging {
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
        /// A little lightning bolt bobbing above the head while charging.
        case charging(t: TimeInterval)
        /// A blinking red empty battery above the head (critical battery).
        case lowBattery(t: TimeInterval)
    }

    let frame: PetFrame
    let props: Props
    let animate: Bool
    let pixel: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            CatCanvas(pose: frame.pose, pixel: pixel)
                .scaleEffect(x: frame.facingLeft ? -1 : 1, y: 1, anchor: UnitPoint(x: 9 / Double(CatSprite.width), y: 0.5))
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
                    PropView(kind: .heart, unit: p * 0.6)
                        .offset(x: p * (i % 2 == 0 ? -3.5 + Double(i) * 0.5 : 17.5),
                                y: p * (top + 6 - progress * 7))
                        .opacity(1 - progress)
                }
            }
        case .eating(let age):
            let eaten = animate ? min(1, age / PetViewModel.Reaction.eating.duration) : 0.3
            PropView(kind: .fish, unit: p * 0.85)
                .scaleEffect(x: -(1 - eaten * 0.85), y: 1 - eaten * 0.5, anchor: .trailing)
                .offset(x: -p * 8, y: p * (top + 8.5))
                .opacity(1 - eaten * 0.7)
        case .playing(let age):
            let bounce = animate ? abs(sin(age * .pi * 2.2 + .pi / 2)) : 0
            PropView(kind: .yarn, unit: p * 0.8)
                .rotationEffect(.degrees(animate ? age * 360 : 0))
                .offset(x: -p * (5 + sin(age * 3) * 1.5), y: p * (top + 15 - bounce * 7))
        case .confetti(let age):
            ForEach(0..<14, id: \.self) { i in
                ConfettiBit(index: i, age: age, pixel: p)
            }
        case .sip(let age):
            let progress = min(1, age / PetViewModel.Reaction.sipping.duration)
            // A droplet drifts down to the mouth and disappears.
            PropView(kind: .droplet, unit: p * 0.7)
                .offset(x: p * 7.3, y: p * (top + 5.5 + progress * 3.5))
                .opacity(1 - progress * progress)
        case .droplet(let t):
            PropView(kind: .droplet, unit: p * 0.8)
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
                Circle()
                    .fill(PixelPalette.outline.opacity(lit ? 0.9 : 0.25))
                    .frame(width: p * 1.2, height: p * 1.2)
                    .offset(x: p * (12.5 + Double(i) * 2.2), y: p * (top - 2.5 - Double(i) * 0.9))
            }
        case .mug(let t):
            ZStack(alignment: .topLeading) {
                PropView(kind: .mug, unit: p * 0.8)
            }
            .offset(x: -p * 5.5, y: p * (top + 13 + (animate ? sin(t * 1.5) * 0.15 : 0)))
        case .charging(let t):
            Image(systemName: "bolt.fill")
                .font(.system(size: p * 3.2, weight: .black))
                .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.15))
                .shadow(color: Color(red: 0.55, green: 0.35, blue: 0), radius: 0, x: p * 0.15, y: p * 0.15)
                .shadow(color: Color(red: 1, green: 0.85, blue: 0.3).opacity(0.7), radius: p * 0.8)
                .rotationEffect(.degrees(animate ? sin(t * 2.4) * 8 : 0))
                .offset(x: p * 17.6, y: p * (top - 3.2 + (animate ? sin(t * 2.4) * 0.4 : 0)))
        case .lowBattery(let t):
            let on = !animate || Int(t / 0.8) % 2 == 0
            Image(systemName: "battery.25percent")
                .font(.system(size: p * 3.8, weight: .bold))
                .foregroundStyle(Color(red: 0.9, green: 0.18, blue: 0.2))
                .padding(.horizontal, p * 0.5)
                .background(Capsule().fill(.white.opacity(0.85)))
                .opacity(on ? 1 : 0.4)
                .offset(x: p * 15.5, y: p * (top - 3.4))
        }
    }
}

/// A small ")" arc used for the listening sound waves.
private struct SoundArc: View {
    let pixel: CGFloat
    let height: Int

    var body: some View {
        let h = CGFloat(height + 2) * pixel
        Path { p in
            p.move(to: CGPoint(x: pixel * 0.5, y: pixel * 0.5))
            p.addQuadCurve(to: CGPoint(x: pixel * 0.5, y: h - pixel * 0.5), control: CGPoint(x: pixel * 2.6, y: h / 2))
        }
        .stroke(DP.water, style: StrokeStyle(lineWidth: pixel * 0.9, lineCap: .round))
        .frame(width: pixel * 2, height: h)
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
        RoundedRectangle(cornerRadius: pixel * 0.2)
            .fill(Self.colors[index % Self.colors.count])
            .frame(width: pixel * 1.1, height: pixel * 0.6)
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

/// Hover spread: labelled actions that spring out of the cat into two columns
/// (or one, near a screen edge) and tuck back in when the cursor leaves.
private struct ActionSpread: View {
    @ObservedObject var model: AppModel
    @ObservedObject var windowState: PetWindowState
    var actions: PetBarActions
    var animate: Bool
    var shown: Bool

    struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let help: String
        let tint: Color
        let action: () -> Void
    }

    private var items: [Item] {
        let timer = model.focusTimerState
        let focusTitle = timer == nil ? "Start focus" : (timer!.isRunning ? "Pause timer" : "Resume timer")
        let ml = model.hydrationSettings.defaultServingML
        return [
            Item(id: "water", symbol: "drop.fill", title: "Log \(ml) ml", help: "Log \(ml) ml of water (⌃⌥W)",
                 tint: Color(red: 0.25, green: 0.6, blue: 0.95), action: actions.logWater),
            Item(id: "focus", symbol: timer == nil ? "timer" : (timer!.isRunning ? "pause.fill" : "play.fill"),
                 title: focusTitle, help: focusTitle, tint: Color(red: 0.95, green: 0.55, blue: 0.2), action: actions.toggleFocus),
            Item(id: "world", symbol: "mountain.2.fill", title: "Focus World", help: "Enter a Focus World (⌃⌥F)",
                 tint: Color(red: 0.3, green: 0.72, blue: 0.4), action: actions.enterWorld),
            Item(id: "chat", symbol: "bubble.left.and.text.bubble.right.fill", title: "Chat", help: "Talk to your pet (⌃⌥C)",
                 tint: Color(red: 0.6, green: 0.45, blue: 0.95), action: actions.openChat),
            Item(id: "note", symbol: "note.text.badge.plus", title: "New note", help: "New note or task (⌃⌥N)",
                 tint: Color(red: 0.92, green: 0.72, blue: 0.15), action: actions.openCapture),
            Item(id: "shot", symbol: "camera.viewfinder", title: "Screenshot", help: "Screenshot an area (⌃⌥S)",
                 tint: Color(red: 0.15, green: 0.7, blue: 0.7), action: actions.screenshot),
            Item(id: "text", symbol: "text.viewfinder", title: "Copy text", help: "Copy text from the screen (⌃⌥T)",
                 tint: Color(red: 0.35, green: 0.45, blue: 0.9), action: actions.copyText),
            Item(id: "pdf", symbol: "doc.on.doc.fill", title: "PDF tools", help: "Convert, merge, compress… (or drop files on the cat)",
                 tint: Color(red: 0.9, green: 0.3, blue: 0.3), action: actions.pdfTools),
            Item(id: "more", symbol: "ellipsis", title: "More…", help: "Everything else",
                 tint: Color.gray, action: {
                     if let m = actions.moreMenu() { m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
                 }),
        ]
    }

    var body: some View {
        let list = items
        let layout = windowState.layout
        let frames = layout.spreadFrames(count: list.count, mode: windowState.spread)
        let origin = layout.bodyCenter
        let n = list.count
        ZStack(alignment: .topLeading) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                let f = frames[i]
                // Out: inner pills first; in: outer pills first.
                let order = Double(windowState.spread == .split ? i % ((n + 1) / 2) : i)
                SpreadPill(item: item)
                    .frame(width: f.width, height: f.height)
                    .scaleEffect(shown ? 1 : (animate ? 0.25 : 1))
                    .opacity(shown ? 1 : 0)
                    .position(x: shown || !animate ? f.midX : origin.x, y: shown || !animate ? f.midY : origin.y)
                    .animation(animate
                               ? .spring(response: 0.36, dampingFraction: 0.68).delay(shown ? order * 0.035 : (3 - min(order, 3)) * 0.02)
                               : .easeOut(duration: 0.15),
                               value: shown)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
            }
        }
        .frame(width: layout.windowSize.width, height: layout.windowSize.height, alignment: .topLeading)
        .onAppear { windowState.spreadCount = n }
    }
}

/// Bare button style: no system chrome, slight press feedback.
private struct SpreadPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
    }
}

private struct SpreadPill: View {
    let item: ActionSpread.Item
    @State private var hovering = false

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 7) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(item.tint.gradient))
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.leading, 3)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(item.tint.opacity(hovering ? 0.22 : 0)))
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.96)))
            // (Capsule strokes draw stray flat ends on some renderers; a rounded rectangle doesn't.)
            .overlay(RoundedRectangle(cornerRadius: PetLayout.pillSize.height / 2 - 0.5, style: .circular).inset(by: 0.5).stroke(hovering ? item.tint.opacity(0.8) : Color.primary.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(SpreadPillStyle())
        .compositingGroup()
        .shadow(color: .black.opacity(hovering ? 0.22 : 0.14), radius: hovering ? 5 : 3, y: 1)
        .foregroundStyle(.primary)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .help(item.help)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.help)
        .onHover { hovering = $0 }
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

