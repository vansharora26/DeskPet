import AppKit

/// The paw-print item in the menu bar. Its menu is rebuilt each time it opens,
/// so stats, timers and titles are always current.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let menu = NSMenu()
    private let pet: PetViewModel
    private let model: AppModel
    private let actions: PetMenu.Actions

    init(pet: PetViewModel, model: AppModel, actions: PetMenu.Actions) {
        self.pet = pet
        self.model = model
        self.actions = actions
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "DeskPet")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "DeskPet"
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        PetMenu.build(into: menu, pet: pet, model: model, actions: actions, includeAppItems: true)
    }
}
