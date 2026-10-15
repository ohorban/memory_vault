import SwiftData
import SwiftUI

/// Shown after saving when the AI needs you to confirm who someone is
/// (e.g. which of your two Alexes), or whether to add a new person.
struct ReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var allPeople: [Person]

    let memory: Memory
    let onFinish: (String) -> Void

    @State private var draft: ReviewDraft
    @State private var pickingForMention: UUID?

    init(memory: Memory, draft: ReviewDraft, onFinish: @escaping (String) -> Void = { _ in }) {
        self.memory = memory
        self.onFinish = onFinish
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(memory.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }

                if !draft.mentions.isEmpty {
                    ForEach($draft.mentions) { $mention in
                        MentionSection(
                            mention: $mention,
                            people: allPeople,
                            onPickOther: { pickingForMention = mention.id }
                        )
                    }
                }

                Section("Details") {
                    TextField("Title", text: $draft.title)
                    Picker("Tone", selection: $draft.tone) {
                        ForEach(Tone.allCases) { Text("\($0.emoji) \($0.label)").tag($0) }
                    }
                    CategoryToggleGrid(selection: $draft.categories)
                        .padding(.vertical, 4)
                }

                if let suggested = draft.suggestedDate {
                    Section {
                        Toggle(isOn: $draft.applyDate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Date it \(suggested.displayText)")
                                if !draft.dateEvidence.isEmpty {
                                    Text("“\(draft.dateEvidence)”").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("When")
                    } footer: {
                        Text("Currently: \(memory.memoryDate.displayText)")
                    }
                }
            }
            .navigationTitle("Who's in this story?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        memory.analysisState = .needsReview
                        try? context.save()
                        onFinish("Saved ✓ Confirm people any time from Memories")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let summary = MemoryProcessor.apply(draft, to: memory, context: context)
                        onFinish(summary)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: Binding(get: { pickingForMention != nil }, set: { if !$0 { pickingForMention = nil } })) {
                PeoplePickerSheet(title: "Who is this?", allowsMultiple: false, initialSelection: []) { chosen in
                    guard let person = chosen.first,
                          let index = draft.mentions.firstIndex(where: { $0.id == pickingForMention }) else { return }
                    if !draft.mentions[index].candidateIDs.contains(person.id) {
                        draft.mentions[index].candidateIDs.append(person.id)
                    }
                    draft.mentions[index].choice = .existing(person.id)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct MentionSection: View {
    @Binding var mention: MentionResolution
    let people: [Person]
    let onPickOther: () -> Void

    private var candidates: [Person] {
        mention.candidateIDs.compactMap { id in people.first { $0.id == id } }
    }

    private var header: String {
        let name = mention.detected.mention
        if candidates.count > 1 { return "Which \(name)?" }
        if candidates.isEmpty { return "“\(name)” — new person?" }
        return "“\(name)”"
    }

    var body: some View {
        Section {
            ForEach(candidates) { person in
                choiceRow(.existing(person.id)) {
                    HStack(spacing: 12) {
                        PersonAvatar(person: person, size: 36)
                        VStack(alignment: .leading) {
                            Text(person.displayName)
                            if !person.subtitle.isEmpty {
                                Text(person.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            choiceRow(.createNew) {
                Label("Add as a new person", systemImage: "person.badge.plus")
            }
            if mention.choice == .createNew {
                TextField("Name", text: $mention.newName)
                TextField("Relationship (e.g. coworker, cousin)", text: $mention.newRelationship)
            }

            Button(action: onPickOther) {
                Label("Someone else…", systemImage: "magnifyingglass")
            }
            choiceRow(.ignore) {
                Label("Don't tag", systemImage: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(header)
        } footer: {
            if !mention.detected.context.isEmpty {
                Text("From the story: “\(mention.detected.context)”")
            }
        }
    }

    private func choiceRow<Content: View>(_ choice: MentionResolution.Choice, @ViewBuilder label: () -> Content) -> some View {
        Button {
            mention.choice = choice
        } label: {
            HStack {
                label()
                Spacer()
                if mention.choice == choice {
                    Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Toggleable chips for memory types.
struct CategoryToggleGrid: View {
    @Binding var selection: Set<String>
    @State private var customTag = ""

    private var allTags: [String] {
        CategoryCatalog.ids + CategoryCatalog.ordered(selection).filter { !CategoryCatalog.ids.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                ForEach(allTags, id: \.self) { id in
                    let info = CategoryCatalog.info(for: id)
                    Button {
                        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                    } label: {
                        Chip(text: "\(info.emoji) \(info.label)", isSelected: selection.contains(id))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Add your own tag", text: $customTag)
                    .onSubmit(addCustom)
                Button("Add", action: addCustom)
                    .buttonStyle(.borderless)
                    .disabled(customTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.subheadline)
        }
    }

    private func addCustom() {
        let tag = customTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !tag.isEmpty else { return }
        selection.insert(tag)
        customTag = ""
    }
}
