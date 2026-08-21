import AppKit

/// Borderless, transparent, non-activating panel pinned to the top strip of
/// the screen. It ignores mouse events except while the cursor is over the
/// card, so everything else clicks straight through.
public final class DangleWindow: NSPanel {

    public init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovable = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Front: floats above windows. Behind: keeps watch from the desktop.
    public func setBehindWindows(_ behind: Bool) {
        if behind {
            level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        } else {
            level = .statusBar
        }
    }
}

public final class DangleView: NSView {
    public var onMouseDown: ((CGPoint) -> Void)?
    public var onMouseDragged: ((CGPoint) -> Void)?
    public var onMouseUp: ((CGPoint) -> Void)?

    public override var isFlipped: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func local(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    public override func mouseDown(with event: NSEvent) { onMouseDown?(local(event)) }
    public override func mouseDragged(with event: NSEvent) { onMouseDragged?(local(event)) }
    public override func mouseUp(with event: NSEvent) { onMouseUp?(local(event)) }
}
