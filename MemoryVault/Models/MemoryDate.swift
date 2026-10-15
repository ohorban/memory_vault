import Foundation

/// How precisely we know when a memory happened.
enum DatePrecision: String, Codable, CaseIterable, Identifiable {
    case day, month, season, year, decade, unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "Day"
        case .month: "Month"
        case .season: "Season"
        case .year: "Year"
        case .decade: "Decade"
        case .unknown: "Not sure"
        }
    }
}

enum Season: Int, Codable, CaseIterable, Identifiable {
    case winter = 1, spring, summer, fall

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .winter: "Winter"
        case .spring: "Spring"
        case .summer: "Summer"
        case .fall: "Fall"
        }
    }

    /// Months considered part of this season (northern hemisphere, same calendar year).
    var months: [Int] {
        switch self {
        case .winter: [12, 1, 2]
        case .spring: [3, 4, 5]
        case .summer: [6, 7, 8]
        case .fall: [9, 10, 11]
        }
    }

    var startMonth: Int {
        switch self {
        case .winter: 1
        case .spring: 3
        case .summer: 6
        case .fall: 9
        }
    }

    static func containing(month: Int) -> Season {
        allCases.first { $0.months.contains(month) } ?? .winter
    }
}

/// A possibly-approximate date: "March 14, 2019", "March 2019", "Summer 2019", "~2019", "1990s".
struct MemoryDate: Codable, Hashable {
    var precision: DatePrecision
    var year: Int?
    var month: Int?
    var day: Int?
    var season: Int?
    var isCirca: Bool = false

    static func exact(_ date: Date) -> MemoryDate {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return MemoryDate(precision: .day, year: c.year, month: c.month, day: c.day, season: nil, isCirca: false)
    }

    static var today: MemoryDate { exact(Date()) }

    static let unknown = MemoryDate(precision: .unknown)

    /// Precision after accounting for missing components.
    var effectivePrecision: DatePrecision {
        guard year != nil else { return .unknown }
        switch precision {
        case .day: return (month != nil && day != nil) ? .day : (month != nil ? .month : .year)
        case .month: return month != nil ? .month : .year
        case .season: return season != nil ? .season : .year
        default: return precision
        }
    }

    var exactDate: Date? {
        guard effectivePrecision == .day, let year, let month, let day else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    /// The start of the period, used for sorting. Unknown dates sort last.
    var sortDate: Date {
        let cal = Calendar.current
        func make(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? .distantPast
        }
        guard let year else { return .distantPast }
        switch effectivePrecision {
        case .day: return make(year, month ?? 1, day ?? 1)
        case .month: return make(year, month ?? 1, 1)
        case .season: return make(year, Season(rawValue: season ?? 1)?.startMonth ?? 1, 1)
        case .year: return make(year, 1, 1)
        case .decade: return make((year / 10) * 10, 1, 1)
        case .unknown: return .distantPast
        }
    }

    var displayText: String {
        let core: String
        switch effectivePrecision {
        case .day:
            core = exactDate?.formatted(date: .long, time: .omitted) ?? "Unknown date"
        case .month:
            core = "\(Self.monthName(month ?? 1)) \(String(year ?? 0))"
        case .season:
            core = "\(Season(rawValue: season ?? 1)?.label ?? "") \(String(year ?? 0))"
        case .year:
            core = String(year ?? 0)
        case .decade:
            core = "\(String(((year ?? 0) / 10) * 10))s"
        case .unknown:
            return "Date unknown"
        }
        return isCirca && effectivePrecision != .day ? "Around \(core)" : core
    }

    /// The label for the timeline section this date belongs to.
    var sectionTitle: String {
        switch effectivePrecision {
        case .unknown: "Undated"
        case .decade: "\(String(((year ?? 0) / 10) * 10))s"
        default: String(year ?? 0)
        }
    }

    var isToday: Bool { self == .today }

    /// Whether this approximate date covers the given month (used by the calendar).
    func loosely(coversYear y: Int, month m: Int) -> Bool {
        guard year == y else { return false }
        switch effectivePrecision {
        case .month: return month == m
        case .season: return Season(rawValue: season ?? 0)?.months.contains(m) ?? false
        default: return false
        }
    }

    static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }
}
