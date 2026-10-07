import Combine
import Foundation
import SwiftUI

struct Todo: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    /// The day this item belongs to. Every item belongs to exactly one day: the card is a
    /// per-day list, so tomorrow starts empty and yesterday lives on in the history.
    /// nil only ever appears in data written by an older build — the store re-dates those
    /// to the previous day on launch (see migrateLegacyItems).
    var day: String? = nil
}

/// One day in the stamp column.
struct DayStamp: Identifiable {
    var id: Date { date }
    let date: Date
    let complete: Bool
}

/// One day in the history drawer: what that day was asked to punch, and what it did.
struct HistoryDay: Identifiable {
    struct Entry: Identifiable {
        let id: String
        let title: String
        let done: Bool
    }

    var id: Date { date }
    let date: Date
    let complete: Bool
    let hasRecord: Bool
    let entries: [Entry]

    var doneCount: Int { entries.filter(\.done).count }
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
    /// Card size the user dragged out. Missing means "never touched".
    var cardWidth: Double?
    /// Height of the task area. Missing (or nil) means "as tall as the tasks are".
    var listHeight: Double?
    var historyOpen: Bool?
    var tomorrowOpen: Bool?
}

/// Everything the card knows: today's list, the completion log keyed by calendar day,
/// and where the user left the card. One JSON file, no network, no account.
final class Store: ObservableObject {
    @Published var todos: [Todo]
    @Published var log: [String: [String]]
    @Published var needed: [String: [String]]
    @Published var floating: Bool
    /// Width of the card, dragged from its side edges.
    @Published var cardWidth: Double
    /// Height of the task area, dragged from the bottom edge. nil means fit the content.
    @Published var listHeight: Double?
    @Published var historyOpen: Bool
    /// Whether the "tomorrow" drawer is pulled out.
    @Published var tomorrowOpen: Bool
    /// Height the task area currently wants when nothing has been dragged. Kept so the
    /// bottom edge can start from where the card already is.
    @Published private(set) var measuredListHeight: Double = 0
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

