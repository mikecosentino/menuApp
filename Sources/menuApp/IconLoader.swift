import AppKit

/// Produces the monochrome menubar icon for a menu app from its selected SF Symbol.
enum IconLoader {
    /// Resolves a black-and-white template icon for the given menu app.
    static func icon(for app: MenuApp) -> NSImage {
        if let symbol = NSImage(systemSymbolName: app.symbolName, accessibilityDescription: app.name) {
            symbol.isTemplate = true
            return symbol
        }
        return letterIcon(for: app.name)
    }

    /// Fallback when the chosen symbol name isn't a valid SF Symbol.
    private static func letterIcon(for name: String) -> NSImage {
        let letter = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ]
        let rect = NSRect(x: 0, y: -1, width: size.width, height: size.height)
        (letter as NSString).draw(in: rect, withAttributes: attrs)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
