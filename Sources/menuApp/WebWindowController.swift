import AppKit
import WebKit

/// Breaks the WKUserContentController -> handler -> controller retain cycle.
/// WKUserContentController strongly retains its message handlers, so handing it
/// the WebWindowController directly would leak the window and its web view.
final class WeakScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ ucc: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(ucc, didReceive: message)
    }
}

/// Manages the floating, draggable, iPhone-sized window that displays a website.
final class WebWindowController: NSObject, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    private(set) var app: MenuApp
    private var panel: NSPanel!
    private var container: NSView!
    private var webView: WKWebView!
    private var headerView: DragHandleView!
    private var hoverReveal: HoverRevealView?
    private var contentController: WKUserContentController!
    private var titleLabel: NSTextField!
    private var loadedURL: URL?

    /// Suppresses the reconcile echo: saving a hidden selector round-trips through
    /// the store and calls `update(with:)` back on this controller. Without this
    /// guard that would reload the page (and kill video playback) on every hide.
    private var isApplyingLocalEdit = false

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
        self.container = container

        // Web view first so the header (and its hover-reveal overlay) sit above it
        // when the toolbar is configured to auto-hide over the page.
        buildWebView(in: container, size: size)
        buildHeader(in: container, size: contentRect.size)
        applyToolbarMode()
    }

    private func buildHeader(in container: NSView, size: NSSize) {
        let header = DragHandleView(frame: NSRect(
            x: 0, y: size.height - headerHeight, width: size.width, height: headerHeight))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        header.autoresizingMask = [.width, .minYMargin]
        container.addSubview(header)
        self.headerView = header

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

        // Hide-elements toggle (left of always-on-top)
        let pick = rightButton(
            at: 2,
            symbol: "eye.slash",
            action: #selector(toggleHideMode(_:)),
            tip: "Hide elements — click items to hide, Esc to finish")
        self.pickButton = pick

        // Theater mode toggle (left of the eye)
        let theater = rightButton(
            at: 3,
            symbol: "play.rectangle",
            action: #selector(toggleTheater(_:)),
            tip: "Theater mode — isolate the video and expand it to full width")
        self.theaterButton = theater

        // Mute toggle (left of theater)
        let mute = rightButton(
            at: 4,
            symbol: app.muted ? "speaker.slash.fill" : "speaker.wave.2",
            action: #selector(toggleMute(_:)),
            tip: "Mute this window's audio")
        self.muteButton = mute

        // Title (centered in the space between the left and right button rows)
        titleLabel = NSTextField(labelWithString: app.name)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 104, y: (headerHeight - 16) / 2, width: size.width - 232, height: 16)
        titleLabel.autoresizingMask = [.width]
        header.addSubview(titleLabel)
    }

    private var pinButton: NSButton?
    private var alwaysOnTopButton: NSButton?
    private var backButton: NSButton?
    private var pickButton: NSButton?
    private var pickActive = false
    private var theaterButton: NSButton?
    private var theaterActive = false
    private var muteButton: NSButton?

    private func buildWebView(in container: NSView, size: NSSize) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let ucc = WKUserContentController()
        self.contentController = ucc
        installUserScripts(into: ucc)
        ucc.add(WeakScriptMessageProxy(self), name: "menuAppHide")
        config.userContentController = ucc

        let frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        webView = WKWebView(frame: frame, configuration: config)
        webView.customUserAgent = app.resolvedUserAgent
        applyMuted(app.muted)
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

    @objc private func toggleMute(_ sender: NSButton) {
        app.muted.toggle()
        sender.image = NSImage(
            systemSymbolName: app.muted ? "speaker.slash.fill" : "speaker.wave.2",
            accessibilityDescription: nil)
        applyMuted(app.muted)
        onAppChanged?(app)
    }

    /// Mutes or unmutes all audio in the web view at the page level (covers both
    /// HTML media elements and the Web Audio API). Uses WebKit's `_setPageMuted:`
    /// with the `_WKMediaAudioMuted` (1) bit; no-ops if the runtime lacks it.
    private func applyMuted(_ muted: Bool) {
        let sel = NSSelectorFromString("_setPageMuted:")
        guard webView.responds(to: sel) else { return }
        typealias MuteFn = @convention(c) (NSObject, Selector, UInt) -> Void
        let imp = webView.method(for: sel)
        let fn = unsafeBitCast(imp, to: MuteFn.self)
        fn(webView, sel, muted ? 1 : 0)
    }

    /// Called when the user changes a setting from the window chrome, so the store can persist it.
    var onAppChanged: ((MenuApp) -> Void)?

    /// Updates configuration when the app is edited in Settings.
    func update(with newApp: MenuApp) {
        let urlChanged = newApp.urlString != app.urlString
        let sizeChanged = newApp.width != app.width || newApp.height != app.height
        let uaChanged = newApp.resolvedUserAgent != app.resolvedUserAgent
        let selectorsChanged = newApp.hiddenSelectors != app.hiddenSelectors
        let mutedChanged = newApp.muted != app.muted
        let toolbarModeChanged = newApp.autoHideToolbar != app.autoHideToolbar
        let wasLocalEdit = isApplyingLocalEdit
        isApplyingLocalEdit = false
        app = newApp
        titleLabel.stringValue = newApp.name
        muteButton?.image = NSImage(
            systemSymbolName: newApp.muted ? "speaker.slash.fill" : "speaker.wave.2",
            accessibilityDescription: nil)
        if mutedChanged { applyMuted(newApp.muted) }
        pinButton?.image = NSImage(
            systemSymbolName: newApp.pinnedOpen ? "pin.fill" : "pin", accessibilityDescription: nil)
        alwaysOnTopButton?.image = NSImage(
            systemSymbolName: newApp.alwaysOnTop ? "arrow.up.square.fill" : "arrow.up.square",
            accessibilityDescription: nil)
        if sizeChanged { resizeWindow() }
        if toolbarModeChanged { applyToolbarMode() }
        panel.alphaValue = CGFloat(newApp.opacity)
        panel.level = newApp.alwaysOnTop ? .floating : .normal
        if uaChanged { webView.customUserAgent = newApp.resolvedUserAgent }
        if urlChanged || uaChanged {
            loadedURL = nil
            if panel.isVisible { ensureLoaded() }
        }
        // Selectors changed from elsewhere (e.g. Settings, another path) rather
        // than from a local hide/clear we already applied — re-bake and re-apply.
        if selectorsChanged && !wasLocalEdit {
            rebuildSelectorBootstrap()
            applyHiddenSelectorsLive()
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.delegate = nil
    }

    // MARK: - Toolbar auto-hide

    private var toolbarShown = true

    /// Lays out the web view and header for the current `autoHideToolbar` setting.
    /// When auto-hide is on the web view fills the whole window, the header floats
    /// on top (hidden until hovered), and a pass-through strip at the top edge
    /// detects the pointer to reveal it.
    private func applyToolbarMode() {
        let b = container.bounds
        headerView.frame = NSRect(x: 0, y: b.height - headerHeight, width: b.width, height: headerHeight)

        if app.autoHideToolbar {
            webView.frame = b
            let stripFrame = NSRect(x: 0, y: b.height - headerHeight, width: b.width, height: headerHeight)
            if let strip = hoverReveal {
                strip.frame = stripFrame
            } else {
                let strip = HoverRevealView(frame: stripFrame)
                strip.autoresizingMask = [.width, .minYMargin]
                strip.onHover = { [weak self] inside in
                    guard let self, self.app.autoHideToolbar else { return }
                    if inside { self.showToolbar() } else { self.hideToolbar() }
                }
                container.addSubview(strip, positioned: .above, relativeTo: webView)
                hoverReveal = strip
            }
            // header above the strip so its buttons stay clickable.
            container.addSubview(headerView, positioned: .above, relativeTo: hoverReveal)
            toolbarShown = false
            headerView.alphaValue = 0
            headerView.isHidden = true
        } else {
            hoverReveal?.removeFromSuperview()
            hoverReveal = nil
            webView.frame = NSRect(x: 0, y: 0, width: b.width, height: b.height - headerHeight)
            container.addSubview(headerView, positioned: .above, relativeTo: webView)
            toolbarShown = true
            headerView.isHidden = false
            headerView.alphaValue = 1
        }
    }

    private func showToolbar() {
        guard !toolbarShown else { return }
        toolbarShown = true
        headerView.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            headerView.animator().alphaValue = 1
        }
    }

    private func hideToolbar() {
        guard toolbarShown else { return }
        toolbarShown = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            headerView.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.toolbarShown else { return }
            self.headerView.isHidden = true
        })
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
        // Page mute resets on a full navigation; reassert the saved preference.
        applyMuted(app.muted)
        // The picker and theater scripts re-inject dormant on each load, so the
        // header toggles should reflect "off" again for the new page.
        setPickButtonState(active: false)
        setTheaterButtonState(active: false)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        backButton?.isEnabled = webView.canGoBack
    }
}

