import Foundation

// Headless checks for the card's logic. Run with ./build.sh --test.

@main
struct TestRunner {
    static var failures = 0

    static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok   \(label)")
        } else {
            failures += 1
            print("  FAIL \(label) \(detail)")
        }
    }

    static func main() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dailycheck-test-\(UUID().uuidString).json")

        print("first run")
        let store = Store(dataURL: url)
        check("starter list has three tasks", store.todos.count == 3, "got \(store.todos.count)")
        check("nothing is done yet", store.doneCount == 0)
        check("no run yet", store.streak == 0)
        check("the card is not stamped", !store.allDone)

        print("punching")

        let first = store.todos[0]
        store.toggle(first)
        check("one position punched", store.doneCount == 1)
        check("that task reads done", store.isDone(first))
        store.toggle(first)
        check("punching again clears it", store.doneCount == 0)

        print("a full day")
        for todo in store.todos { store.toggle(todo) }
        check("every position punched", store.allDone)
        check("today counts as one day", store.streak == 1)

        print("a run behind today")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayKey = Store.key(for: yesterday)
        store.log[yesterdayKey] = store.todos.map(\.id)
        store.needed[yesterdayKey] = store.todos.map(\.id)
        check("yesterday joins the run", store.streak == 2, "got \(store.streak)")

        print("a task written today does not rewrite yesterday")
        store.add(title: "今天才想加的一件")
        check("yesterday stays finished", store.isComplete(yesterday))
        // With today open again, the run counts only the days actually finished.
        check("yesterday still counts in the run", store.streak == 1, "got \(store.streak)")
        check("today is open again", !store.allDone)
        store.rename(store.todos.last!, to: "")

        print("an unfinished day ends the run")
        store.resetToday()
        check("today is clear again", store.doneCount == 0)
        check("the run survives an unfinished today", store.streak == 1, "got \(store.streak)")

        print("editing")
        store.add(title: "  泡脚  ")
        check("a task is added and trimmed", store.todos.last?.title == "泡脚")
        store.add(title: "   ")
        check("an empty task is refused", store.todos.count == 4)
        let added = store.todos.last!
        store.rename(added, to: "泡脚 15 分钟")
        check("a task can be renamed", store.todos.last?.title == "泡脚 15 分钟")
        store.rename(added, to: "")
        check("renaming to nothing removes it", store.todos.count == 3)

        print("the stamp column")
        for todo in store.todos where !store.isDone(todo) { store.toggle(todo) }
        let days = store.recentDays(7)
        check("seven days are shown", days.count == 7)
        check("they run oldest first", days[0].date < days[6].date)
        check("the last one is today", Calendar.current.isDateInToday(days[6].date))
        check("today is complete", days[6].complete)
        check("yesterday is complete", days[5].complete)
        check("six days ago is not", !days[0].complete)
        check("today plus yesterday is a two day run", store.streak == 2, "got \(store.streak)")

        print("persistence")
        store.add(title: "写今天的日志")
        store.toggle(store.todos[0])
        store.setFloating(false)
        store.rememberFrame(CGPoint(x: 120, y: 340))
        let reopened = Store(dataURL: url)
        check("tasks survive a relaunch", reopened.todos.map(\.title) == store.todos.map(\.title))
        check("today's punches survive", reopened.doneCount == store.doneCount)
        check("the run survives", reopened.streak == store.streak, "\(reopened.streak) vs \(store.streak)")
        check("the window position survives", reopened.frameOrigin == CGPoint(x: 120, y: 340))
        check("the window setting survives", reopened.floating == false)

        print("removing a task")
        let doomed = reopened.todos[0]
        reopened.remove(doomed)
        check("the task is gone", !reopened.todos.contains(where: { $0.id == doomed.id }))
        check("its punch is gone from the log",
              !(reopened.log[Store.key(for: Date())] ?? []).contains(doomed.id))

        print("rolling over to a new day")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        check("tomorrow carries no punches", (reopened.log[Store.key(for: tomorrow)] ?? []).isEmpty)
        check("tomorrow is not complete", !reopened.isComplete(tomorrow))
        check("an unpunched task keeps today open", !reopened.isComplete(Date()))
        for todo in reopened.todos where !reopened.isDone(todo) { reopened.toggle(todo) }
        check("punching the last position finishes the day", reopened.isComplete(Date()))
        check("and the run is today plus yesterday", reopened.streak == 2, "got \(reopened.streak)")

        try? FileManager.default.removeItem(at: url)
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
