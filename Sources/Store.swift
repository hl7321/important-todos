import Combine
import Foundation
import SwiftUI

struct Todo: Codable, Identifiable, Hashable {
    var id: String
    var title: String
}

/// One day in the stamp column.
struct DayStamp: Identifiable {
    var id: Date { date }
    let date: Date
    let complete: Bool
}

private struct SavedState: Codable {
    var todos: [Todo]
    var log: [String: [String]]
    /// What each day was required to punch. Snapshotted so a task added today cannot
    /// rewrite the days that are already behind us.
    var needed: [String: [String]]?
    var floating: Bool?
    var frameX: Double?
    var frameY: Double?
}

/// Everything the card knows: today's list, the completion log keyed by calendar day,
/// and where the user left the card. One JSON file, no network, no account.
final class Store: ObservableObject {
    @Published var todos: [Todo]
    @Published var log: [String: [String]]
    @Published var needed: [String: [String]]
    @Published var floating: Bool
    /// Advanced on a slow timer so the card rolls over at midnight without a relaunch.
    @Published private(set) var now = Date()
    /// Bumped when the card is called back from the menu bar or by opening the app again,
    /// so the panel can answer with a small nudge instead of appearing silently.
    @Published private(set) var summonTick = 0

    let dataURL: URL
    private(set) var frameOrigin: CGPoint?
    private var clock: AnyCancellable?

    /// Placeholder tasks for the first run. They are illustrative, not the user's list;
    /// the card's empty state takes over once they are removed.
    static let starterTodos: [Todo] = [
        Todo(id: "starter-1", title: "喝水 8 杯"),
        Todo(id: "starter-2", title: "读书 30 分钟"),
        Todo(id: "starter-3", title: "运动 20 分钟"),
    ]

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func defaultDataURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["DAILYCHECK_DATA"] {
            return URL(fileURLWithPath: override)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DailyCheck", isDirectory: true)
            .appendingPathComponent("data.json")
    }

    init(dataURL: URL? = nil) {
        let url = dataURL ?? Store.defaultDataURL()
        self.dataURL = url
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode(SavedState.self, from: data) {
            todos = saved.todos
            log = saved.log
            needed = saved.needed ?? [:]
            floating = saved.floating ?? true
            if let x = saved.frameX, let y = saved.frameY {
                frameOrigin = CGPoint(x: x, y: y)
            }
        } else {
            todos = Store.starterTodos
            log = [:]
            needed = [:]
            floating = true
        }
        clock = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
    }

    // MARK: - Days

    static func key(for date: Date) -> String { keyFormatter.string(from: date) }

    private static func date(daysAgo: Int, from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }

    func doneIDs(on date: Date) -> Set<String> {
        Set(log[Store.key(for: date)] ?? [])
    }

    func isDone(_ todo: Todo, on date: Date = Date()) -> Bool {
        doneIDs(on: date).contains(todo.id)
    }

    func isComplete(_ date: Date) -> Bool {
        // Days the card recorded carry their own requirement. For any day it never got
        // around to recording, today's list is the only honest guess.
        let required = needed[Store.key(for: date)] ?? todos.map(\.id)
        guard !required.isEmpty else { return false }
        let done = doneIDs(on: date)
        return required.allSatisfy { done.contains($0) }
    }

    /// Today's requirement always mirrors today's list: a task written today has to be
    /// punched today, and days already finished keep the requirement they were judged by.
    private func refreshTodayRequirement() {
        needed[Store.key(for: now)] = todos.map(\.id)
    }

    var doneCount: Int {
        let done = doneIDs(on: now)
        return todos.filter { done.contains($0.id) }.count
    }

    var allDone: Bool { isComplete(now) }

    /// Consecutive finished days. A day still in progress does not break the run.
    var streak: Int {
        var count = 0
        var cursor = now
        if !isComplete(cursor) { cursor = Store.date(daysAgo: 1, from: cursor) }
        while isComplete(cursor), count < 3650 {
            count += 1
            cursor = Store.date(daysAgo: 1, from: cursor)
        }
        return count
    }

    /// The last `days` days, oldest first, each with its own completion state.
    func recentDays(_ days: Int = 7) -> [DayStamp] {
        stride(from: days - 1, through: 0, by: -1).map { offset in
            let day = Store.date(daysAgo: offset, from: now)
            return DayStamp(date: day, complete: isComplete(day))
        }
    }

    // MARK: - Edits

    func toggle(_ todo: Todo) {
        refreshTodayRequirement()
        let key = Store.key(for: now)
        var done = Set(log[key] ?? [])
        if done.contains(todo.id) {
            done.remove(todo.id)
        } else {
            done.insert(todo.id)
        }
        log[key] = Array(done)
        save()
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(Todo(id: UUID().uuidString, title: trimmed))
        refreshTodayRequirement()
        save()
    }

    func rename(_ todo: Todo, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        if trimmed.isEmpty {
            remove(todo)
        } else {
            todos[index].title = trimmed
            refreshTodayRequirement()
            save()
        }
    }

    func remove(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        for (key, ids) in log {
            log[key] = ids.filter { $0 != todo.id }
        }
        // Deleting a task also deletes it from what past days were required to punch,
        // so a finished day never comes undone because a task was retired.
        for (key, ids) in needed {
            needed[key] = ids.filter { $0 != todo.id }
        }
        refreshTodayRequirement()
        save()
    }

    func setFloating(_ value: Bool) {
        floating = value
        save()
    }

    func summon() {
        summonTick += 1
    }

    func rememberFrame(_ origin: CGPoint) {
        frameOrigin = origin
        save()
    }

    /// Drop today's marks and yesterday's, leaving the completed days intact. Offered
    /// from the menu as an escape hatch, never as a habit.
    func resetToday() {
        log[Store.key(for: now)] = []
        save()
    }

    func save() {
        let state = SavedState(todos: todos,
                               log: log,
                               needed: needed,
                               floating: floating,
                               frameX: frameOrigin.map { Double($0.x) },
                               frameY: frameOrigin.map { Double($0.y) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: dataURL, options: .atomic)
    }
}
