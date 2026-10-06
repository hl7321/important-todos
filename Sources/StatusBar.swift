import AppKit

/// The icon the user clicks to bring the card back: left click toggles the card, right
/// click opens the menu.
final class StatusBarController: NSObject, NSMenuDelegate {
    private let store: Store
    private let panel: PanelController
    private let item: NSStatusItem
    private let menu = NSMenu()

    private let floatingItem = NSMenuItem(title: "浮在窗口上方", action: nil, keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机时自动启动（卡片不弹出）", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "显示 / 隐藏这张卡", action: nil, keyEquivalent: "")

    private static let loginLabel = "com.local.dailycheck"

    init(store: Store, panel: PanelController) {
        self.store = store
        self.panel = panel
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            let image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "重要待办")
            image?.isTemplate = true
            button.image = image
            // If the symbol ever fails to load the item would be a zero-width blank, so
            // keep a text fallback: a menu bar icon the user cannot see is worse than
            // an ugly one.
            if image == nil { button.title = "✓" }
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "重要待办 · \(CardShortcut.description) 呼出/收起"
        }
        buildMenu()
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.delegate = self

        toggleItem.target = self
        toggleItem.action = #selector(togglePanel)
        menu.addItem(toggleItem)

        let recenter = NSMenuItem(title: "移回右上角", action: #selector(recenter), keyEquivalent: "")
        recenter.target = self
        menu.addItem(recenter)

        menu.addItem(.separator())

        floatingItem.target = self
        floatingItem.action = #selector(toggleFloating)
        menu.addItem(floatingItem)

        loginItem.target = self
        loginItem.action = #selector(toggleLogin)
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let openData = NSMenuItem(title: "打开数据文件", action: #selector(openDataFile), keyEquivalent: "")
        openData.target = self
        menu.addItem(openData)

        let reset = NSMenuItem(title: "清空今天的打孔", action: #selector(resetToday), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleItem.title = (panel.isVisible ? "隐藏这张卡" : "显示这张卡")
            + "（\(CardShortcut.description)）"
        floatingItem.state = store.floating ? .on : .off
        loginItem.state = loginEnabled ? .on : .off
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            panel.toggle()
        }
    }

    @objc private func togglePanel() { panel.toggle() }

    @objc private func recenter() {
        panel.moveToDefaultCorner()
        panel.show()
    }

    @objc private func toggleFloating() {
        store.setFloating(!store.floating)
        panel.applyLevel()
        floatingItem.state = store.floating ? .on : .off
    }

    @objc private func openDataFile() {
        store.save()
        NSWorkspace.shared.activateFileViewerSelecting([store.dataURL])
    }

    @objc private func resetToday() {
        store.resetToday()
    }

    // MARK: - Launch at login

    private var loginPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.loginLabel).plist")
    }

    private var loginEnabled: Bool {
        FileManager.default.fileExists(atPath: loginPlistURL.path)
    }

    /// A LaunchAgent is used rather than the ServiceManagement API so the card can be
    /// enabled without a signing identity. It takes effect at the next login.
    /// It starts hidden so login does not drop a card onto the desktop; the menu bar
    /// icon and Spotlight bring it back.
    @objc private func toggleLogin() {
        if loginEnabled {
            try? FileManager.default.removeItem(at: loginPlistURL)
        } else {
            let plist: [String: Any] = [
                "Label": Self.loginLabel,
                "ProgramArguments": [Bundle.main.executablePath ?? "", "--start-hidden"],
                "RunAtLoad": true,
                "ProcessType": "Interactive",
            ]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                                format: .xml,
                                                                options: 0) else { return }
            try? FileManager.default.createDirectory(at: loginPlistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? data.write(to: loginPlistURL)
        }
        loginItem.state = loginEnabled ? .on : .off
    }
}
