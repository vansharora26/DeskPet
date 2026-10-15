import AppKit
import DeskPetCore

/// NSMenuItem that runs a closure — keeps menu wiring readable.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String? = nil, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// Builds the pet menus. Rebuilt on every open so titles and stats are current.
@MainActor
enum PetMenu {
    struct Actions {
        var togglePet: () -> Void
        var isPetVisible: () -> Bool
        var openSettings: () -> Void
        var openWelcome: () -> Void
        var resetPosition: () -> Void
    }

    /// Items shared by the right-click menu and the menu-bar menu.
    static func careItems(pet: PetViewModel) -> [NSMenuItem] {
        [
            ActionMenuItem("Pet \(pet.name)", symbol: "hand.wave.fill") { pet.pet() },
            ActionMenuItem("Feed", symbol: "fork.knife") { pet.feed() },
            ActionMenuItem("Play", symbol: "teddybear.fill") { pet.play() },
            pet.isSleeping
                ? ActionMenuItem("Wake Up", symbol: "sun.max.fill") { pet.toggleSleep() }
                : ActionMenuItem("Nap", symbol: "moon.zzz.fill") { pet.toggleSleep() },
        ]
    }

    static func statItems(pet: PetViewModel) -> [NSMenuItem] {
        let s = pet.stats
        func row(_ title: String, _ symbol: String, _ value: Double, invert: Bool = false) -> NSMenuItem {
            let shown = invert ? 100 - value : value
            let filled = Int((shown / 20).rounded())
            let bar = String(repeating: "▰", count: filled) + String(repeating: "▱", count: 5 - filled)
            let item = NSMenuItem(title: "\(title)  \(bar)  \(Int(value.rounded()))", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            item.isEnabled = false
            return item
        }
        let status = NSMenuItem(title: statusLine(pet), action: nil, keyEquivalent: "")
        status.isEnabled = false
        return [
            status,
            row("Happiness", "heart.fill", s.happiness),
            row("Energy", "bolt.fill", s.energy),
            row("Hunger", "fork.knife", s.hunger, invert: true),
        ]
    }

    static func statusLine(_ pet: PetViewModel) -> String {
        if pet.isSleeping { return "\(pet.name) is napping" }
        switch pet.stats.mood {
        case .happy: return "\(pet.name) is very happy"
        case .content: return "\(pet.name) is content"
        case .hungry: return "\(pet.name) is hungry"
        case .tired: return "\(pet.name) is sleepy"
        case .sad: return "\(pet.name) wants attention"
        }
    }

    /// Right-click menu on the pet itself.
    static func contextMenu(pet: PetViewModel, actions: Actions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        statItems(pet: pet).forEach(menu.addItem)
        menu.addItem(.separator())
        careItems(pet: pet).forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", symbol: "gearshape") { actions.openSettings() })
        menu.addItem(ActionMenuItem("Hide \(pet.name)", symbol: "eye.slash") { actions.togglePet() })
        return menu
    }

    /// Fills the menu-bar menu.
    static func populateStatusMenu(_ menu: NSMenu, pet: PetViewModel, actions: Actions) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let visible = actions.isPetVisible()
        menu.addItem(ActionMenuItem(visible ? "Hide \(pet.name)" : "Show \(pet.name)",
                                    symbol: visible ? "eye.slash" : "eye", key: "p") { actions.togglePet() })
        menu.addItem(ActionMenuItem("Bring \(pet.name) Back to Screen", symbol: "arrow.down.right.and.arrow.up.left") {
            actions.resetPosition()
        })
        menu.addItem(.separator())
        statItems(pet: pet).forEach(menu.addItem)
        menu.addItem(.separator())
        careItems(pet: pet).forEach(menu.addItem)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…", symbol: "gearshape", key: ",") { actions.openSettings() })
        menu.addItem(ActionMenuItem("Welcome Tour", symbol: "sparkles") { actions.openWelcome() })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit DeskPet", key: "q") { NSApp.terminate(nil) })
    }
}
