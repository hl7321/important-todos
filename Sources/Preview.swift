import AppKit
import SwiftUI

// Renders the card to PNG files so the design can be judged without a live window.
// Build with ./build.sh --preview; it is not part of the shipping app.

@MainActor
func render(_ view: some View, to path: String, scale: CGFloat = 2) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    guard let cgImage = renderer.cgImage else {
        print("render failed: \(path)")
        return
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try? data.write(to: url)
    print("wrote \(path) \(cgImage.width)x\(cgImage.height)")
}

func day(_ offset: Int) -> String {
    let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
    return Store.key(for: date)
}

/// Synthetic content for the previews only: five recurring tasks and a five day run
/// behind today.
func sampleStore(allDone: Bool, empty: Bool = false) -> Store {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("dailycheck-preview-\(UUID().uuidString).json")
    let todos: [[String: String]] = empty ? [] : [
        ["id": "t1", "title": "喝水 8 杯"],
        ["id": "t2", "title": "读书 30 分钟"],
        ["id": "t3", "title": "运动 20 分钟"],
        ["id": "t4", "title": "写今天的日志"],
        ["id": "t5", "title": "23:30 前关灯"],
    ]
    let ids = todos.compactMap { $0["id"] }
    var log: [String: [String]] = [:]
    for offset in 1...5 { log[day(offset)] = ids }
    log[day(0)] = allDone ? ids : ["t1", "t2"]

    let payload: [String: Any] = ["todos": todos, "log": log, "floating": true]
    if let data = try? JSONSerialization.data(withJSONObject: payload) {
        try? data.write(to: url)
    }
    return Store(dataURL: url)
}

@MainActor
func framed(_ store: Store, _ scheme: ColorScheme, ground: String) -> some View {
    WidgetView(store: store)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CardTheme.of(scheme).paper)
                .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.22),
                        radius: 15, x: 0, y: 7)
        )
        .padding(28)
        .background(hex(ground))
        .environment(\.colorScheme, scheme)
}

@main
struct PreviewRunner {
    @MainActor
    static func main() {
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "preview"
        let cases: [(Store, ColorScheme, String, String)] = [
            (sampleStore(allDone: false), .light, "7A7F87", "light"),
            (sampleStore(allDone: true), .light, "7A7F87", "light-done"),
            (sampleStore(allDone: false), .dark, "2A2D33", "dark"),
            (sampleStore(allDone: true), .dark, "2A2D33", "dark-done"),
            (sampleStore(allDone: false, empty: true), .light, "7A7F87", "empty"),
        ]
        for (store, scheme, ground, name) in cases {
            render(framed(store, scheme, ground: ground), to: "\(outDir)/\(name).png")
        }
    }
}
