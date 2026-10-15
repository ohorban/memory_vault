import Foundation

struct MemoryCategory: Identifiable, Hashable {
    let id: String
    let label: String
    let emoji: String
}

/// The memory types the AI can assign. You can also add your own free-form tags.
enum CategoryCatalog {
    static let all: [MemoryCategory] = [
        .init(id: "funny", label: "Funny", emoji: "😂"),
        .init(id: "heartwarming", label: "Heartwarming", emoji: "🥹"),
        .init(id: "sad", label: "Sad", emoji: "😢"),
        .init(id: "embarrassing", label: "Embarrassing", emoji: "🙈"),
        .init(id: "adventure", label: "Adventure", emoji: "🧭"),
        .init(id: "travel", label: "Travel", emoji: "✈️"),
        .init(id: "milestone", label: "Milestone", emoji: "🏁"),
        .init(id: "achievement", label: "Achievement", emoji: "🏆"),
        .init(id: "lesson", label: "Life lesson", emoji: "💡"),
        .init(id: "romantic", label: "Romantic", emoji: "❤️"),
        .init(id: "scary", label: "Scary", emoji: "😱"),
        .init(id: "conflict", label: "Conflict", emoji: "⚡️"),
        .init(id: "celebration", label: "Celebration", emoji: "🎉"),
        .init(id: "family", label: "Family", emoji: "👨‍👩‍👧"),
        .init(id: "friendship", label: "Friendship", emoji: "🤝"),
        .init(id: "work", label: "Work", emoji: "💼"),
        .init(id: "school", label: "School", emoji: "🎓"),
        .init(id: "childhood", label: "Childhood", emoji: "🧸"),
        .init(id: "food", label: "Food", emoji: "🍜"),
        .init(id: "nostalgic", label: "Nostalgic", emoji: "📼"),
        .init(id: "weird", label: "Weird", emoji: "🛸"),
        .init(id: "everyday", label: "Everyday", emoji: "☕️"),
    ]

    static let ids: [String] = all.map(\.id)

    static func info(for id: String) -> MemoryCategory {
        all.first { $0.id == id } ?? MemoryCategory(id: id, label: id.capitalized, emoji: "🏷️")
    }

    /// Sorts tags in catalog order, with custom tags last.
    static func ordered(_ tags: some Sequence<String>) -> [String] {
        Array(Set(tags)).sorted { a, b in
            let ia = ids.firstIndex(of: a) ?? Int.max
            let ib = ids.firstIndex(of: b) ?? Int.max
            return ia == ib ? a < b : ia < ib
        }
    }
}
