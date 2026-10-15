import SwiftData
import SwiftUI

/// Pick one or more people, with search and quick-add.
struct PeoplePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]

    var title = "Tag people"
    var allowsMultiple = true
    let initialSelection: [Person]
    let onDone: ([Person]) -> Void

    @State private var selectedIDs: Set<UUID> = []
    @State private var search = ""
    @State private var showingNew = false
    @State private var newName = ""
    @State private var newRelationship = ""

    private var filtered: [Person] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return people }
        return people.filter { p in
            p.allNames.contains { $0.localizedStandardContains(q) } || p.relationship.localizedStandardContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        newName = search
                        showingNew = true
                    } label: {
                        Label(search.isEmpty ? "New person" : "Add “\(search)”", systemImage: "person.badge.plus")
                    }
                }
                Section {
                    ForEach(filtered) { person in
                        Button {
                            toggle(person)
                        } label: {
                            HStack(spacing: 12) {
                                PersonAvatar(person: person, size: 36)
                                VStack(alignment: .leading) {
                                    Text(person.displayName).foregroundStyle(.primary)
                                    if !person.subtitle.isEmpty {
                                        Text(person.subtitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedIDs.contains(person.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
            }
            .alert("New person", isPresented: $showingNew) {
                TextField("Name (e.g. Mom, Alex Kim)", text: $newName)
                TextField("Relationship (optional)", text: $newRelationship)
                Button("Add") { addPerson() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can add a photo and details later in People.")
            }
            .onAppear {
                selectedIDs = Set(initialSelection.map(\.id))
            }
        }
    }

    private func toggle(_ person: Person) {
        if allowsMultiple {
            if selectedIDs.contains(person.id) {
                selectedIDs.remove(person.id)
            } else {
                selectedIDs.insert(person.id)
            }
        } else {
            selectedIDs = [person.id]
            finish()
        }
    }

    private func addPerson() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let person = Person(name: name, relationship: newRelationship.trimmingCharacters(in: .whitespaces))
        context.insert(person)
        try? context.save()
        newName = ""
        newRelationship = ""
        search = ""
        if allowsMultiple {
            selectedIDs.insert(person.id)
        } else {
            selectedIDs = [person.id]
            finish()
        }
    }

    private func finish() {
        let chosen = people.filter { selectedIDs.contains($0.id) }
        onDone(chosen)
        dismiss()
    }
}
