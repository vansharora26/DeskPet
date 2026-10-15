import Foundation
import Testing
@testable import DeskPetCore

@Suite struct PetEngineTests {
    @Test func statsAreClamped() {
        var s = PetStats(happiness: 150, energy: -20, hunger: .nan)
        #expect(s.happiness == 100)
        #expect(s.energy == 0)
        #expect(s.hunger == 50)
        s.hunger = 500
        #expect(s.hunger == 100)
    }

    @Test func feedingReducesHunger() {
        var s = PetStats(happiness: 50, energy: 50, hunger: 60)
        #expect(PetEngine.feed(&s, sleeping: false) == .done)
        #expect(s.hunger < 60)
    }

    @Test func feedingRefusedWhenFull() {
        var s = PetStats(happiness: 50, energy: 50, hunger: 2)
        #expect(PetEngine.feed(&s, sleeping: false) == .refused(.tooFull))
        #expect(s.hunger == 2)
    }

    @Test func playingRaisesHappinessAndCostsEnergy() {
        var s = PetStats(happiness: 50, energy: 50, hunger: 20)
        #expect(PetEngine.play(&s, sleeping: false) == .done)
        #expect(s.happiness > 50)
        #expect(s.energy < 50)
    }

    @Test func playingRefusedWhenExhausted() {
        var s = PetStats(happiness: 50, energy: 5, hunger: 20)
        #expect(PetEngine.play(&s, sleeping: false) == .refused(.tooTired))
    }

    @Test func sleepingRestoresEnergy() {
        let s = PetStats(happiness: 50, energy: 20, hunger: 20)
        let after = PetEngine.advance(s, by: 60, sleeping: true)
        #expect(after.energy > s.energy)
    }

    @Test func awakeTimeDecaysGradually() {
        let s = PetStats(happiness: 80, energy: 80, hunger: 20)
        let after = PetEngine.advance(s, by: 60, sleeping: false)
        #expect(after.hunger > s.hunger)
        #expect(after.energy < s.energy)
        #expect(after.hunger - s.hunger < 1) // one minute is a small change
    }

    @Test func longAbsenceIsForgiving() {
        let s = PetStats(happiness: 90, energy: 90, hunger: 10)
        let after = PetEngine.advance(s, by: 7 * 24 * 3600, sleeping: false)
        #expect(after.happiness >= PetEngine.offlineFloorHappiness)
        #expect(after.energy >= PetEngine.offlineFloorEnergy)
        #expect(after.hunger <= PetEngine.offlineCeilingHunger)
    }

    @Test func absenceNeverImprovesStats() {
        let s = PetStats(happiness: 20, energy: 10, hunger: 90)
        let after = PetEngine.advance(s, by: 24 * 3600, sleeping: false)
        #expect(after.happiness <= 20)
        #expect(after.energy <= 10)
        #expect(after.hunger >= 90)
    }

    @Test func storeRoundTripsAndRecoversFromCorruption() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskPetTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PetStore(directory: dir)

        guard case .none = store.load() else { Issue.record("expected empty store"); return }

        let snap = PetSnapshot(name: "Tester", stats: PetStats(happiness: 11, energy: 22, hunger: 33))
        try store.save(snap)
        guard case .loaded(let loaded) = store.load() else { Issue.record("expected loaded"); return }
        #expect(loaded.name == "Tester")
        #expect(loaded.stats == snap.stats)

        try Data("not json".utf8).write(to: store.fileURL)
        guard case .recovered = store.load() else { Issue.record("expected recovery"); return }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }
}
