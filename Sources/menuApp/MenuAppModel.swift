import Foundation

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

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        symbolName: String = "globe",
        width: Double = 390,
        height: Double = 760,
        pinnedOpen: Bool = false,
        opacity: Double = 1.0,
        alwaysOnTop: Bool = false
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
}
