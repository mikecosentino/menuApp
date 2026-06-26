import Foundation

/// User-agent presets applied to a menu app's web view.
enum UserAgentMode: String, Codable, CaseIterable {
    case mobileSafari
    case desktopSafari
    case desktopChrome
    case desktopEdge
    case custom

    var label: String {
        switch self {
        case .mobileSafari: return "Mobile Safari"
        case .desktopSafari: return "Desktop Safari"
        case .desktopChrome: return "Desktop Chrome"
        case .desktopEdge: return "Desktop Edge"
        case .custom: return "Custom…"
        }
    }

    /// The user-agent string, or nil to use WKWebView's built-in default (desktop Safari).
    func userAgent(custom: String) -> String? {
        switch self {
        case .mobileSafari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 " +
                   "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"
        case .desktopSafari:
            return nil // WKWebView's native UA is already desktop Safari.
        case .desktopChrome:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                   "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
        case .desktopEdge:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
                   "(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36 Edg/138.0.0.0"
        case .custom:
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}

/// A single "menu app": a website pinned to the menubar.
struct MenuApp: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var urlString: String
    /// SF Symbol name used as the (monochrome) menubar icon.
    var symbolName: String
    /// Window size in points. Defaults to an iPhone-ish portrait size.
    var width: Double
    var height: Double
    /// When true, the window stays open after losing focus instead of behaving like a popover.
    var pinnedOpen: Bool
    /// Window opacity, 0.2 (very transparent) to 1.0 (opaque).
    var opacity: Double
    /// When true, the window floats above other apps' windows.
    var alwaysOnTop: Bool
    /// User-agent preset for the web view.
    var userAgentMode: UserAgentMode
    /// Custom user-agent string used when `userAgentMode == .custom`.
    var customUserAgent: String
    /// CSS selectors the user has chosen to hide on this app's site.
    /// Applied as `display:none !important` on every load (Safari-style
    /// "Hide Distracting Items"), and persisted so they survive reopening.
    var hiddenSelectors: [String]

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        symbolName: String = "globe",
        width: Double = 390,
        height: Double = 760,
        pinnedOpen: Bool = false,
        opacity: Double = 1.0,
        alwaysOnTop: Bool = false,
        userAgentMode: UserAgentMode = .mobileSafari,
        customUserAgent: String = "",
        hiddenSelectors: [String] = []
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.symbolName = symbolName
        self.width = width
        self.height = height
        self.pinnedOpen = pinnedOpen
        self.opacity = opacity
        self.alwaysOnTop = alwaysOnTop
        self.userAgentMode = userAgentMode
        self.customUserAgent = customUserAgent
        self.hiddenSelectors = hiddenSelectors
    }

    /// Custom decoding so saved files written by older/newer builds still load
    /// (unknown keys are ignored; missing keys fall back to defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        urlString = try c.decode(String.self, forKey: .urlString)
        symbolName = try c.decodeIfPresent(String.self, forKey: .symbolName) ?? "globe"
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 390
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 760
        pinnedOpen = try c.decodeIfPresent(Bool.self, forKey: .pinnedOpen) ?? false
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        alwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? false
        userAgentMode = try c.decodeIfPresent(UserAgentMode.self, forKey: .userAgentMode) ?? .mobileSafari
        customUserAgent = try c.decodeIfPresent(String.self, forKey: .customUserAgent) ?? ""
        hiddenSelectors = try c.decodeIfPresent([String].self, forKey: .hiddenSelectors) ?? []
    }

    /// A normalized URL, adding https:// when the user omitted a scheme.
    var url: URL? {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") {
            s = "https://" + s
        }
        return URL(string: s)
    }

    var host: String? {
        url?.host
    }

    /// Resolved user-agent for the web view (nil = WKWebView default).
    var resolvedUserAgent: String? {
        userAgentMode.userAgent(custom: customUserAgent)
    }
}
