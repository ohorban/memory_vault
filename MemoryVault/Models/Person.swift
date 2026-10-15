import Foundation
import SwiftData

@Model
final class Person {
    var id: UUID = UUID()
    /// Full name, e.g. "Alex Kim".
    var name: String = ""
    /// What you call them, e.g. "Mom". Shown instead of the name when set.
    var nickname: String = ""
    /// Other names that refer to this person in your stories ("Mama", "Al").
    var aliases: [String] = []
    /// e.g. "mother", "college roommate", "coworker at Acme".
    var relationship: String = ""
    /// Anything that helps tell people apart (used by the AI to pick the right Alex).
    var notes: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    var birthday: Date?
    var createdAt: Date = Date()

    var memories: [Memory] = []

    init(name: String, nickname: String = "", relationship: String = "") {
        self.name = name
        self.nickname = nickname
        self.relationship = relationship
    }

    var displayName: String {
        let nick = nickname.trimmingCharacters(in: .whitespaces)
        if !nick.isEmpty { return nick }
        let full = name.trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Unnamed" : full
    }

    /// Secondary line used to tell people with the same name apart.
    var subtitle: String {
        var parts: [String] = []
        if !nickname.isEmpty, !name.isEmpty, nickname != name { parts.append(name) }
        if !relationship.isEmpty { parts.append(relationship) }
        if parts.isEmpty, !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: " · ")
    }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var allNames: [String] {
        var names = [name, firstName, nickname] + aliases
        names = names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    var initials: String {
        let source = displayName
        let letters = source.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var sortedMemories: [Memory] {
        memories.sorted { $0.sortDate > $1.sortDate }
    }
}
