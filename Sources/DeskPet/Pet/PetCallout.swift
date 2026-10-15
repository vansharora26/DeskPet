import Foundation

/// An actionable speech bubble: a reminder or prompt with real buttons.
struct PetCallout: Identifiable, Equatable {
    enum Kind: Equatable {
        case hydration, movement, task(UUID), focusPhase, briefing, endOfDay, info
    }

    struct Action: Identifiable {
        let id = UUID()
        var title: String
        var isPrimary = false
        var handler: @MainActor () -> Void
    }

    let id = UUID()
    var kind: Kind
    /// SF Symbol name.
    var symbol: String
    var message: String
    var actions: [Action]
    /// Called when the user closes the bubble with ×.
    var onDismiss: (@MainActor () -> Void)?

    static func == (a: PetCallout, b: PetCallout) -> Bool { a.id == b.id }
}
