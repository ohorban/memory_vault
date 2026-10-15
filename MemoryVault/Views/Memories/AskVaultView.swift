import SwiftData
import SwiftUI

/// Ask questions about your life, answered from your memories.
struct AskVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Memory.sortDate) private var memories: [Memory]

    @State private var question = ""
    @State private var answer = ""
    @State private var isAsking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private let suggestions = [
        "What are my funniest stories?",
        "What have I done with Mom over the years?",
        "Which memories are from my childhood?",
        "What happened last summer?",
        "Give me a story I haven't thought about in a while.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .bottom) {
                        TextField("Ask about your memories…", text: $question, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focused)
                            .submitLabel(.send)
                            .onSubmit { Task { await ask() } }
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        Button {
                            Task { await ask() }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                        }
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
                    }

                    if answer.isEmpty && !isAsking {
                        Text("Try asking").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        FlowLayout(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    question = suggestion
                                    Task { await ask() }
                                } label: {
                                    Chip(text: suggestion)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if isAsking {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Looking through \(memories.count) memories…").foregroundStyle(.secondary)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                    }

                    if !answer.isEmpty {
                        Text(answer)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
            .navigationTitle("Ask your memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isAsking else { return }
        focused = false
        isAsking = true
        errorMessage = nil
        answer = ""
        defer { isAsking = false }
        let snapshots = memories.map(MemorySnapshot.init)
        do {
            answer = try await RecallService.ask(q, memories: snapshots)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
