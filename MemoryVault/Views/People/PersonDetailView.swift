import SwiftData
import SwiftUI

struct PersonDetailView: View {
    let person: Person
    @State private var showEdit = false
    @State private var showSpeech = false
    @State private var randomStory: Memory?

    private var memories: [Memory] { person.sortedMemories }

    private var span: String? {
        let years = memories.compactMap(\.year)
        guard let first = years.min(), let last = years.max() else { return nil }
        return first == last ? String(first) : "\(String(first))–\(String(last))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    PersonAvatar(person: person, size: 96)
                    Text(person.displayName).font(.title2.bold())
                    if !person.subtitle.isEmpty {
                        Text(person.subtitle).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text("\(memories.count) \(memories.count == 1 ? "memory" : "memories")")
                        if let span { Text("· \(span)") }
                        if let birthday = person.birthday {
                            Text("· 🎂 \(birthday.formatted(.dateTime.month(.abbreviated).day()))")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if !person.notes.isEmpty {
                        Text(person.notes)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            if !memories.isEmpty {
                Section {
                    Button { showSpeech = true } label: {
                        Label("Help me write a speech or toast", systemImage: "text.quote")
                    }
                    Button { randomStory = memories.randomElement() } label: {
                        Label("Remind me of a story", systemImage: "shuffle")
                    }
                }
            }

            Section(memories.isEmpty ? "No memories with \(person.displayName) yet" : "Memories together") {
                ForEach(memories) { memory in
                    NavigationLink(value: memory) { MemoryRow(memory: memory) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { showEdit = true }
        }
        .sheet(isPresented: $showEdit) { PersonEditView(person: person) }
        .sheet(isPresented: $showSpeech) { SpeechHelperView(person: person) }
        .navigationDestination(item: $randomStory) { MemoryDetailView(memory: $0) }
    }
}
