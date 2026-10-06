import AppKit
import SwiftUI

/// Lets the card tell the store how tall the task area wants to be, so the bottom edge
/// can be dragged from wherever the card already is.
private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WidgetView: View {
    @ObservedObject var store: Store
    /// Called when the card should get out of the way (Escape).
    var onHide: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    @State private var adding = false
    @State private var draft = ""
    @State private var editingID: String?
    @State private var editingText = ""
    @State private var hoverAdd = false
    @State private var hoverHistory = false
    @State private var summonPop = false
    @FocusState private var draftFocused: Bool
    @FocusState private var editFocused: Bool

    private let rowHeight: CGFloat = 30
    private let historyRowHeight: CGFloat = 19
    private let marginX: CGFloat = 19
    private let historyWindowHeight: CGFloat = 266

    private static let dateLine: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd EEE"
        return formatter
    }()

    var body: some View {
        card
            .environment(\.cardTheme, CardTheme.of(scheme))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            titleRule
            list
            if store.historyOpen { historySection }
            footerRule
            footer
        }
        .padding(.init(top: 13, leading: 15, bottom: 12, trailing: 15))
        .frame(width: CGFloat(store.cardWidth), alignment: .topLeading)
        .background(PaperCard())
        .onPreferenceChange(ListHeightKey.self) { store.noteListHeight(Double($0)) }
        // The card answers when it is called: a small nudge, no flashing.
        .scaleEffect(summonPop ? 1.012 : 1)
        .onChange(of: store.summonTick) { _ in
            summonPop = true
            withAnimation(.easeOut(duration: 0.3)) { summonPop = false }
        }
        .onExitCommand(perform: handleEscape)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: store.allDone)
        .animation(.easeOut(duration: 0.18), value: store.todos.map(\.id))
        .animation(.easeOut(duration: 0.18), value: adding)
        .animation(.easeOut(duration: 0.22), value: store.historyOpen)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("重要待办")
                    .font(Face.cardTitle)
                    .foregroundStyle(theme.ink)
                Text(Self.dateLine.string(from: store.now))
                    .font(Face.meta(10))
                    .tracking(0.6)
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer(minLength: 6)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(store.doneCount) / \(store.todos.count)")
                        .font(Face.meta(13, .semibold))
                        .foregroundStyle(store.allDone ? theme.stamp : theme.ink)
                    Text(store.allDone ? "全部完成" : "已完成")
                        .font(Face.meta(9, .regular))
                        .tracking(0.5)
                        .foregroundStyle(theme.inkSoft)
                }
                CollapseButton(action: onHide)
            }
        }
        .padding(.bottom, 9)
    }

    /// The card's printed title rule. It thickens once the day is stamped.
    private var titleRule: some View {
        Rectangle()
            .fill(theme.stamp.opacity(store.allDone ? 0.85 : 0.55))
            .frame(height: store.allDone ? 2 : 1)
    }

    // MARK: - Task list

    private var list: some View {
        Group {
            if store.todos.isEmpty {
                emptyState
            } else {
                rows
            }
            addRow
            historyRow
        }
        .overlay(alignment: .leading) { marginRule }
    }

    private var marginRule: some View {
        Rectangle()
            .fill(theme.marginRule.opacity(0.75))
            .frame(width: 1)
            .offset(x: marginX)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var rows: some View {
        let content = VStack(spacing: 0) {
            ForEach(store.todos) { todo in
                TaskRow(todo: todo,
                        done: store.isDone(todo, on: store.now),
                        isLast: todo.id == store.todos.last?.id,
                        height: rowHeight,
                        isEditing: editingID == todo.id,
                        editText: $editingText,
                        editFocused: $editFocused,
                        onTap: { punch(todo) },
                        onStartEditing: { startEditing(todo) },
                        onCommitEditing: { commitEditing(todo) },
                        onDelete: { store.remove(todo) })
            }
        }
        if let limit = store.listHeight {
            // The user dragged the bottom edge: hold that height and scroll the rest.
            ScrollView(.vertical) { content }
                .frame(height: CGFloat(limit))
                .scrollIndicators(.automatic)
        } else {
            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                    }
                )
        }
    }

    @ViewBuilder
    private var addRow: some View {
        if adding {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.stamp)
                    .frame(width: 15)
                TextField("每天都要做的一件事…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Face.task)
                    .foregroundStyle(theme.ink)
                    .focused($draftFocused)
                    .onSubmit(commitDraft)
                Button(action: cancelDraft) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.inkSoft)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("不加了")
            }
            .frame(height: rowHeight)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.rule).frame(height: 1)
            }
            .onAppear { draftFocused = true }
        } else {
            Button(action: { adding = true }) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(hoverAdd ? theme.stamp : theme.inkSoft)
                        .frame(width: 15)
                    Text("添加一项")
                        .font(Face.task)
                        .foregroundStyle(hoverAdd ? theme.ink : theme.inkSoft)
                    Spacer(minLength: 0)
                }
                .frame(height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverAdd = $0 }
            .help("添加一个每天都做的事")
        }
    }

    /// The way into the history: it expands downwards, inside the same card.
    private var historyRow: some View {
        Button(action: { store.setHistoryOpen(!store.historyOpen) }) {
            HStack(spacing: 9) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hoverHistory ? theme.stamp : theme.inkSoft)
                    .frame(width: 15)
                Text(store.historyOpen ? "收起历史待办" : "查看历史待办")
                    .font(Face.task)
                    .foregroundStyle(hoverHistory ? theme.ink : theme.inkSoft)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.inkSoft)
                    .rotationEffect(.degrees(store.historyOpen ? 180 : 0))
            }
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverHistory = $0 }
        .help(store.historyOpen ? "收起历史" : "看最近 7 天的打卡记录")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("这张卡还没有印上内容")
                .font(Face.task)
                .foregroundStyle(theme.ink)
            Text("写下每天都要做的事，明天它会自己清空。")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.rule).frame(height: 1)
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(theme.rule).frame(height: 1)
            HStack(spacing: 6) {
                Text("最近 7 天")
                    .font(Face.meta(10, .semibold))
                    .tracking(0.4)
                    .foregroundStyle(theme.ink)
                Spacer(minLength: 4)
                Text("完成 \(store.completedDays(in: 7)) / 7 天")
                    .font(Face.meta(10))
                    .foregroundStyle(theme.inkSoft)
            }
            .padding(.vertical, 7)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    let days = store.history(days: 7)
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        HistoryDayBlock(day: day,
                                        isToday: Calendar.current.isDateInToday(day.date),
                                        isLast: index == days.count - 1,
                                        rowHeight: historyRowHeight)
                    }
                }
            }
            .frame(height: historyWindowHeight)
            .scrollIndicators(.automatic)
        }
    }

    // MARK: - Footer

    private var footerRule: some View {
        Rectangle().fill(theme.rule).frame(height: 1)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(runLine)
                .font(Face.meta(10))
                .foregroundStyle(theme.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 4)
            if store.allDone {
                Stamp()
                    .transition(.scale(scale: 1.5).combined(with: .opacity))
            }
            dayStrip
        }
        // Fixed height so the card does not jump when the stamp arrives.
        .frame(height: 20)
        .padding(.top, 9)
    }

    private var runLine: String {
        store.streak == 0 ? "从今天开始" : "连续 \(store.streak) 天"
    }

    private var dayStrip: some View {
        HStack(spacing: 3) {
            ForEach(store.recentDays(7)) { day in
                DayCell(date: day.date,
                        complete: day.complete,
                        isToday: Calendar.current.isDate(day.date, inSameDayAs: store.now))
            }
        }
    }

    private var theme: CardTheme { CardTheme.of(scheme) }

    // MARK: - Actions

    private func punch(_ todo: Todo) {
        let wasDone = store.isDone(todo, on: store.now)
        store.toggle(todo)
        if !wasDone {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func commitDraft() {
        let title = draft
        draft = ""
        store.add(title: title)
        draftFocused = true
    }

    private func cancelDraft() {
        draft = ""
        adding = false
        draftFocused = false
    }

    private func startEditing(_ todo: Todo) {
        editingText = todo.title
        editingID = todo.id
        editFocused = true
    }

    private func commitEditing(_ todo: Todo) {
        store.rename(todo, to: editingText)
        editingID = nil
    }

    /// Escape backs out of whatever is being typed first, and only then dismisses the
    /// card. Dismissing hides the panel; the menu bar icon or opening the app again
    /// brings it back.
    private func handleEscape() {
        if adding {
            cancelDraft()
        } else if editingID != nil {
            editingID = nil
        } else {
            onHide()
        }
    }
}

// MARK: - Row

private struct TaskRow: View {
    @Environment(\.cardTheme) private var theme

    let todo: Todo
    let done: Bool
    let isLast: Bool
    let height: CGFloat
    let isEditing: Bool
    @Binding var editText: String
    var editFocused: FocusState<Bool>.Binding
    let onTap: () -> Void
    let onStartEditing: () -> Void
    let onCommitEditing: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 9) {
            Punch(done: done, pulse: pulse)

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(Face.task)
                    .foregroundStyle(theme.ink)
                    .focused(editFocused)
                    .onSubmit(onCommitEditing)
            } else {
                // No line limit: a long task wraps and the row grows, so nothing is
                // hidden just because the card is narrow.
                Text(todo.title)
                    .font(done ? Face.taskDone : Face.task)
                    .strikethrough(done, color: theme.inkSoft)
                    .foregroundStyle(done ? theme.inkSoft : theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)

            if hovered && !isEditing {
                HStack(spacing: 2) {
                    RowAction(symbol: "pencil", help: "改标题", action: onStartEditing)
                    RowAction(symbol: "xmark", help: "不再做这一项", action: onDelete)
                }
            }
        }
        .padding(.vertical, 5)
        .frame(minHeight: height)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditing { onCommitEditing() } else { onTap() }
        }
        .onHover { hovered = $0 }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.rule)
                .frame(height: 1)
                .opacity(isLast ? 0 : 1)
        }
        .onChange(of: done) { value in
            guard value else { return }
            pulse = true
            withAnimation(.easeOut(duration: 0.45)) { pulse = false }
        }
    }
}

