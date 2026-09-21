import AppKit

/// The menu bar glyph: a monochrome version of the app icon.
///
/// Status bar images must be template images. macOS then tints them to match
/// the menu bar — black on a light bar, white on a dark one, inverted while
/// the item is highlighted — which a colour icon cannot do, and which is why
/// the full app icon is not used here directly.
enum StatusItemIcon {

    /// Standard menu bar glyph size.
    private static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw() {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Page outline.
        let body = NSRect(x: 1.5, y: 1.0, width: 15, height: 15)
        let page = NSBezierPath(roundedRect: body, xRadius: 3.2, yRadius: 3.2)
        page.lineWidth = 1.3
        page.stroke()

        // Header band, clipped to the rounded top.
        NSGraphicsContext.saveGraphicsState()
        page.addClip()
        NSRect(x: body.minX, y: body.maxY - 3.6, width: body.width, height: 3.6).fill()
        NSGraphicsContext.restoreGraphicsState()

        // Day dots: two rows of three, evenly weighted. The app icon singles
        // one dot out as "today", but at 18pt a dot one point larger is
        // indistinguishable, so the variation is dropped rather than pretended.
        // Squares, not circles — circles this small render as mush.
        let dot: CGFloat = 1.8
        let columns: [CGFloat] = [4.4, 8.1, 11.8]
        let rows: [CGFloat] = [8.0, 4.2]

        for y in rows {
            for x in columns {
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: y, width: dot, height: dot),
                    xRadius: 0.4, yRadius: 0.4
                ).fill()
            }
        }
    }
}
