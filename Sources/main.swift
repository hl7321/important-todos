import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var panel: PanelController!
    private var status: StatusBarController!
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        // `--verify` works on a throwaway data file so a self-check never edits the
        // card the user is actually keeping.
        if arguments.contains("--verify") {
            let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("dailycheck-verify-\(UUID().uuidString).json")
            store = Store(dataURL: scratch)
        } else {
            store = Store()
        }
        panel = PanelController(store: store)
        status = StatusBarController(store: store, panel: panel)
        hotKey = GlobalHotKey.register(keyCode: CardShortcut.keyCode,
                                      modifiers: CardShortcut.modifiers) { [weak panel] in
            panel?.toggle()
        }

        // `--start-hidden` is used when the card is set to open at login: the app waits
        // in the menu bar and the card only appears when it is called.
        if !arguments.contains("--start-hidden") {
            panel.show()
        }

        // `--verify` prints the live window state and quits; used by the build check.
        if arguments.contains("--verify") {
            runVerification()
        }
    }

    /// Walks the card through its states and prints what the window server sees at each
    /// one, including the states the check itself cannot click into existence.
    private func runVerification() {
        var lines: [String] = []
        if hotKey == nil {
            lines.append("hotkey \(CardShortcut.description) registered: false")
        } else {
            lines.append("hotkey \(CardShortcut.description) registered: true")
        }
        panel.show()

        let steps: [(String, () -> Void)] = [
            ("after show", {}),
            ("after planning tomorrow (drawer open, one item added)", {
                self.store.setTomorrowOpen(true)
                self.store.addTomorrow(title: "明天要做的事")
            }),
            ("after resize to 460 wide, list height 300, history open", {
                self.store.setTomorrowOpen(false)
                self.store.setHistoryOpen(true)
                self.store.setCardWidth(460, persist: false)
                self.store.setListHeight(300, persist: false)
                self.panel.fitHeight()
            }),
            ("after hide", { self.panel.hide() }),
        ]

        func step(_ index: Int) {
            guard index < steps.count else {
                FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
                NSApp.terminate(nil)
                return
            }
            let (title, action) = steps[index]
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                lines.append("== \(title) ==")
                lines.append(self.panel.verifyReport)
                step(index + 1)
            }
        }
        step(0)
    }

    /// Opening the app again — from Spotlight, Finder, or `open` — calls the card back
    /// instead of starting a second copy.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.summon()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