/// The two quiet row actions that appear under the pointer.
private struct RowAction: View {
    @Environment(\.cardTheme) private var theme

    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(hovered ? theme.stamp : theme.inkSoft)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

/// Puts the card away. This is the control the user can always see, so hiding never
/// depends on the menu bar icon being reachable.
private struct CollapseButton: View {
    @Environment(\.cardTheme) private var theme

    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovered ? theme.stamp : theme.inkSoft)
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(hovered ? theme.hover : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("收起这张卡（⌥⌘T 可以再叫回来）")
        .accessibilityLabel("收起这张卡")
    }
}

// MARK: - History blocks

/// One day in the history drawer: the date and its tally on the first line, then that
/// day's tasks with the punches it actually got.
private struct HistoryDayBlock: View {
    @Environment(\.cardTheme) private var theme

    let day: HistoryDay
    let isToday: Bool
    let isLast: Bool
    let rowHeight: CGFloat

    private static let label: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd EEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(isToday ? "今天" : Self.label.string(from: day.date))
                    .font(Face.meta(10, isToday ? .semibold : .medium))
                    .foregroundStyle(isToday ? theme.ink : theme.inkSoft)
                Spacer(minLength: 4)
                if day.hasRecord {
                    if day.complete { Stamp(compact: true) }
                    Text("\(day.doneCount) / \(day.entries.count)")
                        .font(Face.meta(9.5, day.complete ? .semibold : .regular))
                        .foregroundStyle(day.complete ? theme.stamp : theme.inkSoft)
                }
            }
            .frame(height: 20)

            if day.hasRecord {
                ForEach(day.entries) { entry in
                    HStack(spacing: 7) {
                        Punch(done: entry.done, pulse: false, size: 10)
                        Text(entry.title)
                            .font(.system(size: 11))
                            .foregroundStyle(entry.done ? theme.inkSoft : theme.ink)
                            .strikethrough(entry.done, color: theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: rowHeight, alignment: .leading)
                }
            } else {
                Text(isToday ? "今天还没有记录" : "没有记录")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.inkSoft.opacity(0.85))
                    .frame(minHeight: rowHeight, alignment: .leading)
            }

            if !isLast {
                Rectangle()
                    .fill(theme.rule.opacity(0.7))
                    .frame(height: 1)
                    .padding(.top, 5)
                    .padding(.bottom, 5)
            }
        }
    }
}

