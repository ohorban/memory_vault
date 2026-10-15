import Foundation

/// A plain-value snapshot of a Person, safe to hand to background work.
struct PersonDescriptor {
    let uuid: UUID
    let name: String
    let nickname: String
    let aliases: [String]
    let relationship: String
    let notes: String

    init(_ person: Person) {
        uuid = person.id
        name = person.name
        nickname = person.nickname
        aliases = person.aliases
        relationship = person.relationship
        notes = person.notes
    }
}

/// What Claude extracts from a memory. Field names map to snake_case JSON.
struct MemoryAnalysis: Codable {
    var title: String
    var summary: String
    var categories: [String]
    var tone: String
    var people: [DetectedPerson]
    var dateHint: DateHint

    struct DetectedPerson: Codable, Hashable {
        /// How the person is referred to in the story ("Alex", "my mom").
        var mention: String
        /// A short phrase from the story that helps identify them.
        var context: String
        /// Known people this could be. After `analyze` returns these are Person UUID strings.
        var candidateIds: [String]
        var bestMatchId: String
        var confidence: String
        var suggestedName: String
        var suggestedRelationship: String
    }

    struct DateHint: Codable {
        var found: Bool
        var precision: String
        var year: Int
        var month: Int
        var day: Int
        var season: Int
        var circa: Bool
        var evidence: String

        func memoryDate(relativeTo now: Date = Date()) -> MemoryDate? {
            guard found else { return nil }
            let currentYear = Calendar.current.component(.year, from: now)
            guard (1900...currentYear).contains(year) else { return nil }
            let validMonth = (1...12).contains(month) ? month : nil
            let validDay = (1...31).contains(day) ? day : nil
            let validSeason = (1...4).contains(season) ? season : nil
            var date = MemoryDate(precision: DatePrecision(rawValue: precision) ?? .year,
                                  year: year, month: validMonth, day: validDay, season: validSeason, isCirca: circa)
            if date.precision == .unknown { date.precision = .year }
            // Never place a memory in the future.
            if date.sortDate > now { return nil }
            return date
        }
    }

    func encodedString() -> String? {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(_ string: String) -> MemoryAnalysis? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(MemoryAnalysis.self, from: Data(string.utf8))
    }
}

struct MemoryAnalyzer {
    let client: any LLMClient

    func analyze(
        text: String,
        people: [PersonDescriptor],
        currentDate: MemoryDate?,
        recordedAt: Date,
        birthYear: Int?
    ) async throws -> MemoryAnalysis {
        // Short keys keep the prompt small and avoid the model mangling UUIDs.
        var keyToUUID: [String: String] = [:]
        var lines: [String] = []
        for (index, person) in people.enumerated() {
            let key = "p\(index + 1)"
            keyToUUID[key] = person.uuid.uuidString
            var parts = ["id: \(key)", "name: \(person.name)"]
            if !person.nickname.isEmpty { parts.append("called: \(person.nickname)") }
            if !person.aliases.isEmpty { parts.append("aliases: \(person.aliases.joined(separator: ", "))") }
            if !person.relationship.isEmpty { parts.append("relationship: \(person.relationship)") }
            if !person.notes.isEmpty { parts.append("notes: \(person.notes)") }
            lines.append("- " + parts.joined(separator: " | "))
        }

        let recorded = recordedAt.formatted(date: .complete, time: .omitted)
        var prompt = "Recording date: \(recorded)\n"
        prompt += "Narrator's birth year: \(birthYear.map { String($0) } ?? "unknown")\n"
        if let currentDate {
            prompt += "The narrator already dated this memory: \(currentDate.displayText)\n"
        }
        prompt += "\nKnown people:\n"
        prompt += lines.isEmpty ? "(none yet)\n" : lines.joined(separator: "\n") + "\n"
        prompt += "\n<memory>\n\(text)\n</memory>"

        let request = LLMRequest(
            system: Self.systemPrompt,
            prompt: prompt,
            maxTokens: 4096,
            effort: .low,
            jsonSchema: Self.schema
        )
        var analysis = try await client.completeJSON(request, as: MemoryAnalysis.self)

        // Translate short keys back to real IDs and drop anything invented.
        analysis.people = analysis.people.map { detected in
            var d = detected
            d.candidateIds = d.candidateIds.compactMap { keyToUUID[$0] }
            d.bestMatchId = keyToUUID[d.bestMatchId] ?? ""
            return d
        }
        .filter { !$0.mention.trimmingCharacters(in: .whitespaces).isEmpty }
        analysis.categories = analysis.categories.filter { CategoryCatalog.ids.contains($0) }
        return analysis
    }

