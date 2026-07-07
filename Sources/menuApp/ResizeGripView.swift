import AppKit

/// A small bottom-right grip that resizes the window, keeping the top-left corner fixed.
/// Borderless windows don't reliably get user edge-resizing, so this guarantees a handle.
final class ResizeGripView: NSView {
    var minSize = NSSize(width: 280, height: 240)

    /// Optional hook to constrain the dragged size (e.g. lock the aspect ratio in
    /// theater mode). Given the post-min-clamp size, returns the size to apply.
    var constrainSize: ((NSSize) -> NSSize)?

    override func resetCursorRects() {
        // Diagonal resize affordance.
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.tertiaryLabelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        // Three short diagonal lines in the corner.
        for offset in stride(from: 4, through: 12, by: 4) {
            path.move(to: NSPoint(x: bounds.maxX - CGFloat(offset), y: bounds.minY + 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + CGFloat(offset)))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        // No-op; tracking happens in mouseDragged using the global cursor position.
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation            // screen coordinates
        let topY = window.frame.maxY                 // keep the top edge fixed
        let leftX = window.frame.minX                // keep the left edge fixed

        var width = mouse.x - leftX
        var height = topY - mouse.y
        width = max(width, minSize.width)
        height = max(height, minSize.height)
        if let constrainSize {
            let s = constrainSize(NSSize(width: width, height: height))
            width = s.width
            height = s.height
        }

        let newFrame = NSRect(x: leftX, y: topY - height, width: width, height: height)
        window.setFrame(newFrame, display: true)
    }
}