/// One position on the card. An unfinished task is a hollow outline; finishing it
/// leaves a solid stamp behind an ink ring that expands once and fades.
private struct Punch: View {
    @Environment(\.cardTheme) private var theme

    let done: Bool
    let pulse: Bool
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.stamp, lineWidth: 1)
                .scaleEffect(pulse ? 1 : 2.1)
                .opacity(pulse ? 0.6 : 0)

            Circle()
                .strokeBorder(theme.marginRule, lineWidth: done ? 0 : 1)
                .background(Circle().fill(theme.paper))

            Circle()
                .fill(theme.stamp)
                .scaleEffect(done ? 1 : 0.3)
                .opacity(done ? 1 : 0)

            Image(systemName: "checkmark")
                .font(.system(size: size * 0.47, weight: .bold))
                .foregroundStyle(theme.paper)
                .scaleEffect(done ? 1 : 0.4)
                .opacity(done ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: done)
    }
}

/// A dated stamp cell, the way a library card records the days a book came back.
private struct DayCell: View {
    @Environment(\.cardTheme) private var theme

    let date: Date
    let complete: Bool
    let isToday: Bool

    private static let number: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        Text(Self.number.string(from: date))
            .font(Face.meta(9, complete ? .semibold : .regular))
            .foregroundStyle(complete ? theme.paper : theme.inkSoft)
            .frame(width: 13, height: 13)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(complete ? theme.stamp : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(complete ? .clear : theme.rule,
                                  lineWidth: isToday ? 1.2 : 0.8)
            )
            .help(isToday ? "今天" : Self.number.string(from: date) + " 日")
    }
}

/// The mark a finished day earns.
struct Stamp: View {
    @Environment(\.cardTheme) private var theme
    var compact = false

    var body: some View {
        Text("已打卡")
            .font(compact ? .system(size: 9, weight: .bold) : Face.stampText)
            .tracking(compact ? 1.2 : 2)
            .foregroundStyle(theme.stamp)
            .padding(.horizontal, compact ? 4 : 5)
            .padding(.vertical, compact ? 1 : 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(theme.stamp, lineWidth: compact ? 1 : 1.4)
            )
            .rotationEffect(.degrees(-6))
            .opacity(0.92)
    }
}
