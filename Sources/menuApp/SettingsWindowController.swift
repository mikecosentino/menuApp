import AppKit
import SwiftUI

/// Hosts the SwiftUI settings view in a single reusable window.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: MenuAppStore
    private let selectionModel = SettingsSelection()
    private var window: NSWindow?

    init(store: MenuAppStore) {
        self.store = store
        super.init()
    }

    func show(selecting id: UUID? = nil) {
        if let id = id { selectionModel.id = id }
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(store: store, selectionModel: selectionModel))
            let win = NSWindow(contentViewController: hosting)
            win.title = "menuApp Settings"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 700, height: 460))
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            window = win
        }
        // Temporarily become a regular app so the settings window can take focus reliably.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back to a menubar-only app when settings close.
        NSApp.setActivationPolicy(.accessory)
    }
}
