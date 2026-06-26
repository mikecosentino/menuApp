import AppKit
import WebKit

/// Manages the floating, draggable, iPhone-sized window that displays a website.
final class WebWindowController: NSObject, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {

    private(set) var app: MenuApp
    private var panel: NSPanel!
    private var webView: WKWebView!
    private var titleLabel: NSTextField!
    private var loadedURL: URL?

    private let headerHeight: CGFloat = 30

    init(app: MenuApp) {
        self.app = app
        super.init()
        buildWindow()
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: - Construction

    private func buildWindow() {
        let size = clampedSize()
        let contentRect = NSRect(x: 0, y: 0, width: size.width, height: size.height + headerHeight)

        panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = app.alwaysOnTop ? .floating : .normal
        panel.minSize = NSSize(width: 240, height: 230)
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.alphaValue = CGFloat(app.opacity)

        let container = NSView(frame: contentRect)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = container

        buildHeader(in: container, size: contentRect.size)
        buildWebView(in: container, size: size)
    }

    private func buildHeader(in container: NSView, size: NSSize) {
        let header = DragHandleView(frame: NSRect(
            x: 0, y: size.height - headerHeight, width: size.width, height: headerHeight))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        header.autoresizingMask = [.width, .minYMargin]
        container.addSubview(header)

        // Left-aligned button row, in order.
        func leftButton(at index: Int, symbol: String, action: Selector, tip: String) -> NSButton {
            let b = makeButton(symbol: symbol, action: action)
            b.frame = NSRect(x: 8 + CGFloat(index) * 24, y: (headerHeight - 18) / 2, width: 18, height: 18)
            b.autoresizingMask = [.maxXMargin]
            b.toolTip = tip
            header.addSubview(b)
            return b
        }

        // Right-aligned button row; index 0 is the rightmost button.
        func rightButton(at index: Int, symbol: String, action: Selector, tip: String) -> NSButton {
            let b = makeButton(symbol: symbol, action: action)
            b.frame = NSRect(x: size.width - 26 - CGFloat(index) * 24, y: (headerHeight - 18) / 2, width: 18, height: 18)
            b.autoresizingMask = [.minXMargin]
            b.toolTip = tip
            header.addSubview(b)
            return b
        }

        // Close (leftmost — macOS-style left placement)
        _ = leftButton(at: 0, symbol: "xmark", action: #selector(hide), tip: "Close")

        // Back
        let back = leftButton(at: 1, symbol: "chevron.backward", action: #selector(goBack), tip: "Back")
        back.isEnabled = false
        self.backButton = back

        // Home (loads the app's configured URL)
        _ = leftButton(at: 2, symbol: "house", action: #selector(goHome), tip: "Home")

        // Reload
        _ = leftButton(at: 3, symbol: "arrow.clockwise", action: #selector(reload), tip: "Reload")

        // Pin toggle (rightmost)
        let pin = rightButton(
            at: 0,
            symbol: app.pinnedOpen ? "pin.fill" : "pin",
            action: #selector(togglePin(_:)),
            tip: "Keep window open when it loses focus")
        self.pinButton = pin

        // Always-on-top toggle (left of pin)
        let onTop = rightButton(
            at: 1,
            symbol: app.alwaysOnTop ? "arrow.up.square.fill" : "arrow.up.square",
            action: #selector(toggleAlwaysOnTop(_:)),
            tip: "Keep window above other windows")
        self.alwaysOnTopButton = onTop

        // Title (centered in the space between the left and right button rows)
        titleLabel = NSTextField(labelWithString: app.name)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 104, y: (headerHeight - 16) / 2, width: size.width - 160, height: 16)
        titleLabel.autoresizingMask = [.width]
        header.addSubview(titleLabel)
    }

    private var pinButton: NSButton?
    private var alwaysOnTopButton: NSButton?
    private var backButton: NSButton?

    private func buildWebView(in container: NSView, size: NSSize) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        webView = WKWebView(frame: frame, configuration: config)
        webView.customUserAgent = app.resolvedUserAgent
        webView.autoresizingMask = [.width, .height]
        webView.uiDelegate = self
        webView.navigationDelegate = self
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        container.addSubview(webView)

        // Resize grip, bottom-right.
        let grip = ResizeGripView(frame: NSRect(x: size.width - 16, y: 0, width: 16, height: 16))
        grip.minSize = panel.minSize
        grip.autoresizingMask = [.minXMargin, .maxYMargin]
        container.addSubview(grip)
    }

    private func makeButton(symbol: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    // MARK: - Public API

    /// Shows the window, positioning it under `statusButton` unless the user has moved it before.
    func show(relativeTo statusButton: NSStatusBarButton?) {
        ensureLoaded()
        // Size comes from the model; position is remembered separately (or placed under the icon).
        resizeWindow()
        if let origin = savedOrigin() {
            panel.setFrameOrigin(clampOrigin(origin))
        } else if let button = statusButton {
            positionUnder(button)
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if panel.isVisible {
            hide()
        } else {
            show(relativeTo: statusButton)
        }
    }

    @objc func hide() {
        panel.orderOut(nil)
    }

    @objc func reload() {
        if loadedURL == nil { ensureLoaded() } else { webView.reload() }
    }

    @objc private func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    /// Navigates to the app's configured URL.
    @objc private func goHome() {
        guard let url = app.url else { return }
        loadedURL = url
        webView.load(URLRequest(url: url))
    }

    @objc private func togglePin(_ sender: NSButton) {
        app.pinnedOpen.toggle()
        let symbol = app.pinnedOpen ? "pin.fill" : "pin"
        sender.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        onAppChanged?(app)
    }

    @objc private func toggleAlwaysOnTop(_ sender: NSButton) {
        app.alwaysOnTop.toggle()
        let symbol = app.alwaysOnTop ? "arrow.up.square.fill" : "arrow.up.square"
        sender.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        panel.level = app.alwaysOnTop ? .floating : .normal
        onAppChanged?(app)
    }

    /// Called when the user changes a setting from the window chrome, so the store can persist it.
    var onAppChanged: ((MenuApp) -> Void)?

    /// Updates configuration when the app is edited in Settings.
    func update(with newApp: MenuApp) {
        let urlChanged = newApp.urlString != app.urlString
        let sizeChanged = newApp.width != app.width || newApp.height != app.height
        let uaChanged = newApp.resolvedUserAgent != app.resolvedUserAgent
        app = newApp
        titleLabel.stringValue = newApp.name
        pinButton?.image = NSImage(
            systemSymbolName: newApp.pinnedOpen ? "pin.fill" : "pin", accessibilityDescription: nil)
        alwaysOnTopButton?.image = NSImage(
            systemSymbolName: newApp.alwaysOnTop ? "arrow.up.square.fill" : "arrow.up.square",
            accessibilityDescription: nil)
        if sizeChanged { resizeWindow() }
        panel.alphaValue = CGFloat(newApp.opacity)
        panel.level = newApp.alwaysOnTop ? .floating : .normal
        if uaChanged { webView.customUserAgent = newApp.resolvedUserAgent }
        if urlChanged || uaChanged {
            loadedURL = nil
            if panel.isVisible { ensureLoaded() }
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.delegate = nil
    }

    // MARK: - Loading

    private func ensureLoaded() {
        guard let url = app.url else { return }
        if loadedURL == url { return }
        loadedURL = url
        webView.load(URLRequest(url: url))
    }

    // MARK: - Positioning

    private func positionUnder(_ button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { panel.center(); return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var x = buttonFrame.midX - size.width / 2
        let y = buttonFrame.minY - size.height - 4

        // Keep the window on-screen horizontally.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func clampedSize() -> NSSize {
        var width = CGFloat(app.width)
        var height = CGFloat(app.height)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            width = min(width, visible.width - 16)
            height = min(height, visible.height - headerHeight - 16)
        }
        return NSSize(width: width, height: height)
    }

    private func resizeWindow() {
        let size = clampedSize()
        var frame = panel.frame
        frame.size = NSSize(width: size.width, height: size.height + headerHeight)
        panel.setFrame(frame, display: true)
    }

    // MARK: - Position persistence (per app id, in UserDefaults).
    // Size lives in the model (so it shows in Settings); only the position is stored here.

    private var positionKey: String { "window.origin.\(app.id.uuidString)" }

    private func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: positionKey + ".x") != nil else { return nil }
        return NSPoint(x: defaults.double(forKey: positionKey + ".x"),
                       y: defaults.double(forKey: positionKey + ".y"))
    }

    private func saveOrigin() {
        let origin = panel.frame.origin
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x), forKey: positionKey + ".x")
        defaults.set(Double(origin.y), forKey: positionKey + ".y")
    }

    /// Keeps an origin on-screen (e.g. if the display layout changed since it was saved).
    private func clampOrigin(_ origin: NSPoint) -> NSPoint {
        guard let screen = NSScreen.main else { return origin }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        return NSPoint(
            x: max(visible.minX, min(origin.x, visible.maxX - size.width)),
            y: max(visible.minY, min(origin.y, visible.maxY - size.height)))
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        saveOrigin()
    }

    func windowDidResize(_ notification: Notification) {
        saveOrigin()
        // Reflect the manual resize back into the model so Settings shows the live size.
        let newWidth = Double(panel.frame.width)
        let newHeight = Double(panel.frame.height) - Double(headerHeight)
        if abs(newWidth - app.width) > 0.5 || abs(newHeight - app.height) > 0.5 {
            app.width = newWidth
            app.height = newHeight
            onAppChanged?(app)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Popover behavior: close on focus loss unless pinned.
        if !app.pinnedOpen {
            hide()
        }
    }

    // MARK: - WKUIDelegate (handle target=_blank by loading in place)

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    // MARK: - WKNavigationDelegate (keep the Back button in sync)

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        backButton?.isEnabled = webView.canGoBack
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        backButton?.isEnabled = webView.canGoBack
    }
}
