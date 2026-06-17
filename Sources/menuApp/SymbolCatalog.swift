import AppKit

/// A curated set of SF Symbol names for the icon picker.
/// Names that don't resolve on the running OS are filtered out at load time,
/// so it's safe to list symbols that may not exist on every macOS version.
enum SymbolCatalog {
    /// All valid symbol names from the curated list, in order.
    static let all: [String] = raw.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }

    /// Returns true if `name` is a usable SF Symbol on this system.
    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private static let raw: [String] = [
        // General / web
        "globe", "globe.americas", "globe.europe.africa", "network", "wifi", "link",
        "safari", "magnifyingglass", "bookmark", "newspaper", "doc.text", "books.vertical",
        // Communication
        "envelope", "envelope.open", "message", "bubble.left", "bubble.left.and.bubble.right",
        "phone", "video", "bell", "megaphone", "at", "paperplane",
        // Social / people
        "person", "person.2", "person.3", "person.crop.circle", "bird", "hand.wave",
        "heart", "hand.thumbsup", "star", "flag", "bookmark.fill",
        // Media
        "play.rectangle", "play.circle", "music.note", "music.note.list", "headphones",
        "tv", "film", "photo", "photo.on.rectangle", "camera", "mic", "speaker.wave.2",
        "gamecontroller", "radio", "guitars",
        // Shopping / money
        "cart", "bag", "creditcard", "dollarsign.circle", "giftcard", "tag", "banknote",
        "chart.line.uptrend.xyaxis", "chart.bar", "chart.pie", "bitcoinsign.circle",
        // Productivity
        "calendar", "checklist", "list.bullet", "checkmark.circle", "clock", "alarm",
        "timer", "stopwatch", "note.text", "pencil", "doc", "folder", "tray", "paperclip",
        "briefcase", "building.2", "graduationcap", "books.vertical.fill",
        // Travel / places
        "house", "map", "mappin", "location", "car", "airplane", "tram", "bicycle",
        "fork.knife", "cup.and.saucer", "bed.double", "building.columns",
        // Weather / nature
        "cloud", "cloud.rain", "sun.max", "moon", "bolt", "snowflake", "leaf", "flame",
        "drop", "tornado", "wind",
        // Tech / dev
        "terminal", "chevron.left.forwardslash.chevron.right", "cpu", "memorychip",
        "externaldrive", "server.rack", "ladybug", "hammer", "wrench.and.screwdriver",
        "gearshape", "gearshape.2", "command", "keyboard", "desktopcomputer", "laptopcomputer",
        // Symbols / misc
        "bolt.horizontal", "sparkles", "wand.and.stars", "lightbulb", "puzzlepiece",
        "cube", "shippingbox", "gift", "crown", "trophy", "medal", "target", "scope",
        "flag.checkered", "circle.grid.2x2", "square.grid.2x2", "rectangle.3.group",
        "app", "app.badge", "questionmark.circle", "info.circle", "exclamationmark.triangle",
        "lock", "lock.open", "key", "shield", "eye", "hand.raised", "face.smiling"
    ]
}
