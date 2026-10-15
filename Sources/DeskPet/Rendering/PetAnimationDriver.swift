import AppKit
import Combine

/// Drives the pet's animation cheaply: a plain timer evaluates PetAnimator at
/// a frame rate suited to what's happening, and publishes a new frame only
/// when it actually differs. At idle that's ~1–2 SwiftUI updates per second;
/// while hidden or with animations off, the timer doesn't run at all.
@MainActor
final class PetAnimationDriver: ObservableObject {
    @Published private(set) var stage: PetStage

    private let pet: PetViewModel
    private let windowState: PetWindowState
    private let settings: AppSettings
    private var timer: Timer?
    private var timerFPS: Double = 0
    private var cancellables = Set<AnyCancellable>()

    init(pet: PetViewModel, windowState: PetWindowState, settings: AppSettings) {
        self.pet = pet
        self.windowState = windowState
        self.settings = settings
        stage = PetStage(frame: PetFrame(), props: .none, animate: false, pixel: windowState.layout.pixel)

        // Re-evaluate right away when any input changes (after the change lands).
        Publishers.MergeMany(
            pet.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            windowState.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
                .map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)

        refresh()
    }

    private var animate: Bool { settings.effectiveAnimations }

    /// Frame rate for the current activity; 0 means no timer needed.
    private var desiredFPS: Double {
        guard animate, windowState.isVisible else { return 0 }
        if pet.reaction != nil { return 15 }  // hops, hearts, chewing
        if pet.isSleeping { return 10 }       // drifting z's
        if pet.mode == .thirsty || pet.mode == .resting { return 8 } // bobbing droplet, steam
        return 6                              // blinks & tail swish (blinks outlast a frame)
    }

    private func refresh() {
        updateTimer()
        render()
    }

    private func updateTimer() {
        let fps = desiredFPS
        guard fps != timerFPS else { return }
        timer?.invalidate()
        timer = nil
        timerFPS = fps
        guard fps > 0 else { return }
        let t = Timer(timeInterval: 1 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        t.tolerance = 0.2 / fps
        RunLoop.main.add(t, forMode: .common) // keep animating during drags & menus
        timer = t
    }

    private func render() {
        let now = Date()
        let t = now.timeIntervalSinceReferenceDate
        let age = max(0, now.timeIntervalSince(pet.reactionStart))
        let frame = PetAnimator.frame(at: t, .init(
            reaction: pet.reaction, reactionAge: age, sleeping: pet.isSleeping,
            mood: pet.stats.mood, mode: pet.mode, hovered: windowState.isHovered, animate: animate,
            coat: pet.coat, accessory: pet.accessory))

        let props: PetStage.Props
        let a = animate ? age : 0.4
        let loop = animate ? t : 0
        if pet.isSleeping {
            props = .sleeping(t: loop)
        } else {
            switch pet.reaction {
            case .petted: props = .petted(age: a)
            case .eating: props = .eating(age: a)
            case .playing: props = .playing(age: a)
            case .celebrating: props = .confetti(age: a)
            case .sipping: props = .sip(age: a)
            default:
                switch pet.mode {
                case .thirsty: props = .droplet(t: loop)
                case .resting: props = .mug(t: loop)
                default: props = .none
                }
            }
        }
        let next = PetStage(frame: frame, props: props, animate: animate, pixel: windowState.layout.pixel)
        if next != stage { stage = next }
    }
}
