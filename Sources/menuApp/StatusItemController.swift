import AppKit

/// Owns one menubar status item and its associated web window.
final class StatusItemController: NSObject {
    private(set) var app: MenuApp
    private let statusItem: NSStatusItem
    private let windowController: WebWindowController

    /// The web window this status item drives (so the AppDelegate can route
    /// menu-bar shortcuts to it when it's frontmost).
    var webWindow: WebWindowController { windowController }

    /// Callbacks wired up by the AppDelegate.
    var onEdit: ((MenuApp) -> Void)?
    var onRemove: ((MenuApp) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onAppChanged: ((MenuApp) -> Void)?

    init(app: MenuApp) {
        self.app = app
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.windowController = WebWindowController(app: app)
        super.init()

        windowController.onAppChanged = { [weak self] updated in
            self?.app = updated
            self?.onAppChanged?(updated)
        }

        configureButton()
        refreshIcon()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = app.name
    }

    private func refreshIcon() {
        statusItem.button?.image = IconLoader.icon(for: app)
    }

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showMenu()
        } else {
            windowController.toggle(relativeTo: statusItem.button)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false // honor explicit isEnabled (e.g. Show Hidden Items)
        menu.addItem(withTitle: app.name, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Window", action: #selector(openWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let reloadItem = NSMenuItem(title: "Reload", action: #selector(reload), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)

        let undoHideItem = NSMenuItem(title: "Undo Last Hide", action: #selector(undoHide), keyEquivalent: "z")
        undoHideItem.target = self
        undoHideItem.isEnabled = windowController.hasHiddenSelectors
        menu.addItem(undoHideItem)

        let showHiddenItem = NSMenuItem(title: "Show All Hidden Items", action: #selector(showHidden), keyEquivalent: "")
        showHiddenItem.target = self
        showHiddenItem.isEnabled = windowController.hasHiddenSelectors
        menu.addItem(showHiddenItem)

        let editItem = NSMenuItem(title: "Edit…", action: #selector(edit), keyEquivalent: "")
        editItem.target = self
        menu.addItem(editItem)

        let removeItem = NSMenuItem(title: "Remove", action: #selector(remove), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit menuApp", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil // detach so left-click toggles the window again
    }

    // MARK: - Menu actions

    @objc private func openWindow() { windowController.show(relativeTo: statusItem.button) }
    @objc private func reload() { windowController.reload() }
    @objc private func undoHide() { windowController.undoLastHide() }
    @objc private func showHidden() { windowController.clearHiddenSelectors() }
    @objc private func edit() { onEdit?(app) }
    @objc private func remove() { onRemove?(app) }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Lifecycle

    func update(with newApp: MenuApp) {
        let iconNeedsRefresh = newApp.urlString != app.urlString || newApp.symbolName != app.symbolName
        app = newApp
        statusItem.button?.toolTip = newApp.name
        windowController.update(with: newApp)
        if iconNeedsRefresh { refreshIcon() }
    }

    func teardown() {
        windowController.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
