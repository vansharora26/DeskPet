import AppKit
import Combine
import DeskPetCore
import os

/// Owns the live pet: advances needs over time, runs actions, drives reaction
/// animations, speech and sound, and saves through PetStore. UI observes this.
@MainActor
final class PetViewModel: ObservableObject {

    /// A short-lived reaction animation that overrides the idle loop.
    enum Reaction: Equatable {
        case petted, eating, playing, waking, refused, celebrating, sipping
        var duration: TimeInterval {
            switch self {
            case .petted: return 1.6
            case .eating: return 2.4
            case .playing: return 2.6
            case .waking: return 1.2
            case .refused: return 1.0
            case .celebrating: return 2.8
            case .sipping: return 1.4
            }
        }
    }

    @Published private(set) var snapshot: PetSnapshot
    @Published private(set) var reaction: Reaction?
    @Published private(set) var reactionStart = Date()
    @Published private(set) var speech: String?
    @Published private(set) var lastSaveError: String?
    /// Ongoing state from the app (focus, break, reminder) — set by the coordinator.
    @Published var mode: PetMode = .none
    @Published var coat: CoatTheme = .ginger
    @Published var accessory: Accessory?
    /// An actionable bubble (reminder, phase change). Takes priority over speech.
    @Published private(set) var callout: PetCallout?
    private var calloutQueue: [PetCallout] = []
    /// Called when the user pets the cat (for small, capped XP).
    var onPetted: () -> Void = {}

    var stats: PetStats { snapshot.stats }
    var isSleeping: Bool { snapshot.isSleeping }
    var name: String { snapshot.name }

    private let store: PetStore
    private let settings: AppSettings
    private let sound: SoundPlayer
    private let log = Logger(subsystem: "app.deskpet.DeskPet", category: "pet")

    private var tickTimer: Timer?
    private var speechTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var recentPetTimes: [Date] = []
    private var lastChatter = Date()
    private var wakeObserver: NSObjectProtocol?
    private var savingDisabled = false

    static let tickInterval: TimeInterval = 20

