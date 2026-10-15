import SwiftUI

/// Drafts a speech or toast for someone, using only your real stories with them.
struct SpeechHelperView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.userName) private var userName = ""
    let person: Person

    @State private var occasion: SpeechOccasion = .birthday
    @State private var style: SpeechStyle = .balanced
    @State private var length: SpeechLength = .medium
    @State private var notes = ""
    @State private var outlineOnly = false
    @State private var excluded: Set<UUID> = []
    @State private var result = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var memories: [Memory] { person.sortedMemories }
    private var included: [Memory] { memories.filter { !excluded.contains($0.id) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Occasion", selection: $occasion) {
                        ForEach(SpeechOccasion.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Style", selection: $style) {
                        ForEach(SpeechStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Length", selection: $length) {
                        ForEach(SpeechLength.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Just suggest the best stories", isOn: $outlineOnly)
                    TextField("Anything else? (inside jokes, what to emphasize)", text: $notes, axis: .vertical)
                        .lineLimit(2...)
                } header: {
                    Text("For \(person.displayName)")
                }

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView().padding(.trailing, 6) }
                            Text(isWorking ? "Writing…" : (outlineOnly ? "Find the best stories" : "Write it"))
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isWorking || included.isEmpty)
                } footer: {
                    Text("Uses only the \(included.count) memories below. Nothing is made up.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                if !result.isEmpty {
                    Section {
                        Text(result)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                        HStack {
                            Button {
                                UIPasteboard.general.string = result
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            Spacer()
                            ShareLink(item: result) { Label("Share", systemImage: "square.and.arrow.up") }
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text(outlineOnly ? "Story ideas" : "Draft")
                    }
                }

                Section("Stories to draw from") {
                    ForEach(memories) { memory in
                        Toggle(isOn: Binding(
                            get: { !excluded.contains(memory.id) },
                            set: { isOn in
                                if isOn { excluded.remove(memory.id) } else { excluded.insert(memory.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memory.displayTitle).font(.subheadline.weight(.medium))
                                Text(memory.memoryDate.displayText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Speech helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func generate() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let description = person.subtitle.isEmpty ? person.displayName : "\(person.displayName) (\(person.subtitle))"
        let snapshots = included.map(MemorySnapshot.init)
        do {
            result = try await RecallService.writeSpeech(
                about: description,
                memories: snapshots,
                occasion: occasion,
                style: style,
                length: length,
                speakerName: userName,
                notes: notes,
                outlineOnly: outlineOnly
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
