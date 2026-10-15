import Foundation
import SwiftData

/// How one detected mention ("Alex") gets resolved to a person in your contacts.
struct MentionResolution: Identifiable {
    enum Choice: Hashable {
        case existing(UUID)
        case createNew
        case ignore
    }

    let id = UUID()
    let detected: MemoryAnalysis.DetectedPerson
    /// People this mention could be, most likely first.
    var candidateIDs: [UUID]
    var choice: Choice
    /// True when the app couldn't decide on its own (ambiguous or new person).
    var needsAttention: Bool
    var newName: String
    var newRelationship: String
}

/// Editable result of an analysis, shown in the review sheet or applied automatically.
struct ReviewDraft {
    var title: String
    var summary: String
    var categories: Set<String>
    var tone: Tone
    var mentions: [MentionResolution]
    var suggestedDate: MemoryDate?
    var dateEvidence: String
    var applyDate: Bool

    var needsReview: Bool { mentions.contains { $0.needsAttention } }
}

enum PersonMatcher {
    static func normalize(_ string: String) -> String {
        var s = string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        for prefix in ["my ", "our ", "the "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if s.hasSuffix("'s") || s.hasSuffix("’s") { s = String(s.dropLast(2)) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// People whose name, first name, nickname, or alias exactly matches the mention.
    static func localMatches(for mention: String, in people: [Person]) -> [Person] {
        let target = normalize(mention)
        guard !target.isEmpty else { return [] }
        return people.filter { person in
            person.allNames.contains { normalize($0) == target }
        }
    }

    static func resolve(
        _ detected: MemoryAnalysis.DetectedPerson,
        people: [Person],
        alreadyTagged: [Person]
    ) -> MentionResolution {
        let byID = Dictionary(people.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let best = byID[detected.bestMatchId]
        let local = localMatches(for: detected.mention, in: people)

        var candidates: [Person] = []
        let ordered = [best].compactMap { $0 } + detected.candidateIds.compactMap { byID[$0] } + local
        for person in ordered where !candidates.contains(where: { $0.id == person.id }) {
            candidates.append(person)
        }

        let suggestedName = detected.suggestedName.isEmpty ? detected.mention : detected.suggestedName
        var resolution = MentionResolution(
            detected: detected,
            candidateIDs: candidates.map(\.id),
            choice: .createNew,
            needsAttention: true,
            newName: suggestedName.capitalizedFirstLetter,
            newRelationship: detected.suggestedRelationship
        )

        // You already tagged one of the candidates by hand: that's the one.
        if let tagged = candidates.first(where: { c in alreadyTagged.contains { $0.id == c.id } }) {
            resolution.choice = .existing(tagged.id)
            resolution.needsAttention = false
            return resolution
        }

        switch candidates.count {
        case 0:
            resolution.choice = .createNew
            resolution.needsAttention = true
        case 1:
            let only = candidates[0]
            resolution.choice = .existing(only.id)
            let nameMatches = local.contains { $0.id == only.id }
            let confident = best?.id == only.id && detected.confidence != "low"
            resolution.needsAttention = !(nameMatches || confident)
        default:
            // Several people share the name: preselect the best guess, but always ask.
            resolution.choice = .existing((best ?? candidates[0]).id)
            resolution.needsAttention = true
        }
        return resolution
    }
}

@MainActor
enum MemoryProcessor {
    /// Runs AI tagging on a saved memory and returns a draft to apply or review.
    static func analyze(_ memory: Memory, context: ModelContext) async throws -> ReviewDraft {
        let client = try LLMFactory.makeClient()
        let people = (try? context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let analysis = try await MemoryAnalyzer(client: client).analyze(
            text: memory.text,
            people: people.map(PersonDescriptor.init),
            currentDate: memory.dateIsPlaceholder ? nil : memory.memoryDate,
            recordedAt: memory.createdAt,
            birthYear: AppSettings.birthYear
        )
        memory.analysisJSON = analysis.encodedString()
        memory.analysisError = nil
        return makeDraft(from: analysis, memory: memory, people: people)
    }

    /// Rebuilds a draft from a stored analysis (when you come back to finish tagging).
    static func storedDraft(for memory: Memory, context: ModelContext) -> ReviewDraft? {
        guard let json = memory.analysisJSON, let analysis = MemoryAnalysis.decode(json) else { return nil }
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        return makeDraft(from: analysis, memory: memory, people: people)
    }

    static func makeDraft(from analysis: MemoryAnalysis, memory: Memory, people: [Person]) -> ReviewDraft {
        let mentions = analysis.people.map {
            PersonMatcher.resolve($0, people: people, alreadyTagged: memory.people)
        }
        let suggested = analysis.dateHint.memoryDate(relativeTo: memory.createdAt)
        let differs = suggested != nil && suggested != memory.memoryDate
        return ReviewDraft(
            title: analysis.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: analysis.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            categories: Set(analysis.categories).union(memory.categories),
            tone: Tone(rawValue: analysis.tone) ?? .neutral,
            mentions: mentions,
            suggestedDate: differs ? suggested : nil,
            dateEvidence: analysis.dateHint.evidence,
            applyDate: differs && memory.dateIsPlaceholder
        )
    }

    /// Writes the draft onto the memory. Returns a short summary for a toast.
    @discardableResult
    static func apply(_ draft: ReviewDraft, to memory: Memory, context: ModelContext) -> String {
        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []

        if !draft.title.isEmpty { memory.title = draft.title }
        if !draft.summary.isEmpty { memory.summary = draft.summary }
        memory.categories = CategoryCatalog.ordered(draft.categories)
        memory.tone = draft.tone
        if draft.applyDate, let date = draft.suggestedDate {
            memory.memoryDate = date
            memory.dateIsPlaceholder = false
        }

        var tagged: [Person] = memory.people
        for mention in draft.mentions {
            switch mention.choice {
            case let .existing(id):
                guard let person = people.first(where: { $0.id == id }) else { continue }
                learnAlias(mention.detected.mention, for: person)
                if !tagged.contains(where: { $0.id == person.id }) { tagged.append(person) }
            case .createNew:
                let name = mention.newName.trimmingCharacters(in: .whitespacesAndNewlines)
                let person = Person(
                    name: name.isEmpty ? mention.detected.mention : name,
                    relationship: mention.newRelationship.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                context.insert(person)
                learnAlias(mention.detected.mention, for: person)
                tagged.append(person)
            case .ignore:
                continue
            }
        }
        memory.people = tagged
        memory.analysisState = .done
        memory.analysisJSON = nil
        memory.updatedAt = Date()
        try? context.save()

        var parts: [String] = []
        let names = tagged.map(\.displayName)
        if !names.isEmpty { parts.append(names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : "")) }
        if let first = memory.categories.first {
            let info = CategoryCatalog.info(for: first)
            parts.append("\(info.emoji) \(info.label)")
        }
        if draft.applyDate, draft.suggestedDate != nil { parts.append(memory.memoryDate.displayText) }
        return parts.isEmpty ? "Saved" : "Saved · " + parts.joined(separator: " · ")
    }

    /// Remember new ways of referring to someone ("Mama" → Mom) so matching improves over time.
    private static func learnAlias(_ mention: String, for person: Person) {
        let cleaned = mention.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let normalized = PersonMatcher.normalize(cleaned)
        guard normalized.count >= 2 else { return }
        let known = person.allNames.map(PersonMatcher.normalize)
        guard !known.contains(normalized) else { return }
        // Store without "my " so "my brother" becomes "brother".
        let alias = normalized.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        person.aliases.append(alias)
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
