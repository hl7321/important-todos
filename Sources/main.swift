import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var panel: PanelController!
    private var status: StatusBarController!
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = Store()
        panel = PanelController(store: store)
        status = StatusBarController(store: store, panel: panel)
        hotKey = GlobalHotKey.register(keyCode: CardShortcut.keyCode,
                                      modifiers: CardShortcut.modifiers) { [weak panel] in
            panel?.toggle()
        }

        let arguments = ProcessInfo.processInfo.arguments
        // `--start-hidden` is used when the card is set to open at login: the app waits
        // in the menu bar and the card only appears when it is called.
        if !arguments.contains("--start-hidden") {
            panel.show()
        }

        // `--verify` prints the live window state and quits; used by the build check.
        if arguments.contains("--verify") {
            FileHandle.standardError.write(Data("hotkey \(CardShortcut.description) registered: \(hotKey != nil)\n".utf8))
            panel.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let shown = self.panel.verifyReport
                // The collapse button calls exactly this, so the hide path is exercised.
                self.panel.hide()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let hidden = self.panel.verifyReport
                    let report = """
                    == after show ==
                    \(shown)
                    == after hide ==
                    \(hidden)

                    """
                    FileHandle.standardError.write(Data(report.utf8))
                    NSApp.terminate(nil)
                }
            }
        }
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
