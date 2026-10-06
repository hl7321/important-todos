import AppKit
import Combine
import SwiftUI

/// A borderless card. It can take key focus (so the add and rename fields accept typing)
/// without pulling the app to the front the way a normal window would.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the card's window: placement, level, and keeping its height fitted to the
/// content as tasks come and go.
final class PanelController {
    private let store: Store
    private let panel: WidgetPanel
    private let hosting: NSHostingView<WidgetView>
    private let container: CardContainer
    private var cancellable: AnyCancellable?
    private var moveObserver: NSObjectProtocol?

    static let desktopLevel = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)

    var isVisible: Bool { panel.isVisible }

    /// One line of live window state, printed by `--verify`.
    var verifyReport: String {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let onScreen = PanelController.onScreenWindowCount(for: ProcessInfo.processInfo.processIdentifier)
        let handles = """
        left=\(container.leftHandle.frame) right=\(container.rightHandle.frame) bottom=\(container.bottomHandle.frame)
        """
        return """
        window frame=\(panel.frame)
        window level=\(panel.level.rawValue) visible=\(panel.isVisible) movableByBackground=\(panel.isMovableByWindowBackground)
        content fitting=\(hosting.fittingSize) actual=\(panel.contentView?.frame.size ?? .zero)
        card width=\(store.cardWidth) list height=\(store.listHeight.map { String(Int($0)) } ?? "auto") measured=\(Int(store.measuredListHeight)) history=\(store.historyOpen)
        resize handles \(handles)
        this process has \(onScreen) window(s) on screen
        screen visible frame=\(screen)
        """
    }

    /// Counts this process's own windows that the window server is actually showing —
    /// the difference between "isVisible says true" and "the user can see it".
    static func onScreenWindowCount(for pid: Int32) -> Int {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }.count
    }

    init(store: Store) {
        self.store = store
        hosting = NSHostingView(rootView: WidgetView(store: store))
        let size = hosting.fittingSize
        container = CardContainer(hosting: hosting)
        panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)

        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        applyLevel()
        place()

        // Now that every property is set, the card can be given the real dismiss action.
        hosting.rootView = WidgetView(store: store, onHide: { [weak self] in self?.hide() })
        wireResizeHandles()

        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitHeight() }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main) { [weak self] _ in
                guard let self, self.panel.isVisible else { return }
                self.store.rememberFrame(self.panel.frame.origin)
            }
    }

    // MARK: - Resizing

    private func wireResizeHandles() {
        // Dragging the left edge keeps the right edge where it is, so the card grows
        // leftwards; the right edge grows rightwards; the bottom edge changes how tall
        // the task area is (and the card scrolls once the tasks no longer fit).
        container.leftHandle.onDrag = { [weak self] delta in
            self?.growWidth(by: delta, anchoredRight: true)
        }
        container.leftHandle.onEnd = { [weak self] in self?.commitResize() }
        container.rightHandle.onDrag = { [weak self] delta in
            self?.growWidth(by: delta, anchoredRight: false)
        }
        container.rightHandle.onEnd = { [weak self] in self?.commitResize() }
        container.bottomHandle.onDrag = { [weak self] delta in
            self?.growListHeight(by: delta)
        }
        container.bottomHandle.onEnd = { [weak self] in self?.commitResize() }
    }

    private func growWidth(by delta: CGFloat, anchoredRight: Bool) {
        guard delta != 0 else { return }
        store.setCardWidth(store.cardWidth + Double(delta), persist: false)
        var frame = panel.frame
        let top = frame.maxY
        let right = frame.maxX
        frame.size.width = CGFloat(store.cardWidth)
        if anchoredRight { frame.origin.x = right - frame.size.width }
        frame.origin.y = top - frame.size.height
        panel.setFrame(frame, display: true)
    }

    private func growListHeight(by delta: CGFloat) {
        guard delta != 0 else { return }
        let base = store.listHeight ?? max(store.measuredListHeight, Store.minListHeight)
        store.setListHeight(base + Double(delta), persist: false)
        fitHeight()
    }

    private func commitResize() {
        store.save()
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    // MARK: - Placement

    private func place() {
        if let origin = store.frameOrigin, isOnAScreen(origin) {
            panel.setFrameOrigin(origin)
            return
        }
        moveToDefaultCorner()
    }

    /// Top-right of the screen the pointer is on, clear of the menu bar.
    func moveToDefaultCorner() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = CGPoint(x: visible.maxX - size.width - 22,
                             y: visible.maxY - size.height - 18)
        panel.setFrameOrigin(origin)
        store.rememberFrame(origin)
    }

    private func isOnAScreen(_ origin: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -200, dy: -200).contains(origin) }
    }

    // MARK: - Level

    func applyLevel() {
        panel.level = store.floating ? .floating : Self.desktopLevel
    }

    // MARK: - Visibility

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Show the card and let it acknowledge being called.
    func summon() {
        show()
        store.summon()
    }

    // MARK: - Fitting

    /// The card grows downward: the top edge stays where the user put it.
    func fitHeight() {
        hosting.layoutSubtreeIfNeeded()
        let target = hosting.fittingSize
        guard target.height > 40 else { return }
        let current = panel.frame
        guard abs(target.height - current.height) > 0.5 || abs(target.width - current.width) > 0.5 else { return }
        let top = current.maxY
        var frame = current
        frame.size = NSSize(width: target.width, height: target.height)
        frame.origin.y = top - target.height
        panel.setFrame(frame, display: true, animate: false)
    }
}
