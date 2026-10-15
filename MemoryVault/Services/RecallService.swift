import Foundation
import Observation

/// Plain-value copy of a memory for building AI context off the main thread.
struct MemorySnapshot {
    let title: String
    let date: String
    let people: [String]
    let tags: [String]
    let tone: String
    let text: String

    init(_ memory: Memory) {
        title = memory.displayTitle
        date = memory.memoryDate.displayText
        people = memory.sortedPeople.map { p in p.subtitle.isEmpty ? p.displayName : "\(p.displayName) (\(p.subtitle))" }
        tags = memory.categories.map { CategoryCatalog.info(for: $0).label }
        tone = memory.tone.label
        text = memory.text
    }
}

enum SpeechOccasion: String, CaseIterable, Identifiable {
    case birthday = "Birthday", wedding = "Wedding toast", anniversary = "Anniversary", graduation = "Graduation",
         retirement = "Retirement", farewell = "Farewell", eulogy = "Eulogy / memorial", justBecause = "Just because"
    var id: String { rawValue }
}

enum SpeechStyle: String, CaseIterable, Identifiable {
    case heartfelt = "Heartfelt", funny = "Funny", balanced = "Funny + heartfelt", roast = "Gentle roast"
    var id: String { rawValue }
}

enum SpeechLength: String, CaseIterable, Identifiable {
    case short = "~1 min", medium = "~3 min", long = "~5 min"
    var id: String { rawValue }
    var words: Int {
        switch self {
        case .short: 150
        case .medium: 420
        case .long: 700
        }
    }
}

/// AI features that work over your memories: speech writing and "ask your vault".
enum RecallService {
    static func contextBlock(for memories: [MemorySnapshot]) -> String {
        var out = "<journal>\n"
        for (i, m) in memories.enumerated() {
            out += "<memory n=\"\(i + 1)\" title=\"\(m.title)\" date=\"\(m.date)\" tone=\"\(m.tone)\""
            if !m.people.isEmpty { out += " people=\"\(m.people.joined(separator: "; "))\"" }
            if !m.tags.isEmpty { out += " tags=\"\(m.tags.joined(separator: ", "))\"" }
            out += ">\n\(m.text)\n</memory>\n"
        }
        out += "</journal>"
        return out
    }

    static func writeSpeech(
        about personDescription: String,
        memories: [MemorySnapshot],
        occasion: SpeechOccasion,
        style: SpeechStyle,
        length: SpeechLength,
        speakerName: String,
        notes: String,
        outlineOnly: Bool
    ) async throws -> String {
        let client = try LLMFactory.makeClient()
        let system = """
        You help the user prepare a speech about someone in their life, using their private memory journal. \
        Use only the true stories in the journal. Never invent events, details, quotes, or names that aren't there; \
        you may add warm framing, transitions, and an opening and closing. Write in the first person as the user, \
        in natural spoken language that is easy to read aloud. Plain text with paragraph breaks, no markdown headings.
        """
        var prompt = "The speech is about: \(personDescription)\n"
        prompt += "Occasion: \(occasion.rawValue)\nStyle: \(style.rawValue)\n"
        if !speakerName.isEmpty { prompt += "Speaker (the user): \(speakerName)\n" }
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty { prompt += "Extra notes from the user: \(notes)\n" }
        if outlineOnly {
            prompt += """

            Don't write the speech yet. Pick the 5-8 stories from the journal that would work best for this occasion \
            and style. For each: the story title, one line on why it works, and a one-sentence way to tell it. \
            Finish with a suggested order and a theme that ties them together.
            """
        } else {
            prompt += """

            Write the speech, about \(length.words) words. Choose the stories that best fit the occasion and style \
            rather than cramming in everything. After the speech, add a line with "—" and then "Stories used:" \
            followed by the titles you drew on.
            """
        }
        let request = LLMRequest(
            system: system,
            context: contextBlock(for: memories),
            prompt: prompt,
            maxTokens: 8000,
            effort: .medium
        )
        return try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func ask(_ question: String, memories: [MemorySnapshot]) async throws -> String {
        let client = try LLMFactory.makeClient()
        let system = """
        You answer questions about the user's life using only their private memory journal below. \
        Speak to the user as "you". When you rely on a memory, mention its title and date so they can find it. \
        If the journal doesn't contain the answer, say so plainly and don't guess. Keep answers concise; \
        plain text, short lists are fine.
        """
        let request = LLMRequest(
            system: system,
            context: contextBlock(for: memories),
            prompt: question,
            maxTokens: 4000,
            effort: .medium
        )
        return try await client.complete(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// App-wide navigation state (tab selection and notification deep links).
@Observable
final class AppRouter {
    enum Tab: Hashable { case log, memories, people, settings }

    struct MemoryLink: Identifiable {
        let id: UUID
    }

    static let shared = AppRouter()

    var selectedTab: Tab = .log
    var openMemory: MemoryLink?
}