    static let defaultWidth: Double = 292
    static let minWidth: Double = 240
    static let maxWidth: Double = 680
    static let minListHeight: Double = 84
    static let maxListHeight: Double = 900

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
            cardWidth = saved.cardWidth ?? Store.defaultWidth
            listHeight = saved.listHeight
            historyOpen = saved.historyOpen ?? false
            tomorrowOpen = saved.tomorrowOpen ?? false
            if let x = saved.frameX, let y = saved.frameY {
                frameOrigin = CGPoint(x: x, y: y)
            }
        } else {
            // The examples belong to today, like everything else on the card.
            let today = Store.key(for: Date())
            todos = Store.starterTodos.map { todo in
                var copy = todo
                copy.day = today
                return copy
            }
            log = [:]
            needed = [:]
            floating = true
            cardWidth = Store.defaultWidth
            listHeight = nil
            historyOpen = false
            tomorrowOpen = false
        }
        clock = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.advanceClock(to: date) }
        // Data from an older build has undated items; give them a day so today is clean.
        migrateLegacyItems()
    }

    // MARK: - Days

    static func key(for date: Date) -> String { keyFormatter.string(from: date) }

    private static func date(daysAgo: Int, from now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }

    func doneIDs(on date: Date) -> Set<String> {
        Set(log[Store.key(for: date)] ?? [])
    }

    // MARK: - Today, tomorrow, and recurring

    var todayKey: String { Store.key(for: now) }

    var tomorrow: Date { Store.date(daysAgo: -1, from: now) }
    var tomorrowKey: String { Store.key(for: tomorrow) }

    /// The list for one particular day, and nothing else: yesterday's items do not come
    /// along, and tomorrow's wait in their own drawer.
    func todos(on date: Date) -> [Todo] {
        let key = Store.key(for: date)
        return todos.filter { $0.day == key }
    }

    var todayTodos: [Todo] { todos(on: now) }

    /// The items waiting for tomorrow, in the order they were written.
    var tomorrowTodos: [Todo] {
        let key = tomorrowKey
        return todos.filter { $0.day == key }
    }

    /// Short label for a day, for the drawer header.
    static func shortDay(_ date: Date) -> String {
        shortDayFormatter.string(from: date)
    }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd EEE"
        return formatter
    }()

    /// Whether a task is punched on the card's current day. Deliberately no default
    /// date parameter: a default of `Date()` would quietly mean "the wall clock today",
    /// which is a different day from the card's whenever the clock has been moved.
    func isDone(_ todo: Todo) -> Bool {
        doneIDs(on: now).contains(todo.id)
    }

    func isDone(_ todo: Todo, on date: Date) -> Bool {
        doneIDs(on: date).contains(todo.id)
    }

    func isComplete(_ date: Date) -> Bool {
        // Days the card recorded carry their own requirement. For any day it never got
        // around to recording, today's list is the only honest guess.
        let required = needed[Store.key(for: date)] ?? todos(on: date).map(\.id)
        guard !required.isEmpty else { return false }
        let done = doneIDs(on: date)
        return required.allSatisfy { done.contains($0) }
    }

    /// Today's requirement always mirrors today's list: a task written today has to be
    /// punched today, and days already finished keep the requirement they were judged by.
    private func refreshTodayRequirement() {
        needed[todayKey] = todayTodos.map(\.id)
    }

    var doneCount: Int {
        let done = doneIDs(on: now)
        return todayTodos.filter { done.contains($0.id) }.count
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

    /// The last `days` days, newest first, each with the tasks it was asked to punch and
    /// whether they were punched. Titles come from today's list, so a retired task leaves
    /// no orphan line behind.
    func history(days: Int = 7) -> [HistoryDay] {
        let titles = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0.title) })
        return stride(from: 0, to: days, by: 1).map { offset in
            let day = Store.date(daysAgo: offset, from: now)
            let key = Store.key(for: day)
            // What that day asked for: its recorded requirement, what it actually
            // punched, or — for a day nobody finished — the list it was given.
            let required = needed[key] ?? log[key] ?? todos(on: day).map(\.id)
            let done = Set(log[key] ?? [])
            let entries = required.compactMap { id -> HistoryDay.Entry? in
                guard let title = titles[id] else { return nil }
                return HistoryDay.Entry(id: id, title: title, done: done.contains(id))
            }
            return HistoryDay(date: day,
                              complete: isComplete(day),
                              hasRecord: !entries.isEmpty,
                              entries: entries)
        }
    }

    /// Days in the recent window that finished.
    func completedDays(in days: Int = 7) -> Int {
        recentDays(days).filter(\.complete).count
    }

    // MARK: - Size

    func setCardWidth(_ width: Double, persist: Bool = true) {
        let clamped = min(max(width.rounded(), Store.minWidth), Store.maxWidth)
        guard clamped != cardWidth else { return }
        cardWidth = clamped
        if persist { save() }
    }

    /// nil restores "as tall as the tasks are".
    func setListHeight(_ height: Double?, persist: Bool = true) {
        guard let height else {
            guard listHeight != nil else { return }
            listHeight = nil
            if persist { save() }
            return
        }
        let clamped = min(max(height.rounded(), Store.minListHeight), Store.maxListHeight)
        guard clamped != listHeight else { return }
        listHeight = clamped
        if persist { save() }
    }

    /// Reported by the card after layout; only meaningful while the height is automatic.
    func noteListHeight(_ height: Double) {
        guard listHeight == nil, height > 1, abs(height - measuredListHeight) > 0.5 else { return }
        measuredListHeight = height
    }

    func resetCardSize() {
        cardWidth = Store.defaultWidth
        listHeight = nil
        save()
    }

    func setHistoryOpen(_ open: Bool) {
        guard open != historyOpen else { return }
        historyOpen = open
        save()
    }

    func setTomorrowOpen(_ open: Bool) {
        guard open != tomorrowOpen else { return }
        tomorrowOpen = open
        save()
    }

    // MARK: - Edits

    func toggle(_ todo: Todo) {
        // Only today's list can be punched. An item planned for tomorrow must not be
        // able to leave a hole on today's card.
        guard todayTodos.contains(where: { $0.id == todo.id }) else { return }
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
        // Belongs to today only. Tomorrow's card starts with tomorrow's list, and this
        // one moves into the history with the rest of the day.
        todos.append(Todo(id: UUID().uuidString, title: trimmed, day: todayKey))
        refreshTodayRequirement()
        save()
    }

    /// Writes an item for tomorrow only. It is not required today, so today's tally and
    /// the run stay untouched; tomorrow it is simply part of that day's list.
    func addTomorrow(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.append(Todo(id: UUID().uuidString, title: trimmed, day: tomorrowKey))
        save()
    }

    /// Items written before the card became a per-day list carry no date. They are
    /// stamped with the previous day, which is what makes today start clean — and they
    /// stay visible in the history for that day, with the punches they earned.
    func migrateLegacyItems() {
        let fallbackDay = Store.key(for: Store.date(daysAgo: 1, from: now))
        var migrated: [String] = []
        for index in todos.indices where todos[index].day == nil {
            todos[index].day = fallbackDay
            migrated.append(todos[index].id)
        }
        guard !migrated.isEmpty else { return }
        // Yesterday's card asked for those items, so add them to whatever yesterday was
        // already recorded as requiring — nothing the user wrote becomes invisible.
        var yesterday = needed[fallbackDay] ?? []
        for id in migrated where !yesterday.contains(id) {
            yesterday.append(id)
        }
        needed[fallbackDay] = yesterday
        // Today's list is now just today's items, so today's requirement has to be
        // rewritten too; otherwise the day could never be completed (it would still be
        // waiting for items that belong to yesterday).
        refreshTodayRequirement()
        save()
    }

    /// The card's clock. The timer calls it, and the checks call it to travel a day.
    /// Rolling over needs no other work: the new day simply has its own — usually empty —
    /// list, and yesterday's stays visible in the history only.
    func advanceClock(to date: Date) {
        now = date
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
                               frameY: frameOrigin.map { Double($0.y) },
                               cardWidth: cardWidth,
                               listHeight: listHeight,
                               historyOpen: historyOpen,
                               tomorrowOpen: tomorrowOpen)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: dataURL, options: .atomic)
    }
}
