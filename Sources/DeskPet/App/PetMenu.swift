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
        var open: (Destination) -> Void
        var talk: () -> Void
        var openSettings: (SettingsTab) -> Void
        var openWelcome: () -> Void
        var resetPosition: () -> Void
        var keyboardMode: () -> Void
        var run: (AppCommand) -> Void
        /// Asks before discarding the current timer.
        var confirmStopFocus: () -> Void
    }

    private static func disabled(_ title: String, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        item.isEnabled = false
        return item
    }

    private static func submenu(_ title: String, symbol: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }

    static func statusLine(_ pet: PetViewModel) -> String {
        if pet.isSleeping { return "\(pet.name) is napping" }
        switch pet.mode {
        case .focused: return "\(pet.name) is focusing with you"
        case .resting: return "\(pet.name) is on a break"
        case .thirsty: return "\(pet.name) thinks it’s water time"
        case .listening: return "\(pet.name) is listening"
        case .thinking: return "\(pet.name) is thinking"
        case .speaking: return "\(pet.name) is talking"
        case .none: break
        }
        switch pet.stats.mood {
        case .happy: return "\(pet.name) is very happy"
        case .content: return "\(pet.name) is content"
        case .hungry: return "\(pet.name) is hungry"
        case .tired: return "\(pet.name) is sleepy"
        case .sad: return "\(pet.name) wants attention"
        }
    }

    /// The full menu, used for right-click, the "More" button and the menu bar.
    static func build(into menu: NSMenu, pet: PetViewModel, model: AppModel, actions a: Actions, includeAppItems: Bool) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        // Status
        menu.addItem(disabled(statusLine(pet), symbol: "pawprint.fill"))
        let s = model.hydrationSettings
        menu.addItem(disabled("Water: \(AppCommand.formatML(model.todayWaterML)) of \(AppCommand.formatML(s.dailyTargetML))", symbol: "drop"))
        if let t = model.focusTimerState {
            menu.addItem(disabled("\(t.phase.title): \(CommandExecutor.clock(t.remaining(at: Date()))) left\(t.isRunning ? "" : " (paused)")",
                                  symbol: "timer"))
        } else {
            let f = model.todayFocus
            menu.addItem(disabled("Focus: \(f.sessionsCompleted) of \(model.focusSettings.dailyGoalSessions) sessions today", symbol: "timer"))
        }
        menu.addItem(.separator())

        menu.addItem(ActionMenuItem("Talk to \(pet.name)…", symbol: "waveform") { a.talk() })
        menu.addItem(ActionMenuItem("Chat…", symbol: "bubble.left.and.text.bubble.right") { a.open(.chat) })
        menu.addItem(ActionMenuItem("Quick Capture…", symbol: "square.and.pencil") { a.open(.capture) })
        menu.addItem(ActionMenuItem("Command Launcher…", symbol: "command") { a.open(.launcher) })

        // Hydration
        var water: [NSMenuItem] = s.servingSizes.map { ml in
            ActionMenuItem("Log \(ml) ml", symbol: "drop.fill") { a.run(.logWater(ml: ml)) }
        }
        let undo = ActionMenuItem("Undo last entry", symbol: "arrow.uturn.backward") { a.run(.undoWater) }
        undo.isEnabled = !model.todayWaterEntries.isEmpty
        water += [undo, .separator(), ActionMenuItem("Water tracker…", symbol: "chart.bar") { a.open(.water) }]
        menu.addItem(submenu("Hydration", symbol: "drop", water))

        // Focus
        var focus: [NSMenuItem] = []
        if let t = model.focusTimerState {
            focus.append(t.isRunning
                ? ActionMenuItem("Pause", symbol: "pause.fill") { a.run(.pauseFocus) }
                : ActionMenuItem("Resume", symbol: "play.fill") { a.run(.resumeFocus) })
            focus.append(ActionMenuItem("Skip to end of \(t.phase.isBreak ? "break" : "session")", symbol: "forward.end") { a.run(.skipPhase) })
            focus.append(ActionMenuItem("Stop timer…", symbol: "stop.fill") { a.confirmStopFocus() })
        } else {
            let m = model.focusSettings.focusMinutes
            focus.append(ActionMenuItem("Start \(m)-minute focus", symbol: "timer") { a.run(.startFocus(minutes: nil, label: nil)) })
            if model.focusSettings.breaksEnabled {
                focus.append(ActionMenuItem("Start a break", symbol: "cup.and.saucer") { a.run(.startBreak(minutes: nil)) })
            }
        }
        focus += [.separator(), ActionMenuItem("Focus timer…", symbol: "chart.bar") { a.open(.focus) }]
        menu.addItem(submenu("Focus", symbol: "timer", focus))

        menu.addItem(ActionMenuItem("Tasks & Notes…", symbol: "checklist") { a.open(.tasks) })
        menu.addItem(ActionMenuItem("Today…", symbol: "sun.max") { a.open(.today) })
        menu.addItem(ActionMenuItem("Stats…", symbol: "chart.bar") { a.open(.stats) })
        menu.addItem(.separator())

        // Pet care
        let st = pet.stats
        menu.addItem(submenu("\(pet.name)", symbol: "pawprint", [
            disabled("Happiness \(Int(st.happiness)) · Energy \(Int(st.energy)) · Hunger \(Int(st.hunger))"),
            .separator(),
            ActionMenuItem("Pet", symbol: "hand.wave.fill") { pet.pet() },
            ActionMenuItem("Feed", symbol: "fork.knife") { pet.feed() },
            ActionMenuItem("Play", symbol: "teddybear.fill") { pet.play() },
            pet.isSleeping ? ActionMenuItem("Wake Up", symbol: "sun.max.fill") { pet.toggleSleep() }
                           : ActionMenuItem("Nap", symbol: "moon.zzz.fill") { pet.toggleSleep() },
            .separator(),
            ActionMenuItem("Control with Keyboard", symbol: "keyboard") { a.keyboardMode() },
            ActionMenuItem("Bring Back to Screen", symbol: "arrow.down.right.and.arrow.up.left") { a.resetPosition() },
            ActionMenuItem("Wardrobe…", symbol: "tshirt") { a.openSettings(.pet) },
        ]))

        menu.addItem(ActionMenuItem("Settings…", symbol: "gearshape", key: includeAppItems ? "," : "") { a.openSettings(.general) })
        let visible = a.isPetVisible()
        menu.addItem(ActionMenuItem(visible ? "Hide \(pet.name)" : "Show \(pet.name)",
                                    symbol: visible ? "eye.slash" : "eye") { a.togglePet() })
        if includeAppItems {
            menu.addItem(ActionMenuItem("Welcome Tour", symbol: "sparkles") { a.openWelcome() })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit DeskPet", key: includeAppItems ? "q" : "") { NSApp.terminate(nil) })
    }

    static func make(pet: PetViewModel, model: AppModel, actions: Actions) -> NSMenu {
        let menu = NSMenu()
        build(into: menu, pet: pet, model: model, actions: actions, includeAppItems: false)
        return menu
    }
}
