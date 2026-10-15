import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// JSON backup of everything except voice recordings.
struct BackupFile: Codable {
    var version = 1
    var exportedAt = Date()
    var people: [PersonRecord]
    var memories: [MemoryRecord]

    struct PersonRecord: Codable {
        var id: UUID
        var name: String
        var nickname: String
        var aliases: [String]
        var relationship: String
        var notes: String
        var photo: Data?
        var birthday: Date?
        var createdAt: Date
    }

    struct MemoryRecord: Codable {
        var id: UUID
        var text: String
        var transcript: String?
        var title: String
        var summary: String
        var createdAt: Date
        var updatedAt: Date
        var date: MemoryDate
        var categories: [String]
        var tone: String
        var isFavorite: Bool
        var personIDs: [UUID]
    }
}

enum BackupService {
    @MainActor
    static func export(context: ModelContext) throws -> Data {
        let people = try context.fetch(FetchDescriptor<Person>())
        let memories = try context.fetch(FetchDescriptor<Memory>(sortBy: [SortDescriptor(\.sortDate)]))
        let file = BackupFile(
            people: people.map {
                BackupFile.PersonRecord(id: $0.id, name: $0.name, nickname: $0.nickname, aliases: $0.aliases,
                      relationship: $0.relationship, notes: $0.notes, photo: $0.photoData,
                      birthday: $0.birthday, createdAt: $0.createdAt)
            },
            memories: memories.map {
                BackupFile.MemoryRecord(id: $0.id, text: $0.text, transcript: $0.transcript, title: $0.title, summary: $0.summary,
                      createdAt: $0.createdAt, updatedAt: $0.updatedAt, date: $0.memoryDate,
                      categories: $0.categories, tone: $0.toneRaw, isFavorite: $0.isFavorite,
                      personIDs: $0.people.map(\.id))
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Adds anything from the backup that isn't already in the vault. Returns (people, memories) added.
    @MainActor
    static func importBackup(_ data: Data, context: ModelContext) throws -> (Int, Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(BackupFile.self, from: data)

        var peopleByID: [UUID: Person] = [:]
        for person in try context.fetch(FetchDescriptor<Person>()) { peopleByID[person.id] = person }
        let existingMemories = try context.fetch(FetchDescriptor<Memory>())
        let existingMemoryIDs = Set(existingMemories.map(\.id))

        var addedPeople = 0
        for record in file.people where peopleByID[record.id] == nil {
            let person = Person(name: record.name, nickname: record.nickname, relationship: record.relationship)
            person.id = record.id
            person.aliases = record.aliases
            person.notes = record.notes
            person.photoData = record.photo
            person.birthday = record.birthday
            person.createdAt = record.createdAt
            context.insert(person)
            peopleByID[record.id] = person
            addedPeople += 1
        }

        var addedMemories = 0
        for record in file.memories where !existingMemoryIDs.contains(record.id) {
            let memory = Memory(text: record.text, date: record.date)
            memory.id = record.id
            memory.transcript = record.transcript
            memory.title = record.title
            memory.summary = record.summary
            memory.createdAt = record.createdAt
            memory.updatedAt = record.updatedAt
            memory.categories = record.categories
            memory.toneRaw = record.tone
            memory.isFavorite = record.isFavorite
            memory.analysisState = .done
            context.insert(memory)
            memory.people = record.personIDs.compactMap { peopleByID[$0] }
            addedMemories += 1
        }
        try context.save()
        return (addedPeople, addedMemories)
    }
}

struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
