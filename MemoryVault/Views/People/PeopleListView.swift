import SwiftData
import SwiftUI

struct PeopleListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @State private var search = ""
    @State private var showNew = false
    @State private var pendingDelete: Person?

    private var filtered: [Person] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? people : people.filter { p in
            p.allNames.contains { $0.localizedStandardContains(q) } || p.relationship.localizedStandardContains(q)
        }
        return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { person in
                    NavigationLink(value: person) {
                        HStack(spacing: 12) {
                            PersonAvatar(person: person, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.displayName).font(.body.weight(.medium))
                                if !person.subtitle.isEmpty {
                                    Text(person.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text("\(person.memories.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { pendingDelete = person } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("They're added as you log memories, or tap + to add someone with a photo.")
                    )
                }
            }
            .searchable(text: $search, prompt: "Search people")
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add person")
                }
            }
            .sheet(isPresented: $showNew) { PersonEditView(person: nil) }
            .confirmationDialog(
                "Delete \(pendingDelete?.displayName ?? "")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete person", role: .destructive) {
                    if let person = pendingDelete {
                        context.delete(person)
                        try? context.save()
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("Their memories stay in your vault; they're just untagged.")
            }
            .vaultDestinations()
        }
    }
}
