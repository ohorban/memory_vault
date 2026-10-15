import SwiftUI

/// Month grid. Days with exactly-dated memories get a dot; month- and season-level
/// memories are listed under "Sometime in …".
struct CalendarBrowseView: View {
    let memories: [Memory]

    @State private var monthStart = CalendarBrowseView.startOfMonth(Date())
    @State private var selectedDay: Int?

    private var calendar: Calendar { Calendar.current }
    private var year: Int { calendar.component(.year, from: monthStart) }
    private var month: Int { calendar.component(.month, from: monthStart) }

    private var exactByDay: [Int: [Memory]] {
        var result: [Int: [Memory]] = [:]
        for memory in memories {
            let date = memory.memoryDate
            guard date.effectivePrecision == .day, date.year == year, date.month == month, let day = date.day else { continue }
            result[day, default: []].append(memory)
        }
        return result
    }

    private var approximate: [Memory] {
        memories.filter { $0.memoryDate.loosely(coversYear: year, month: month) }
    }

    private var yearsWithMemories: [Int] {
        Array(Set(memories.compactMap(\.year))).sorted(by: >)
    }

    private var cells: [Int?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        let byDay = exactByDay
        List {
            Section {
                header
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day, count: byDay[day]?.count ?? 0)
                        } else {
                            Color.clear.frame(height: 40)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if let selectedDay {
                Section(dayTitle(selectedDay)) {
                    let items = byDay[selectedDay] ?? []
                    if items.isEmpty {
                        Text("Nothing logged for this day.").foregroundStyle(.secondary)
                    }
                    ForEach(items) { memory in
                        NavigationLink(value: memory) { MemoryRow(memory: memory) }
                    }
                }
            } else {
                let monthItems = byDay.keys.sorted().flatMap { byDay[$0] ?? [] }
                if !monthItems.isEmpty {
                    Section("This month") {
                        ForEach(monthItems) { memory in
                            NavigationLink(value: memory) { MemoryRow(memory: memory) }
                        }
                    }
                }
            }

            if !approximate.isEmpty {
                Section("Sometime in \(MemoryDate.monthName(month)) \(String(year))") {
                    ForEach(approximate) { memory in
                        NavigationLink(value: memory) { MemoryRow(memory: memory) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").padding(8) }
            Spacer()
            Menu {
                Button("This month") { go(to: Date()) }
                if !yearsWithMemories.isEmpty {
                    Section("Jump to year") {
                        ForEach(yearsWithMemories, id: \.self) { y in
                            Button(String(y)) { jump(toYear: y) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(MemoryDate.monthName(month)) \(String(year))").font(.headline)
                    Image(systemName: "chevron.down").font(.caption)
                }
            }
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").padding(8) }
        }
        .buttonStyle(.borderless)
    }

    private func dayCell(_ day: Int, count: Int) -> some View {
        let isSelected = selectedDay == day
        let isToday = calendar.isDateInToday(calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? .distantPast)
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : (isToday ? Color.accentColor : Color.primary))
                Circle()
                    .fill(count > 0 ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayTitle(_ day: Int) -> String {
        let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        return date.formatted(date: .complete, time: .omitted)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthStart) {
            monthStart = next
            selectedDay = nil
        }
    }

    private func go(to date: Date) {
        monthStart = Self.startOfMonth(date)
        selectedDay = nil
    }

    /// Opens the most recent month in that year that has a memory.
    private func jump(toYear y: Int) {
        let monthsWithMemories = memories.filter { $0.year == y }.compactMap(\.month)
        let target = monthsWithMemories.max() ?? 1
        go(to: calendar.date(from: DateComponents(year: y, month: target, day: 1)) ?? monthStart)
    }

    static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}