    init(store: PetStore, settings: AppSettings, sound: SoundPlayer) {
        self.store = store
        self.settings = settings
        self.sound = sound

        let greeting: [String]
        switch store.load() {
        case .loaded(let saved):
            var s = saved
            let away = Date().timeIntervalSince(saved.lastUpdated)
            s.stats = PetEngine.advance(saved.stats, by: away, sleeping: saved.isSleeping)
            if s.isSleeping && PetEngine.shouldWake(s.stats) { s.isSleeping = false }
            s.lastUpdated = Date()
            snapshot = s
            greeting = away > PetEngine.offlineThreshold ? Speech.welcomeBack : []
        case .none:
            snapshot = PetSnapshot()
            greeting = Speech.firstHello
        case .recovered(let backup):
            snapshot = PetSnapshot()
            greeting = Speech.recovered
            log.error("Pet file was unreadable; backed up to \(backup?.path ?? "nowhere", privacy: .public)")
        }

        sound.isEnabled = { [weak settings] in settings?.soundEnabled ?? false }
        save()
        startTicking()

        if let line = greeting.randomElement() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.say(line) }
        }
    }

    // MARK: - Time

    private func startTicking() {
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 5 // let the system coalesce wake-ups
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        // After the Mac sleeps, catch up immediately (long gaps are handled gently).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(allowChatter: false) }
        }
    }

    /// Final save on quit.
    func shutdown() {
        tick(allowChatter: false)
        tickTimer?.invalidate()
        tickTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
    }

    /// Advances time, auto-wakes when rested, maybe chats, and saves.
    func tick(allowChatter: Bool = true) {
        let now = Date()
        let elapsed = now.timeIntervalSince(snapshot.lastUpdated)
        snapshot.stats = PetEngine.advance(snapshot.stats, by: elapsed, sleeping: snapshot.isSleeping)
        snapshot.lastUpdated = now

        if snapshot.isSleeping && PetEngine.shouldWake(snapshot.stats) {
            snapshot.isSleeping = false
            react(.waking)
            sound.play(.wake)
            say(Speech.wake.randomElement())
        } else if allowChatter {
            maybeChatter(now: now)
        }
        save()
    }

    private func maybeChatter(now: Date) {
        // Stay quiet while the user is focusing or a reminder is showing.
        guard settings.chattyEnabled, !snapshot.isSleeping, speech == nil, reaction == nil,
              callout == nil, mode != .focused else { return }
        // Roughly one remark every few minutes; sooner if the pet needs something.
        let mood = stats.mood
        let minGap: TimeInterval = (mood == .hungry || mood == .tired) ? 90 : 180
        guard now.timeIntervalSince(lastChatter) > minGap, Double.random(in: 0..<1) < 0.3 else { return }
        say(Speech.idle(for: mood).randomElement())
    }

    // MARK: - Actions

    func pet() {
        let now = Date()
        recentPetTimes = recentPetTimes.filter { now.timeIntervalSince($0) < 10 } + [now]
        sound.play(.pet)
        if snapshot.isSleeping {
            say(Speech.pettedAsleep.randomElement())
            return
        }
        PetEngine.pet(&snapshot.stats, recentPets: recentPetTimes.count - 1)
        onPetted()
        react(.petted)
        say((recentPetTimes.count >= 6 ? Speech.pettedSpam : Speech.petted).randomElement())
        commit()
    }

    func feed() {
        tick(allowChatter: false)
        switch PetEngine.feed(&snapshot.stats, sleeping: snapshot.isSleeping) {
        case .done:
            react(.eating)
            sound.play(.feed)
            say(Speech.fed.randomElement())
        case .refused(let why):
            refuse(why)
        }
        commit()
    }

    func play() {
        tick(allowChatter: false)
        switch PetEngine.play(&snapshot.stats, sleeping: snapshot.isSleeping) {
        case .done:
            react(.playing)
            sound.play(.play)
            say(Speech.played.randomElement())
        case .refused(let why):
            refuse(why)
        }
        commit()
    }

    /// Puts the pet down for a nap, or wakes it if already napping.
    func toggleSleep() {
        tick(allowChatter: false) // settle stats before switching modes
        if snapshot.isSleeping {
            snapshot.isSleeping = false
            react(.waking)
            sound.play(.wake)
            say((stats.energy >= 90 ? Speech.wake : Speech.wokenEarly).randomElement())
        } else {
            snapshot.isSleeping = true
            reactionTask?.cancel()
            reaction = nil
            sound.play(.sleep)
            say(Speech.sleep.randomElement())
        }
        commit()
    }

    func rename(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != snapshot.name else { return }
        snapshot.name = String(trimmed.prefix(24))
        commit()
    }

    /// Starts over with a fresh pet (keeps the name).
    func reset() {
        snapshot = PetSnapshot(name: snapshot.name)
        reactionTask?.cancel()
        reaction = nil
        commit()
        say(Speech.firstHello.randomElement())
    }

    private func refuse(_ why: PetEngine.Refusal) {
        react(.refused)
        sound.play(.refuse)
        switch why {
        case .tooFull: say(Speech.tooFull.randomElement())
        case .tooTired: say(Speech.tooTired.randomElement())
        case .asleep: say(Speech.asleepRefusal.randomElement())
        }
    }

    // MARK: - Reactions & speech

    func react(_ r: Reaction) {
        reaction = r
        reactionStart = Date()
        reactionTask?.cancel()
        reactionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(r.duration))
            guard !Task.isCancelled else { return }
            self?.reaction = nil
        }
    }

    func say(_ line: String?) {
        guard let line else { return }
        speech = line
        lastChatter = Date()
        speechTask?.cancel()
        let duration = min(6, 2.4 + Double(line.count) * 0.05)
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.speech = nil
        }
    }

    // MARK: - Callouts

    /// Shows an actionable bubble. A newer callout of the same kind replaces the
    /// old one (no duplicate reminders); different kinds queue up.
    func show(_ c: PetCallout) {
        if callout?.kind == c.kind || callout == nil {
            callout = c
        } else {
            calloutQueue.removeAll { $0.kind == c.kind }
            calloutQueue.append(c)
        }
    }

    /// Removes a callout (by kind) whether it's showing or queued.
    func clearCallout(kind: PetCallout.Kind) {
        calloutQueue.removeAll { $0.kind == kind }
        if callout?.kind == kind { advanceCallouts() }
    }

    func clearCallout(id: UUID) {
        calloutQueue.removeAll { $0.id == id }
        if callout?.id == id { advanceCallouts() }
    }

    private func advanceCallouts() {
        callout = calloutQueue.isEmpty ? nil : calloutQueue.removeFirst()
    }

    func chime(_ effect: SoundPlayer.Effect) { sound.play(effect) }

    /// "Delete all data": remove the saved pet and stop writing it until relaunch.
    func eraseAndStopSaving() {
        savingDisabled = true
        tickTimer?.invalidate()
        store.delete()
    }

    /// Small, positive effect of real habits on the pet's needs.
    func boost(happiness: Double = 0, energy: Double = 0, hunger: Double = 0) {
        guard !snapshot.isSleeping else { return }
        snapshot.stats.happiness += happiness
        snapshot.stats.energy += energy
        snapshot.stats.hunger += hunger
        commit()
    }

    // MARK: - Persistence

    private func commit() {
        snapshot.lastUpdated = Date()
        save()
    }

    private func save() {
        guard !savingDisabled else { return }
        do {
            try store.save(snapshot)
            lastSaveError = nil
        } catch {
            // Keep running in memory; surface the problem in Settings rather than nagging.
            if lastSaveError == nil { log.error("Save failed: \(error.localizedDescription, privacy: .public)") }
            lastSaveError = error.localizedDescription
        }
    }
}
