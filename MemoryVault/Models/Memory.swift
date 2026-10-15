import Foundation
import SwiftData

enum Tone: String, Codable, CaseIterable, Identifiable {
    case positive, neutral, negative, mixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .positive: "Positive"
        case .neutral: "Neutral"
        case .negative: "Negative"
        case .mixed: "Bittersweet"
        }
    }

    var emoji: String {
        switch self {
        case .positive: "☀️"
        case .neutral: "🌤️"
        case .negative: "🌧️"
        case .mixed: "🌦️"
        }
    }
}

enum AnalysisState: String, Codable {
    /// Saved, AI tagging not run yet.
    case pending
    /// Tagged.
    case done
    /// AI found people it needs you to confirm (e.g. which Alex).
    case needsReview
    /// The AI call failed; can be retried.
    case failed
    /// No API key configured.
    case skipped
}

@Model
final class Memory {
    var id: UUID = UUID()
    /// Exactly what you typed or said. Never rewritten by the AI.
    var text: String = ""
    /// Raw speech-to-text output, kept even if `text` is edited later.
    var transcript: String?
    var title: String = ""
    var summary: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Flattened MemoryDate (see `memoryDate`).
    var precisionRaw: String = DatePrecision.day.rawValue
    var year: Int?
    var month: Int?
    var day: Int?
    var season: Int?
    var isCirca: Bool = false
    var sortDate: Date = Date()
    /// True when the date is just "the day it was logged" rather than something you chose.
    var dateIsPlaceholder: Bool = false

    var categories: [String] = []
    var toneRaw: String = Tone.neutral.rawValue
    var isFavorite: Bool = false
    var audioFileNames: [String] = []

    var analysisStateRaw: String = AnalysisState.pending.rawValue
    /// Stored AI analysis while waiting for you to review it.
    var analysisJSON: String?
    var analysisError: String?

    @Relationship(inverse: \Person.memories) var people: [Person] = []

    init(text: String, date: MemoryDate) {
        self.text = text
        self.precisionRaw = date.precision.rawValue
        self.year = date.year
        self.month = date.month
        self.day = date.day
        self.season = date.season
        self.isCirca = date.isCirca
        self.sortDate = date.sortDate
    }

    var memoryDate: MemoryDate {
        get {
            MemoryDate(
                precision: DatePrecision(rawValue: precisionRaw) ?? .unknown,
                year: year, month: month, day: day, season: season, isCirca: isCirca
            )
        }
        set {
            precisionRaw = newValue.precision.rawValue
            year = newValue.year
            month = newValue.month
            day = newValue.day
            season = newValue.season
            isCirca = newValue.isCirca
            sortDate = newValue.sortDate
        }
    }

    var tone: Tone {
        get { Tone(rawValue: toneRaw) ?? .neutral }
        set { toneRaw = newValue.rawValue }
    }

    var analysisState: AnalysisState {
        get { AnalysisState(rawValue: analysisStateRaw) ?? .pending }
        set { analysisStateRaw = newValue.rawValue }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return firstLine.count > 60 ? String(firstLine.prefix(57)) + "…" : (firstLine.isEmpty ? "Untitled memory" : firstLine)
    }

    var sortedPeople: [Person] {
        people.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var audioURLs: [URL] { audioFileNames.map(AudioStorage.url(for:)) }

    func matches(search query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        if text.localizedStandardContains(q) || title.localizedStandardContains(q) || summary.localizedStandardContains(q) {
            return true
        }
        if people.contains(where: { $0.allNames.contains { $0.localizedStandardContains(q) } }) { return true }
        return categories.contains { CategoryCatalog.info(for: $0).label.localizedStandardContains(q) }
    }
}
