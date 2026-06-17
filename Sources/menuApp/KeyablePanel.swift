import AppKit

/// A borderless panel that is allowed to become the key/main window.
///
/// Borderless `NSWindow`/`NSPanel` instances return `false` from `canBecomeKey`
/// by default, which prevents any text field (including those inside a WKWebView)
/// from receiving keyboard focus — clicks work, typing doesn't. Overriding these
/// restores normal keyboard input.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
