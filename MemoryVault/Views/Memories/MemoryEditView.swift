import SwiftData
import SwiftUI

struct MemoryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let memory: Memory

    @State private var title: String
    @State private var text: String
    @State private var date: MemoryDate
    @State private var people: [Person]
    @State private var categories: Set<String>
    @State private var tone: Tone
    @State private var isFavorite: Bool
    @State private var dateChanged = false
    @State private var showDate = false
    @State private var showPeople = false

    init(memory: Memory) {
        self.memory = memory
        _title = State(initialValue: memory.title)
        _text = State(initialValue: memory.text)
        _date = State(initialValue: memory.memoryDate)
        _people = State(initialValue: memory.sortedPeople)
        _categories = State(initialValue: Set(memory.categories))
        _tone = State(initialValue: memory.tone)
        _isFavorite = State(initialValue: memory.isFavorite)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Story") {
                    TextField("What happened?", text: $text, axis: .vertical)
                        .lineLimit(6...)
                }
                Section {
                    Button { showDate = true } label: {
                        LabeledContent("When", value: date.displayText)
                    }
                    Button { showPeople = true } label: {
                        LabeledContent("People") {
                            if people.isEmpty {
                                Text("None")
                            } else {
                                AvatarStack(people: people)
                            }
                        }
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                }
                .foregroundStyle(.primary)
                Section("Tone") {
                    Picker("Tone", selection: $tone) {
                        ForEach(Tone.allCases) { Text($0.emoji).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Type") {
                    CategoryToggleGrid(selection: $categories)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle("Edit memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showDate) {
                MemoryDateSheet(initial: date) {
                    date = $0
                    dateChanged = true
                }
            }
            .sheet(isPresented: $showPeople) {
                PeoplePickerSheet(initialSelection: people) { people = $0 }
            }
        }
    }

    private func save() {
        memory.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        memory.memoryDate = date
        if dateChanged { memory.dateIsPlaceholder = false }
        memory.people = people
        memory.categories = CategoryCatalog.ordered(categories)
        memory.tone = tone
        memory.isFavorite = isFavorite
        memory.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}
