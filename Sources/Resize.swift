import AppKit

/// A draggable edge of the borderless card.
///
/// This is AppKit rather than a SwiftUI gesture on purpose: the panel moves when you
/// drag its background (`isMovableByWindowBackground`), and only a real view that
/// refuses `mouseDownCanMoveWindow` is guaranteed to resize instead of dragging the
/// whole card away. Using an NSView also gets the cursor for free via cursor rects.
final class ResizeHandleView: NSView {
    enum Kind {
        case leftEdge
        case rightEdge
        case bottomEdge
    }

    let kind: Kind
    /// Incremental drag, already signed the way the caller wants it.
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    private var lastPoint: NSPoint = .zero
    private var tracking: NSTrackingArea?
    private var hovering = false
    private let highlight = CALayer()

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
        highlight.backgroundColor = NSColor(srgbRed: 0.776, green: 0.251, blue: 0.165, alpha: 0.35).cgColor
        highlight.opacity = 0
        layer?.addSublayer(highlight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Never let the window interpret this drag as "move the card".
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        let cursor: NSCursor = kind == .bottomEdge ? .resizeUpDown : .resizeLeftRight
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch kind {
        case .leftEdge, .rightEdge:
            highlight.frame = CGRect(x: kind == .leftEdge ? 0 : bounds.width - 2,
                                     y: 8,
                                     width: 2,
                                     height: max(0, bounds.height - 16))
        case .bottomEdge:
            highlight.frame = CGRect(x: 8,
                                     y: kind == .bottomEdge ? 0 : 0,
                                     width: max(0, bounds.width - 16),
                                     height: 2)
        }
        CATransaction.commit()
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        highlight.opacity = 1
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        highlight.opacity = 0
    }

    override func mouseDown(with event: NSEvent) {
        lastPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        lastPoint = point
        switch kind {
        // Dragging the left edge to the left widens the card, right edge stays put.
        case .leftEdge: onDrag?(-dx)
        case .rightEdge: onDrag?(dx)
        // Cocoa y grows upward, so dragging down (negative dy) makes the card taller.
        case .bottomEdge: onDrag?(-dy)
        }
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}

/// Holds the SwiftUI card plus its three resize edges, and keeps them pinned to the
/// window's bounds as it changes size.
final class CardContainer: NSView {
    static let handleThickness: CGFloat = 7

    let hosting: NSView
    let leftHandle = ResizeHandleView(kind: .leftEdge)
    let rightHandle = ResizeHandleView(kind: .rightEdge)
    let bottomHandle = ResizeHandleView(kind: .bottomEdge)

    init(hosting: NSView) {
        self.hosting = hosting
        super.init(frame: .zero)
        addSubview(hosting)
        addSubview(leftHandle)
        addSubview(rightHandle)
        addSubview(bottomHandle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let thickness = CardContainer.handleThickness
        hosting.frame = bounds
        leftHandle.frame = NSRect(x: 0, y: 0, width: thickness, height: bounds.height)
        rightHandle.frame = NSRect(x: max(0, bounds.width - thickness),
                                   y: 0,
                                   width: thickness,
                                   height: bounds.height)
        bottomHandle.frame = NSRect(x: thickness,
                                    y: 0,
                                    width: max(0, bounds.width - thickness * 2),
                                    height: thickness)
    }
}
