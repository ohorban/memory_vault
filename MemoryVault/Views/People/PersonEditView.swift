import PhotosUI
import SwiftData
import SwiftUI

struct PersonEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let person: Person?

    @State private var name = ""
    @State private var nickname = ""
    @State private var relationship = ""
    @State private var aliases = ""
    @State private var notes = ""
    @State private var photoData: Data?
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var photoItem: PhotosPickerItem?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        avatarPreview
                        HStack(spacing: 12) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Photo", systemImage: "photo")
                            }
                            Button {
                                ContactImporter.shared.present { result in
                                    guard let result else { return }
                                    if name.isEmpty { name = result.name }
                                    if nickname.isEmpty { nickname = result.nickname }
                                    if let photo = result.photo { photoData = photo }
                                    if let date = result.birthday {
                                        birthday = date
                                        hasBirthday = true
                                    }
                                }
                            } label: {
                                Label("Contacts", systemImage: "person.crop.circle")
                            }
                            if photoData != nil {
                                Button(role: .destructive) { photoData = nil } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name (e.g. Alex Kim)", text: $name)
                        .textContentType(.name)
                    TextField("What you call them (e.g. Mom)", text: $nickname)
                    TextField("Relationship (e.g. college roommate)", text: $relationship)
                } footer: {
                    Text("If you know two people with the same name, the relationship is how you'll tell them apart.")
                }

                Section {
                    TextField("Other names, comma separated", text: $aliases)
                    TextField("Notes (e.g. Alex from the climbing gym)", text: $notes, axis: .vertical)
                        .lineLimit(2...)
                } header: {
                    Text("Helps the AI recognize them")
                }

                Section {
                    Toggle("Birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Date", selection: $birthday, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(person == nil ? "New person" : "Edit person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                            && nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoData = ImageUtil.avatarData(from: data)
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 96, height: 96)
                .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(.secondary))
        }
    }

    private func load() {
        guard !loaded, let person else { return }
        loaded = true
        name = person.name
        nickname = person.nickname
        relationship = person.relationship
        aliases = person.aliases.joined(separator: ", ")
        notes = person.notes
        photoData = person.photoData
        if let date = person.birthday {
            birthday = date
            hasBirthday = true
        }
    }

    private func save() {
        let target = person ?? Person(name: "")
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if target.name.isEmpty { target.name = target.nickname }
        target.relationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        target.aliases = aliases.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.photoData = photoData
        target.birthday = hasBirthday ? birthday : nil
        if person == nil { context.insert(target) }
        try? context.save()
        dismiss()
    }
}
