import SwiftUI

/// Choose an exact or approximate date: a day, a month, a season, a year, a decade, or "not sure".
struct MemoryDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.birthYear) private var birthYear = 0

    let onSave: (MemoryDate) -> Void

    @State private var precision: DatePrecision
    @State private var exactDate: Date
    @State private var year: Int
    @State private var month: Int
    @State private var season: Season
    @State private var circa: Bool
    @State private var age: Int

    private let currentYear = Calendar.current.component(.year, from: Date())
    private var years: [Int] { Array((1900...currentYear).reversed()) }
    private var decades: [Int] { Array(stride(from: (currentYear / 10) * 10, through: 1900, by: -10)) }

    init(initial: MemoryDate, onSave: @escaping (MemoryDate) -> Void) {
        self.onSave = onSave
        let now = Date()
        let cal = Calendar.current
        let precision = initial.effectivePrecision
        let year = initial.year ?? cal.component(.year, from: now)
        _precision = State(initialValue: precision)
        _exactDate = State(initialValue: initial.exactDate ?? now)
        _year = State(initialValue: precision == .decade ? (year / 10) * 10 : year)
        _month = State(initialValue: initial.month ?? cal.component(.month, from: now))
        _season = State(initialValue: Season(rawValue: initial.season ?? 0)
            ?? Season.containing(month: initial.month ?? cal.component(.month, from: now)))
        _circa = State(initialValue: initial.isCirca)
        let storedBirthYear = UserDefaults.standard.integer(forKey: SettingsKey.birthYear)
        _age = State(initialValue: storedBirthYear > 1900 ? max(0, year - storedBirthYear) : 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Precision", selection: $precision) {
                        ForEach(DatePrecision.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Not sure exactly? Pick a month, season, year, or decade.")
                }

                switch precision {
                case .day:
                    Section {
                        DatePicker("Date", selection: $exactDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical)
                        HStack {
                            Button("Today") { exactDate = Date() }
                            Spacer()
                            Button("Yesterday") {
                                exactDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                case .month:
                    Section {
                        Picker("Month", selection: $month) {
                            ForEach(1...12, id: \.self) { Text(MemoryDate.monthName($0)).tag($0) }
                        }
                        yearPicker
                    }
                case .season:
                    Section {
                        Picker("Season", selection: $season) {
                            ForEach(Season.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        yearPicker
                    }
                case .year:
                    Section {
                        yearPicker
                        if birthYear > 1900 {
                            Stepper("I was about \(age)", value: $age, in: 0...max(0, currentYear - birthYear))
                                .onChange(of: age) {
                                    year = min(currentYear, birthYear + age)
                                    circa = true
                                }
                        }
                    } footer: {
                        if birthYear <= 1900 {
                            Text("Tip: add your birth year in Settings to date memories by your age.")
                        }
                    }
                case .decade:
                    Section {
                        Picker("Decade", selection: $year) {
                            ForEach(decades, id: \.self) { Text("\(String($0))s").tag($0) }
                        }
                        .pickerStyle(.wheel)
                    }
                case .unknown:
                    Section {
                        Text("That's fine — it'll be listed under “Undated”. You can set a date any time.")
                            .foregroundStyle(.secondary)
                    }
                }

                if precision != .day, precision != .unknown {
                    Section {
                        Toggle("Approximately (“around…”)", isOn: $circa)
                    }
                }

                Section {
                    LabeledContent("Will show as", value: result.displayText)
                }
            }
            .navigationTitle("When did it happen?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(result)
                        dismiss()
                    }
                }
            }
            .onChange(of: precision) { old, new in
                if new == .decade { year = (year / 10) * 10 }
                if old == .day {
                    let c = Calendar.current.dateComponents([.year, .month], from: exactDate)
                    year = new == .decade ? ((c.year ?? year) / 10) * 10 : (c.year ?? year)
                    month = c.month ?? month
                    season = Season.containing(month: month)
                }
            }
        }
    }

    private var yearPicker: some View {
        Picker("Year", selection: $year) {
            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(height: 140)
    }

    private var result: MemoryDate {
        switch precision {
        case .day:
            return .exact(exactDate)
        case .month:
            return MemoryDate(precision: .month, year: year, month: month, isCirca: circa)
        case .season:
            return MemoryDate(precision: .season, year: year, season: season.rawValue, isCirca: circa)
        case .year:
            return MemoryDate(precision: .year, year: year, isCirca: circa)
        case .decade:
            return MemoryDate(precision: .decade, year: (year / 10) * 10, isCirca: circa)
        case .unknown:
            return .unknown
        }
    }
}
