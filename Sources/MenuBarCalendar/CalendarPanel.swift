import AppKit

/// The dropdown window shown under the status item.
///
/// This replaces `NSPopover`, which always draws an anchor arrow pointing at
/// its source view — there is no public way to hide it. A borderless panel
/// gives full control over position, so the calendar can sit flush against the
/// menu bar, and over shape, so it keeps the same rounded corners and shadow.
final class CalendarPanel: NSPanel {

    /// Corner radius of the panel's content.
    static let cornerRadius: CGFloat = 10
    /// Vertical gap between the menu bar and the panel.
    static let menuBarGap: CGFloat = 2
    /// Minimum distance kept from the left and right screen edges.
    private static let screenMargin: CGFloat = 8

    /// Borderless windows refuse key status by default, which would leave the
    /// SwiftUI controls inside unable to take clicks.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Keep the panel out of Mission Control and visible on every Space,
        // the way a menu bar dropdown behaves.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .utilityWindow

        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = Self.cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        self.contentView = contentView

        setContentSize(contentView.fittingSize)
    }

    /// Positions the panel directly below `button`, horizontally centred on it
    /// and clamped to the screen the button lives on.
    func position(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil))
        let size = frame.size

        var origin = NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height - Self.menuBarGap
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + Self.screenMargin),
                           visible.maxX - size.width - Self.screenMargin)
            // If there is somehow no room below, keep the panel on screen
            // rather than letting it slide off the bottom.
            origin.y = max(origin.y, visible.minY + Self.screenMargin)
        }

        setFrameOrigin(origin)
        invalidateShadow()
    }

    /// Resizes to the content's natural size, keeping the top edge where it is
    /// so the panel stays attached to the menu bar as it grows or shrinks.
    func fitContent() {
        guard let contentView else { return }
        let size = contentView.fittingSize
        guard abs(size.height - frame.height) > 0.5 || abs(size.width - frame.width) > 0.5 else {
            return
        }
        var newFrame = frame
        newFrame.origin.y = frame.maxY - size.height
        newFrame.size = size
        setFrame(newFrame, display: true)
        invalidateShadow()
    }

    /// Escape closes the panel, matching menu behaviour.
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