    static let systemPrompt = """
    You organize entries in a private memory journal. The narrator ("I") records a story from their life. \
    Extract metadata so the story can be found again later. Never rewrite or correct the story itself.

    title: 3-8 words, specific and evocative, in the narrator's voice (e.g. "Mom's burnt Thanksgiving turkey").
    summary: one plain sentence describing what happened.
    categories: 1-4 of the allowed values that genuinely fit. Use "everyday" only if nothing else fits.
    tone: the emotional tone of the story overall.

    people: every specific person who takes part in the story, other than the narrator. \
    Include relational references ("my mom", "my boss") and named pets that are characters in the story. \
    Exclude the narrator, vague groups ("some guys", "my coworkers"), and public figures only mentioned in passing. \
    If the same person is referred to several ways ("Mom", "my mother"), return a single entry.
    For each person:
    - mention: how they are referred to, as written (e.g. "Alex", "Mom", "my brother").
    - context: a few words from the story that help identify them (e.g. "Alex from the climbing gym").
    - candidate_ids: ids of known people who could plausibly be this person (matching name, nickname, alias, \
    or relationship). Empty if none.
    - best_match_id: the single most likely known person given the story and their notes, or "" if no known \
    person fits or the story gives no way to tell candidates apart.
    - confidence: "high" only when the story clearly identifies which known person it is.
    - suggested_name / suggested_relationship: for someone who may be new, how they would be listed \
    (e.g. "Mom" / "mother", "Alex" / "friend from climbing"). Use the best guess even if matched.

    date_hint: only when the story itself states or clearly implies when it happened \
    ("in 2012", "last Christmas", "when I was 7" with a known birth year, "my freshman year" is NOT enough \
    without a year). Resolve relative phrases against the recording date. Use the most precise level the \
    evidence supports: day, month, season (1 winter, 2 spring, 3 summer, 4 fall), year, or decade (year = first \
    year of the decade). Set circa true for approximations ("around", "when I was about 10"). \
    If there is no such evidence, set found false, precision "year", numbers 0, circa false, evidence "".
    """

    static var schema: String {
        let categoryEnum = CategoryCatalog.ids.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        {
          "type": "object",
          "properties": {
            "title": {"type": "string"},
            "summary": {"type": "string"},
            "categories": {"type": "array", "items": {"type": "string", "enum": [\(categoryEnum)]}},
            "tone": {"type": "string", "enum": ["positive", "neutral", "negative", "mixed"]},
            "people": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "mention": {"type": "string"},
                  "context": {"type": "string"},
                  "candidate_ids": {"type": "array", "items": {"type": "string"}},
                  "best_match_id": {"type": "string"},
                  "confidence": {"type": "string", "enum": ["high", "medium", "low"]},
                  "suggested_name": {"type": "string"},
                  "suggested_relationship": {"type": "string"}
                },
                "required": ["mention", "context", "candidate_ids", "best_match_id", "confidence", "suggested_name", "suggested_relationship"],
                "additionalProperties": false
              }
            },
            "date_hint": {
              "type": "object",
              "properties": {
                "found": {"type": "boolean"},
                "precision": {"type": "string", "enum": ["day", "month", "season", "year", "decade"]},
                "year": {"type": "integer"},
                "month": {"type": "integer"},
                "day": {"type": "integer"},
                "season": {"type": "integer"},
                "circa": {"type": "boolean"},
                "evidence": {"type": "string"}
              },
              "required": ["found", "precision", "year", "month", "day", "season", "circa", "evidence"],
              "additionalProperties": false
            }
          },
          "required": ["title", "summary", "categories", "tone", "people", "date_hint"],
          "additionalProperties": false
        }
        """
    }
}
