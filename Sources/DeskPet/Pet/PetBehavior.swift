import AppKit
import Combine
import DeskPetCore

/// Connects the pet's expressions to real app state. Every reaction here is
/// triggered by something the user actually did or that DeskPet recorded —
/// never by guessing at activity it can't observe.
@MainActor
final class PetBehavior {
    private let model: AppModel
    private let pet: PetViewModel
    private let router: WindowRouter
    private let notifications: NotificationManager
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel, pet: PetViewModel, router: WindowRouter, notifications: NotificationManager) {
        self.model = model
        self.pet = pet
        self.router = router
        self.notifications = notifications
    }

    func start() {
        pet.onPetted = { [weak model] in model?.notePetting() }

        model.events
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.handle($0) }
            .store(in: &cancellables)

        // Ongoing mode: focus headband, break mug, thirsty droplet.
        Publishers.CombineLatest(model.$data.map(\.focus.timer).removeDuplicates(), pet.$callout.map { $0?.kind })
            .receive(on: RunLoop.main)
            .sink { [weak self] timer, callout in self?.updateMode(timer: timer, callout: callout) }
            .store(in: &cancellables)

        // Appearance from the wardrobe (only items the user has unlocked).
        model.$data.map(\.progression).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] p in
                guard let self else { return }
                self.pet.coat = p.isUnlocked(p.coat) ? p.coat : .ginger
                self.pet.accessory = p.accessory.flatMap { p.isUnlocked($0) ? $0 : nil }
            }
            .store(in: &cancellables)
    }

    private func updateMode(timer: FocusTimer?, callout: PetCallout.Kind?) {
        let mode: PetMode
        if callout == .hydration { mode = .thirsty }
        else if let t = timer, t.isRunning { mode = t.phase.isBreak ? .resting : .focused }
        else { mode = .none }
        if pet.mode != mode { pet.mode = mode }
    }

    private func handle(_ event: AppEvent) {
        switch event {
        case .waterLogged(_, _, let goal):
            pet.clearCallout(kind: .hydration)
            notifications.remove(id: "deskpet.hydration")
            pet.react(.sipping)
            pet.chime(.feed)
            pet.say(Speech.waterLogged.randomElement())
            pet.boost(happiness: 2)
            if goal {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.pet.react(.celebrating)
                    self?.pet.say(Speech.waterGoal.randomElement())
                }
            }

        case .waterUndone:
            pet.say("Undone — no worries.")

        case .focusStarted(let phase, _):
            pet.clearCallout(kind: .focusPhase)
            pet.say((phase.isBreak ? Speech.breakStarted : Speech.focusStarted).randomElement())

        case .focusPaused:
            pet.say("Paused. I’ll hold your spot.")

        case .focusResumed:
            pet.say("Back at it!")

        case .focusStopped:
            pet.clearCallout(kind: .focusPhase)

        case .phaseCompleted(let record, let next):
            handlePhase(record, next: next)

        case .itemCreated:
            pet.say(Speech.saved.randomElement())

        case .taskCompleted:
            pet.react(.petted)
            pet.chime(.play)
            pet.say(Speech.taskDone.randomElement())
            pet.boost(happiness: 1)

        case .movementDone:
            pet.say(Speech.movementDone.randomElement())

        case .leveledUp(let level):
            pet.react(.celebrating)
            let unlocked = Accessory.allCases.filter { $0.unlockLevel == level }.map(\.title)
                + CoatTheme.allCases.filter { $0.unlockLevel == level }.map { "\($0.title) coat" }
            let message = unlocked.isEmpty ? "Level \(level)! Thanks for hanging out with me."
                                           : "Level \(level)! You unlocked: \(unlocked.joined(separator: ", "))."
            pet.show(PetCallout(kind: .info, symbol: "star.fill", message: message,
                                actions: unlocked.isEmpty ? [] : [.init(title: "Wardrobe", isPrimary: true) { [weak self] in
                                    self?.pet.clearCallout(kind: .info)
                                    self?.router.openSettings(.pet)
                                }]))

        case .milestone(let m):
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                self?.pet.say("Milestone: \(m.title)! ⭐")
            }
        }
    }

    private func handlePhase(_ record: FocusRecord, next: FocusPhase?) {
        let settings = model.focusSettings
        if record.phase == .focus {
            pet.react(.celebrating)
            pet.chime(.play)
            pet.say(Speech.focusDone.randomElement())
            pet.boost(happiness: 4)
            if next == nil && settings.breaksEnabled {
                let phase = model.data.focus.suggestedNextPhase(now: Date())
                let minutes = settings.minutes(for: phase == .focus ? .shortBreak : phase)
                pet.show(PetCallout(kind: .focusPhase, symbol: "cup.and.saucer.fill",
                                    message: "Session complete! Take a \(minutes)-minute break?",
                                    actions: [
                                        .init(title: "Start break", isPrimary: true) { [weak self] in
                                            try? self?.model.startFocus(phase == .focus ? .shortBreak : phase)
                                        },
                                        .init(title: "Not now") { [weak self] in self?.pet.clearCallout(kind: .focusPhase) },
                                    ]))
            }
        } else {
            pet.boost(energy: 3)
            if next == nil {
                pet.show(PetCallout(kind: .focusPhase, symbol: "timer",
                                    message: "Break’s over. Ready for another round?",
                                    actions: [
                                        .init(title: "Start focus", isPrimary: true) { [weak self] in try? self?.model.startFocus(.focus) },
                                        .init(title: "Later") { [weak self] in self?.pet.clearCallout(kind: .focusPhase) },
                                    ]))
            } else {
                pet.say(Speech.breakDone.randomElement())
            }
        }
    }
}
