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

        print("卡片尺寸")
        reopened.setCardWidth(120)
        check("宽度有下限", reopened.cardWidth == Store.minWidth, "got \(reopened.cardWidth)")
        reopened.setCardWidth(2_000)
        check("宽度有上限", reopened.cardWidth == Store.maxWidth, "got \(reopened.cardWidth)")
        reopened.setCardWidth(401.4)
        check("宽度取整到整点", reopened.cardWidth == 401, "got \(reopened.cardWidth)")
        reopened.setListHeight(10)
        check("任务区高度有下限", reopened.listHeight == Store.minListHeight,
              "got \(String(describing: reopened.listHeight))")
        reopened.setListHeight(20_000)
        check("任务区高度有上限", reopened.listHeight == Store.maxListHeight)
        reopened.setListHeight(nil)
        check("任务区可以回到自动高度", reopened.listHeight == nil)
        reopened.setCardWidth(Store.defaultWidth)
        check("宽度能回到默认", reopened.cardWidth == Store.defaultWidth)

        print("历史待办")
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let threeKey = Store.key(for: threeDaysAgo)
        reopened.needed[threeKey] = reopened.todos.map(\.id)
        reopened.log[threeKey] = [reopened.todos[0].id]
        let week = reopened.history(days: 7)
        check("历史是七天", week.count == 7)
        check("最新的一天在最上面", week[0].date > week[6].date)
        check("第一条是今天", Calendar.current.isDateInToday(week[0].date))
        check("今天有记录", week[0].hasRecord)
        check("今天的条目数等于任务数", week[0].entries.count == reopened.todos.count,
              "got \(week[0].entries.count)")
        check("今天全部打完", week[0].doneCount == reopened.todos.count)
        check("今天算已打卡", week[0].complete)
        check("昨天的记录还在", week[1].hasRecord && week[1].complete)
        check("三天前只打了第一个孔", week[3].doneCount == 1, "got \(week[3].doneCount)")
        check("三天前不算完成", !week[3].complete)
        check("三天前条目仍然完整", week[3].entries.count == reopened.todos.count)
        check("六天前没有记录", !week[6].hasRecord)
        // 今天和昨天是完整的；两天前没有记录，三天前只打了一个孔。
        check("最近七天完成天数", reopened.completedDays(in: 7) == 2,
              "got \(reopened.completedDays(in: 7))")

        print("尺寸与历史的存档")
        reopened.setCardWidth(420)
        reopened.setListHeight(260)
        reopened.setHistoryOpen(true)
        let reopened3 = Store(dataURL: url)
        check("宽度能存下来", reopened3.cardWidth == 420, "got \(reopened3.cardWidth)")
        check("任务区高度能存下来", reopened3.listHeight == 260,
              "got \(String(describing: reopened3.listHeight))")
        check("历史展开状态能存下来", reopened3.historyOpen)

        print("明日待办")
        let tomorrowKey = Store.key(for: tomorrow)
        let dayAfter = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let todayBefore = reopened3.todayTodos.count
        reopened3.addTomorrow(title: "  明天要读的论文  ")
        let planned = reopened3.tomorrowTodos
        check("能加明天的待办", planned.count == 1, "got \(planned.count)")
        check("标题去掉空白", planned.first?.title == "明天要读的论文")
        check("它带着明天的日期", planned.first?.day == tomorrowKey)
        check("今天的清单里没有它", !reopened3.todayTodos.contains { $0.id == planned.first?.id })
        check("今天的条目数没变", reopened3.todayTodos.count == todayBefore,
              "got \(reopened3.todayTodos.count)")
        check("明天的清单只有明天排的事", reopened3.todos(on: tomorrow).count == 1,
              "got \(reopened3.todos(on: tomorrow).count)")
        check("今天的事不会跟到明天",
              reopened3.todos(on: tomorrow).allSatisfy { $0.day == tomorrowKey })
        reopened3.addTomorrow(title: "   ")
        check("空标题被拒绝", reopened3.tomorrowTodos.count == 1)

        print("第二天：自动变成今日待办")
        let plannedID = planned.first!.id
        let todayIDsBefore = Set(reopened3.todayTodos.map(\.id))
        reopened3.advanceClock(to: tomorrow)
        check("时钟走到第二天", Calendar.current.isDate(reopened3.now, inSameDayAs: tomorrow))
        check("它进了今日清单", reopened3.todayTodos.contains { $0.id == plannedID })
        check("昨天的清单一条都没跟过来",
              reopened3.todayTodos.allSatisfy { !todayIDsBefore.contains($0.id) },
              "got \(reopened3.todayTodos.map(\.title))")
        check("今日清单只剩明天排过的那一件", reopened3.todayTodos.count == 1,
              "got \(reopened3.todayTodos.count)")
        check("明日抽屉空了", reopened3.tomorrowTodos.isEmpty)
        check("新的一天从零开始", reopened3.doneCount == 0, "got \(reopened3.doneCount)")
        check("新的一天还没完成", !reopened3.allDone)
        for todo in reopened3.todayTodos where !reopened3.isDone(todo) { reopened3.toggle(todo) }
        check("第二天可以全部打完", reopened3.allDone)
        check("打孔记录落在第二天", (reopened3.log[tomorrowKey] ?? []).contains(plannedID))
        check("新的一天在历史里是完成的", reopened3.isComplete(tomorrow))

        print("漏掉的一整天：今天清空，只留在历史里")
        let missedURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dailycheck-missed-\(UUID().uuidString).json")
        let missed = Store(dataURL: missedURL)
        missed.addTomorrow(title: "明天要做的重要事")
        let missedID = missed.tomorrowTodos.first!.id
        missed.advanceClock(to: tomorrow)
        check("到了那天它出现在今日清单", missed.todayTodos.contains { $0.id == missedID })
        missed.advanceClock(to: dayAfter)   // 那一天整天没打开，也一条都没打
        check("第二天今天的清单是空的", missed.todayTodos.isEmpty,
              "got \(missed.todayTodos.map(\.title))")
        check("没做完的也不会跟到今天", !missed.todayTodos.contains { $0.id == missedID })
        let missedHistory = missed.history(days: 7)
        check("它留在那天的历史里",
              missedHistory.contains { day in day.entries.contains { $0.id == missedID } })

        print("做完的明日待办不会顺延")
        let doneURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dailycheck-done-\(UUID().uuidString).json")
        let finished = Store(dataURL: doneURL)
        finished.addTomorrow(title: "做完的事")
        let finishedID = finished.tomorrowTodos.first!.id
        finished.advanceClock(to: tomorrow)
        finished.toggle(finished.todos.first { $0.id == finishedID }!)
        finished.advanceClock(to: dayAfter)
        check("做完的也不会回今天的清单", !finished.todayTodos.contains { $0.id == finishedID })
        check("但它留在那天被记住", (finished.log[tomorrowKey] ?? []).contains(finishedID))
        try? FileManager.default.removeItem(at: missedURL)
        try? FileManager.default.removeItem(at: doneURL)

        print("旧数据迁移：无日期的任务归到昨天，今天清空")
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let legacyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dailycheck-legacy-\(UUID().uuidString).json")
        let legacyPayload: [String: Any] = [
            "todos": [
                ["id": "old1", "title": "昨天记的事"],
                ["id": "old2", "title": "昨天记的另一件事"],
            ],
            "log": [yesterdayKey: ["old1", "old2"]],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: legacyPayload) {
            try? data.write(to: legacyURL)
        }
        let legacy = Store(dataURL: legacyURL)
        check("旧任务被归到昨天", legacy.todos.allSatisfy { $0.day == yesterdayKey },
              "got \(legacy.todos.map { $0.day ?? "nil" })")
        check("今天不显示昨天的事", legacy.todayTodos.isEmpty,
              "got \(legacy.todayTodos.map(\.title))")
        check("迁移时补上昨天的应打清单", legacy.needed[yesterdayKey] == ["old1", "old2"])
        check("昨天在历史里仍是完整的一天", legacy.isComplete(yesterdayDate))
        check("历史里还看得见那两条",
              legacy.history(days: 7).contains { day in
                  Calendar.current.isDate(day.date, inSameDayAs: yesterdayDate)
                      && day.entries.count == 2 && day.doneCount == 2
              })
        let legacyReopened = Store(dataURL: legacyURL)
        check("再次打开不会重复迁移", legacyReopened.todayTodos.isEmpty
                && legacyReopened.todos.allSatisfy { $0.day == yesterdayKey })
        try? FileManager.default.removeItem(at: legacyURL)

        try? FileManager.default.removeItem(at: url)
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
