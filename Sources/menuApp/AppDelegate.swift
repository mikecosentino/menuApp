import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MenuAppStore()
    private lazy var settingsController = SettingsWindowController(store: store)

    /// The "home" status item that's always present (settings / add / quit).
    private var homeItem: NSStatusItem!
    /// Per-app status items keyed by app id.
    private var controllers: [UUID: StatusItemController] = [:]

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        buildHomeItem()
        reconcile(with: store.apps)

        // DispatchQueue.main (not RunLoop.main) so updates are delivered even while a
        // control is being tracked — e.g. live opacity changes while dragging the slider.
        store.$apps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.reconcile(with: apps)
            }
            .store(in: &cancellables)
    }

    // MARK: - Main menu

    /// Builds the application main menu. Without this, standard keyboard shortcuts
    /// like ⌘C/⌘V/⌘X/⌘A don't work in text fields (the Settings URL field), because
    /// the responder chain has no menu item defining those key equivalents.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // Application menu.
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit menuApp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (Cut/Copy/Paste/Select All target the first responder).
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu — shortcuts that act on the frontmost web window. Targeting
        // self (rather than the first responder) lets validateMenuItem gate them on
        // whether a web window is actually key, and show ✓ state for the toggles.
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let reloadItem = windowMenu.addItem(
            withTitle: "Reload", action: #selector(reloadFrontWindow(_:)), keyEquivalent: "r")
        reloadItem.target = self
        let theaterItem = windowMenu.addItem(
            withTitle: "Theater Mode", action: #selector(toggleFrontTheater(_:)), keyEquivalent: "t")
        theaterItem.target = self
        let muteItem = windowMenu.addItem(
            withTitle: "Mute Audio", action: #selector(toggleFrontMute(_:)), keyEquivalent: "m")
        muteItem.keyEquivalentModifierMask = [.command, .shift]
        muteItem.target = self
        windowMenu.addItem(.separator())
        let closeItem = windowMenu.addItem(
            withTitle: "Close Window", action: #selector(closeFrontWindow(_:)), keyEquivalent: "w")
        closeItem.target = self
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Frontmost-window commands

    /// The web window controller whose window is currently key, if any.
    private func frontWebController() -> WebWindowController? {
        controllers.values.map(\.webWindow).first(where: \.isKeyWindow)
    }

    @objc private func reloadFrontWindow(_ sender: Any?) { frontWebController()?.reload() }
    @objc private func toggleFrontTheater(_ sender: Any?) { frontWebController()?.toggleTheater() }
    @objc private func toggleFrontMute(_ sender: Any?) { frontWebController()?.toggleMute() }

    @objc private func closeFrontWindow(_ sender: Any?) {
        if let controller = frontWebController() {
            controller.hide()
        } else {
            NSApp.keyWindow?.performClose(sender) // e.g. the Settings window
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleFrontTheater(_:)):
            item.state = (frontWebController()?.isTheaterActive ?? false) ? .on : .off
            return frontWebController() != nil
        case #selector(toggleFrontMute(_:)):
            item.state = (frontWebController()?.isMuted ?? false) ? .on : .off
            return frontWebController() != nil
        case #selector(reloadFrontWindow(_:)):
            return frontWebController() != nil
        case #selector(closeFrontWindow(_:)):
            return NSApp.keyWindow != nil
        default:
            return true
        }
    }

    // MARK: - Home status item

    private func buildHomeItem() {
        homeItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = homeItem.button {
            let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "menuApp")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "menuApp"
        }

        let menu = NSMenu()

        let addItem = NSMenuItem(title: "Add Menu App…", action: #selector(addApp), keyEquivalent: "n")
        addItem.target = self
        menu.addItem(addItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit menuApp", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        homeItem.menu = menu
    }

    // MARK: - Reconciliation

    private func reconcile(with apps: [MenuApp]) {
        let incomingIds = Set(apps.map { $0.id })

        // Remove controllers for deleted apps.
        for (id, controller) in controllers where !incomingIds.contains(id) {
            controller.teardown()
            controllers.removeValue(forKey: id)
        }

        // Add or update controllers.
        for app in apps {
            if let existing = controllers[app.id] {
                existing.update(with: app)
            } else {
                let controller = StatusItemController(app: app)
                wire(controller)
                controllers[app.id] = controller
            }
        }
    }

    private func wire(_ controller: StatusItemController) {
        controller.onEdit = { [weak self] app in
            self?.settingsController.show(selecting: app.id)
        }
        controller.onRemove = { [weak self] app in
            self?.confirmRemove(app)
        }
        controller.onOpenSettings = { [weak self] in
            self?.settingsController.show()
        }
        controller.onAppChanged = { [weak self] app in
            self?.store.update(app)
        }
    }

    private func confirmRemove(_ app: MenuApp) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(app.name)”?"
        alert.informativeText = "This removes the menubar icon. You can add it again later in Settings."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            store.remove(app)
        }
    }

    // MARK: - Home menu actions

    @objc private func addApp() {
        let new = MenuApp(name: "New Site", urlString: "https://")
        store.add(new)
        settingsController.show(selecting: new.id)
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