// MARK: - Hide Distracting Items

extension WebWindowController {

    // MARK: User-script installation

    /// Installs the three user scripts (bootstrap + engine + picker). The bootstrap
    /// bakes the current selector list in as a JS literal at `.atDocumentStart`, so
    /// persisted items are hidden before first paint (no flash of un-hidden cruft).
    private func installUserScripts(into ucc: WKUserContentController) {
        let bootstrap = WKUserScript(
            source: selectorBootstrapJS(app.hiddenSelectors),
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let engine = WKUserScript(
            source: Self.engineSource,
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let picker = WKUserScript(
            source: Self.pickerSource,
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        let theater = WKUserScript(
            source: Self.theaterSource,
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        ucc.addUserScript(bootstrap)
        ucc.addUserScript(engine)
        ucc.addUserScript(picker)
        ucc.addUserScript(theater)
    }

    /// The content controller is created once and reused across opens, so the baked
    /// bootstrap must be refreshed whenever the selector list changes for the *next*
    /// load to be correct. `removeAllUserScripts()` does NOT remove message handlers,
    /// so `menuAppHide` stays registered — don't re-add it here.
    private func rebuildSelectorBootstrap() {
        contentController.removeAllUserScripts()
        installUserScripts(into: contentController)
    }

    private func selectorBootstrapJS(_ selectors: [String]) -> String {
        let json = (try? JSONEncoder().encode(selectors))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "window.__menuAppHidden = \(json);"
    }

    /// Pushes the current selector list into the live page without a reload.
    private func applyHiddenSelectorsLive() {
        let json = (try? JSONEncoder().encode(app.hiddenSelectors))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        webView.evaluateJavaScript("window.__menuAppApply && window.__menuAppApply(\(json));")
    }

    // MARK: Hide-mode toggle & reset

    @objc func toggleHideMode(_ sender: NSButton) {
        pickActive.toggle()
        setPickButtonState(active: pickActive)
        webView.evaluateJavaScript(
            "window.__menuAppPick && window.__menuAppPick.setActive(\(pickActive));")
    }

    private func setPickButtonState(active: Bool) {
        pickActive = active
        pickButton?.image = NSImage(
            systemSymbolName: active ? "eye.slash.fill" : "eye.slash",
            accessibilityDescription: nil)
        pickButton?.contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
    }

    @objc func toggleTheater(_ sender: NSButton) {
        theaterActive.toggle()
        setTheaterButtonState(active: theaterActive)
        // JS reports back whether a video was actually found; if not, the button
        // un-latches via the message handler, signalling nothing happened.
        webView.evaluateJavaScript(
            "window.__menuAppTheater && window.__menuAppTheater.setActive(\(theaterActive));")
    }

    private func setTheaterButtonState(active: Bool) {
        theaterActive = active
        theaterButton?.image = NSImage(
            systemSymbolName: active ? "play.rectangle.fill" : "play.rectangle",
            accessibilityDescription: nil)
        theaterButton?.contentTintColor = active ? .controlAccentColor : .secondaryLabelColor
    }

    var hasHiddenSelectors: Bool { !app.hiddenSelectors.isEmpty }

    /// Restores the most recently hidden element. Reloads for the same reason as
    /// `clearHiddenSelectors()` — the picker's inline `display:none` on the clicked
    /// node won't revert from a stylesheet change alone.
    func undoLastHide() {
        guard !app.hiddenSelectors.isEmpty else { return }
        app.hiddenSelectors.removeLast()
        isApplyingLocalEdit = true
        onAppChanged?(app)
        rebuildSelectorBootstrap()
        webView.reload()
    }

    /// Clears all hidden selectors and reloads for a clean state. A reload is used
    /// (rather than just removing the `<style>`) because the picker also sets inline
    /// `display:none` on clicked nodes, which the stylesheet removal alone won't undo.
    func clearHiddenSelectors() {
        guard !app.hiddenSelectors.isEmpty else { return }
        app.hiddenSelectors.removeAll()
        isApplyingLocalEdit = true
        onAppChanged?(app)
        rebuildSelectorBootstrap()
        webView.reload()
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ ucc: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "menuAppHide" else { return }

        // The picker reporting its active state (e.g. the user pressed Esc).
        if let dict = message.body as? [String: Any], let on = dict["active"] as? Bool {
            setPickButtonState(active: on)
            return
        }

        // Theater mode reporting whether it engaged (false = no video found).
        if let dict = message.body as? [String: Any], let on = dict["theater"] as? Bool {
            setTheaterButtonState(active: on)
            return
        }

        guard let selector = message.body as? String,
              !selector.isEmpty,
              !app.hiddenSelectors.contains(selector) else { return }

        app.hiddenSelectors.append(selector)
        isApplyingLocalEdit = true
        onAppChanged?(app)
        rebuildSelectorBootstrap()   // keep the next load accurate
        applyHiddenSelectorsLive()   // keep the current page accurate (durable past SPA re-renders)
    }

    // MARK: Injected JavaScript

    /// Applies stored selectors as `display:none !important` via an injected
    /// `<style>`, and re-asserts it if a SPA tears it down. Exposes
    /// `window.__menuAppApply(selectors)` for live updates.
    static let engineSource = """
    (function () {
      if (window.__menuAppEngineInstalled) return;
      window.__menuAppEngineInstalled = true;
      var STYLE_ID = "__menuapp-hide-style";
      function selectors() {
        return Array.isArray(window.__menuAppHidden) ? window.__menuAppHidden : [];
      }
      function buildCSS() {
        var out = [];
        var sels = selectors();
        for (var i = 0; i < sels.length; i++) {
          var s = sels[i];
          // Drop malformed selectors; one bad rule invalidates the whole sheet.
          try { document.querySelector(s); } catch (e) { continue; }
          out.push(s + "{display:none !important;}");
        }
        return out.join("\\n");
      }
      function ensureStyle() {
        var el = document.getElementById(STYLE_ID);
        if (!el) {
          el = document.createElement("style");
          el.id = STYLE_ID;
          (document.head || document.documentElement).appendChild(el);
        }
        el.textContent = buildCSS();
      }
      window.__menuAppApply = function (newSelectors) {
        if (Array.isArray(newSelectors)) window.__menuAppHidden = newSelectors;
        ensureStyle();
      };
      ensureStyle();
      var scheduled = false;
      var obs = new MutationObserver(function () {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(function () {
          scheduled = false;
          if (!document.getElementById(STYLE_ID)) ensureStyle();
        });
      });
      function startObserver() {
        obs.observe(document.documentElement, { childList: true, subtree: true });
      }
      if (document.documentElement) startObserver();
      else document.addEventListener("DOMContentLoaded", startObserver, { once: true });
    })();
    """

    /// Click-to-hide picker. Dormant until `window.__menuAppPick.setActive(true)`.
    /// Highlights the hovered element; on click hides it, generates a stable CSS
    /// selector, and posts it to the `menuAppHide` handler. Esc exits.
    static let pickerSource = """
    (function () {
      if (window.__menuAppPick) return;
      var OVERLAY_ID = "__menuapp-pick-overlay";
      var active = false, overlay = null, lastTarget = null;

      function post(body) {
        try { window.webkit.messageHandlers.menuAppHide.postMessage(body); } catch (e) {}
      }
      function makeOverlay() {
        var o = document.createElement("div");
        o.id = OVERLAY_ID;
        var s = o.style;
        s.position = "fixed"; s.zIndex = "2147483647"; s.pointerEvents = "none";
        s.background = "rgba(0,122,255,0.25)"; s.border = "2px solid rgba(0,122,255,0.9)";
        s.borderRadius = "2px"; s.top = "0"; s.left = "0"; s.width = "0"; s.height = "0";
        s.transition = "all 40ms ease-out"; s.display = "none";
        (document.body || document.documentElement).appendChild(o);
        return o;
      }
      function positionOverlay(el) {
        if (!overlay) overlay = makeOverlay();
        var r = el.getBoundingClientRect();
        var s = overlay.style;
        s.display = "block";
        s.top = r.top + "px"; s.left = r.left + "px";
        s.width = r.width + "px"; s.height = r.height + "px";
      }
      function cssEscape(v) {
        return (window.CSS && CSS.escape) ? CSS.escape(v) : v.replace(/([^a-zA-Z0-9_-])/g, "\\\\$1");
      }
      function isStableId(id) {
        return id && !/[0-9]/.test(id) && !/^(ember|react|radix|:r)/i.test(id);
      }
      function classSelector(el) {
        var good = [];
        var list = el.classList ? Array.prototype.slice.call(el.classList) : [];
        for (var i = 0; i < list.length; i++) {
          var c = list[i];
          if (/^[a-zA-Z][a-zA-Z0-9_-]{2,}$/.test(c) && !/[0-9]{3,}/.test(c) && c.length < 30) good.push(c);
        }
        good = good.slice(0, 2).map(cssEscape);
        return good.length ? "." + good.join(".") : "";
      }
      function nthOfType(el) {
        var tag = el.tagName, i = 1, sib = el;
        while ((sib = sib.previousElementSibling)) if (sib.tagName === tag) i++;
        return ":nth-of-type(" + i + ")";
      }
      function partFor(el) {
        var part = el.tagName.toLowerCase();
        var cls = classSelector(el);
        if (cls) part += cls;
        var parent = el.parentElement;
        if (parent) {
          var matches = Array.prototype.filter.call(parent.children, function (c) {
            try { return c.matches(part); } catch (e) { return false; }
          });
          if (matches.length > 1) part += nthOfType(el);
        }
        return part;
      }
      function uniqueSelector(el) {
        if (isStableId(el.id)) return "#" + cssEscape(el.id);
        var parts = [], node = el;
        while (node && node.nodeType === 1 && node !== document.documentElement) {
          if (isStableId(node.id)) { parts.unshift("#" + cssEscape(node.id)); break; }
          parts.unshift(partFor(node));
          var candidate = parts.join(" > ");
          try { if (document.querySelectorAll(candidate).length === 1) return candidate; }
          catch (e) {}
          node = node.parentElement;
        }
        return parts.join(" > ");
      }
      function onMove(e) {
        if (!active) return;
        var el = e.target;
        if (!el || el === overlay || el === document.documentElement || el === document.body) return;
        lastTarget = el;
        positionOverlay(el);
      }
      function onClick(e) {
        if (!active) return;
        e.preventDefault(); e.stopPropagation();
        var el = lastTarget || e.target;
        if (!el) return;
        var sel;
        try { sel = uniqueSelector(el); } catch (err) { return; }
        if (!sel) return;
        el.style.setProperty("display", "none", "important");
        if (overlay) overlay.style.display = "none";
        post(sel);
      }
      function onKey(e) {
        if (active && e.key === "Escape") { e.preventDefault(); setActive(false); }
      }
      function setActive(on) {
        active = on;
        document.documentElement.style.cursor = on ? "crosshair" : "";
        if (on) {
          document.addEventListener("mousemove", onMove, true);
          document.addEventListener("click", onClick, true);
          document.addEventListener("keydown", onKey, true);
        } else {
          document.removeEventListener("mousemove", onMove, true);
          document.removeEventListener("click", onClick, true);
          document.removeEventListener("keydown", onKey, true);
          if (overlay) overlay.style.display = "none";
        }
        post({ active: on });
      }
      window.__menuAppPick = { setActive: setActive };
    })();
    """

    /// Theater mode. Picks the page's player element, lifts it out to be a direct
    /// child of <body>, and pins it to fill the window — so it escapes the site's
    /// own wrapper/overlay stacking contexts (e.g. YouTube's cinematic full-bleed
    /// container, which paints over a merely-pinned <video>). Sites with a known
    /// player container are handled via `SITES`; everything else falls back to the
    /// most prominent <video> (controls forced on) or a video-like iframe. Every
    /// mutation is recorded and undone in reverse by setActive(false).
    static let theaterSource = """
    (function () {
      if (window.__menuAppTheater) return;
      var STYLE_ID = "__menuapp-theater-style";

      // Per-site player containers. Reparenting one of these to <body> is far more
      // robust than pinning the bare <video>, because it keeps the site's native
      // controls and steps outside the wrappers that would otherwise overlay it.
      var SITES = [
        { host: /(^|\\.)youtube(-nocookie)?\\.com$|(^|\\.)youtu\\.be$/, sel: "#movie_player" }
      ];

      var undo = [];
      function pushUndo(fn) { undo.push(fn); }
      function runUndo() {
        for (var i = undo.length - 1; i >= 0; i--) { try { undo[i](); } catch (e) {} }
        undo = [];
      }

      function post(body) {
        try { window.webkit.messageHandlers.menuAppHide.postMessage(body); } catch (e) {}
      }
      function area(el) {
        var r = el.getBoundingClientRect();
        return r.width * r.height;
      }
      function siteTarget() {
        for (var i = 0; i < SITES.length; i++) {
          if (SITES[i].host.test(location.hostname)) {
            var el = document.querySelector(SITES[i].sel);
            if (el) return el;
          }
        }
        return null;
      }
      function pickVideo() {
        var best = null, bestArea = 0;
        var vids = document.querySelectorAll("video");
        for (var i = 0; i < vids.length; i++) {
          var a = area(vids[i]);
          if (a > bestArea) { bestArea = a; best = vids[i]; }
        }
        if (best && bestArea > 0) return best;
        // Fallback: largest video-like iframe (cross-origin embeds we can't see into).
        var frames = document.querySelectorAll("iframe");
        var bestFrame = null, bestFArea = 0;
        for (var j = 0; j < frames.length; j++) {
          var src = frames[j].src || "";
          if (!/youtube|youtu\\.be|vimeo|dailymotion|twitch|player|video|embed|stream/i.test(src)) continue;
          var fa = area(frames[j]);
          if (fa > bestFArea) { bestFArea = fa; bestFrame = frames[j]; }
        }
        return bestFrame;
      }
      function ensureStyle() {
        var el = document.createElement("style");
        el.id = STYLE_ID;
        (document.head || document.documentElement).appendChild(el);
        el.textContent =
          "html.__menuapp-theater, html.__menuapp-theater body{" +
            "background:#000 !important;margin:0 !important;overflow:hidden !important;}" +
          ".__menuapp-stage{position:fixed !important;inset:0 !important;top:0 !important;" +
            "left:0 !important;width:100vw !important;height:100vh !important;" +
            "max-width:100vw !important;max-height:100vh !important;margin:0 !important;" +
            "padding:0 !important;background:#000 !important;z-index:2147483647 !important;}" +
          // Letterbox a real <video> so the whole frame stays visible.
          "video.__menuapp-stage{object-fit:contain !important;}";
        pushUndo(function () { if (el.parentNode) el.parentNode.removeChild(el); });
      }
      // Move `el` to be the last child of <body>, remembering where it came from so
      // it can be put back exactly. For <video> we also force native controls on.
      function reparentToBody(el, isVideo) {
        var ph = document.createComment("menuapp-theater");
        el.parentNode.insertBefore(ph, el);
        var prevStyle = el.getAttribute("style");
        var prevControls = isVideo ? el.controls : null;
        document.body.appendChild(el);
        el.classList.add("__menuapp-stage");
        if (isVideo) { try { el.controls = true; } catch (e) {} }
        pushUndo(function () {
          el.classList.remove("__menuapp-stage");
          if (prevStyle === null) el.removeAttribute("style"); else el.setAttribute("style", prevStyle);
          if (isVideo) { try { el.controls = prevControls; } catch (e) {} }
          if (ph.parentNode) { ph.parentNode.insertBefore(el, ph); ph.parentNode.removeChild(ph); }
        });
      }
      function hideBodyChildrenExcept(keep) {
        var kids = Array.prototype.slice.call(document.body.children);
        kids.forEach(function (k) {
          if (k === keep) return;
          var pv = k.style.getPropertyValue("display");
          var pp = k.style.getPropertyPriority("display");
          k.style.setProperty("display", "none", "important");
          pushUndo(function () {
            if (pv) k.style.setProperty("display", pv, pp); else k.style.removeProperty("display");
          });
        });
      }
      function apply() {
        var target = siteTarget();
        var isVideo = false;
        if (!target) {
          target = pickVideo();
          isVideo = !!(target && target.tagName === "VIDEO");
        }
        if (!target) return false;
        document.documentElement.classList.add("__menuapp-theater");
        pushUndo(function () { document.documentElement.classList.remove("__menuapp-theater"); });
        ensureStyle();
        reparentToBody(target, isVideo);
        hideBodyChildrenExcept(target);
        // Nudge the site player to relayout into its new full-window box.
        try { window.dispatchEvent(new Event("resize")); } catch (e) {}
        return true;
      }
      window.__menuAppTheater = {
        setActive: function (on) {
          if (on) {
            if (undo.length) { post({ theater: true }); return; }
            post({ theater: !!apply() });
          } else {
            runUndo();
            try { window.dispatchEvent(new Event("resize")); } catch (e) {}
            post({ theater: false });
          }
        }
      };
    })();
    """
}

/// A transparent strip pinned to the top edge of the window that reports when the
/// pointer enters or leaves it, used to reveal an auto-hidden toolbar. It never
/// participates in hit-testing (`hitTest` returns nil), so clicks and scrolls pass
/// straight through to the web view beneath it; tracking-area enter/exit events are
/// geometry-based and still fire regardless.
final class HoverRevealView: NSView {
    var onHover: ((Bool) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
