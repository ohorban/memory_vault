import SwiftData
import SwiftUI

struct MemoryDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var memory: Memory

    @State private var player = ClipPlayer()
    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var review: ReviewTarget?
    @State private var isTagging = false
    @State private var errorMessage: String?
    @State private var showTranscript = false

    private struct ReviewTarget: Identifiable {
        let id = UUID()
        let draft: ReviewDraft
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(memory.memoryDate.displayText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(memory.displayTitle)
                        .font(.title2.bold())
                    if !memory.summary.isEmpty {
                        Text(memory.summary).font(.callout).foregroundStyle(.secondary)
                    }
                }

                statusBanner

                if !memory.people.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(memory.sortedPeople) { person in
                            NavigationLink(value: person) {
                                HStack(spacing: 6) {
                                    PersonAvatar(person: person, size: 24)
                                    Text(person.displayName).font(.subheadline.weight(.medium))
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 10)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !memory.categories.isEmpty || memory.analysisState == .done {
                    FlowLayout(spacing: 6) {
                        NavigationLink(value: MemoryFilterRoute(kind: .tone(memory.tone))) {
                            Chip(text: "\(memory.tone.emoji) \(memory.tone.label)")
                        }
                        ForEach(memory.categories, id: \.self) { id in
                            let info = CategoryCatalog.info(for: id)
                            NavigationLink(value: MemoryFilterRoute(kind: .category(id))) {
                                Chip(text: "\(info.emoji) \(info.label)")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text(memory.text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !memory.audioFileNames.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recordings").font(.headline)
                        ForEach(Array(memory.audioURLs.enumerated()), id: \.offset) { index, url in
                            AudioClipRow(url: url, index: index, player: player)
                        }
                    }
                }

                if let transcript = memory.transcript, transcript != memory.text {
                    DisclosureGroup("Original transcript", isExpanded: $showTranscript) {
                        Text(transcript)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                    }
                }

                Text("Logged \(memory.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    memory.isFavorite.toggle()
                } label: {
                    Image(systemName: memory.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(memory.isFavorite ? Color.yellow : Color.accentColor)
                }
                .accessibilityLabel(memory.isFavorite ? "Unfavorite" : "Favorite")
                Menu {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button { Task { await retag() } } label: {
                        Label("Re-tag with AI", systemImage: "sparkles")
                    }
                    ShareLink(item: shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) { MemoryEditView(memory: memory) }
        .sheet(item: $review) { target in
            ReviewSheet(memory: memory, draft: target.draft)
        }
        .confirmationDialog("Delete this memory?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Couldn't tag", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear { player.stop() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch memory.analysisState {
        case .needsReview:
            banner("Confirm who's in this story", systemImage: "person.fill.questionmark", tint: .orange) {
                if let draft = MemoryProcessor.storedDraft(for: memory, context: context) {
                    review = ReviewTarget(draft: draft)
                } else {
                    Task { await retag() }
                }
            }
        case .failed:
            banner("Tagging failed — tap to retry", systemImage: "exclamationmark.arrow.circlepath", tint: .red) {
                Task { await retag() }
            }
        case .pending, .skipped:
            if AppSettings.hasAnthropicKey {
                banner("Tag people & type with AI", systemImage: "sparkles", tint: .accentColor) {
                    Task { await retag() }
                }
            }
        case .done:
            EmptyView()
        }
    }

    private func banner(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isTagging {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(isTagging ? "Tagging…" : title).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .padding(12)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isTagging)
    }

    private var shareText: String {
        "\(memory.displayTitle)\n\(memory.memoryDate.displayText)\n\n\(memory.text)"
    }

    private func retag() async {
        isTagging = true
        defer { isTagging = false }
        do {
            let draft = try await MemoryProcessor.analyze(memory, context: context)
            review = ReviewTarget(draft: draft)
        } catch {
            memory.analysisState = .failed
            memory.analysisError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        player.stop()
        let target = memory
        let ctx = self.context
        dismiss()
        // Delete after the screen is gone so nothing renders a deleted object.
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            target.audioFileNames.forEach(AudioStorage.delete)
            ctx.delete(target)
            try? ctx.save()
        }
    }
}

private struct AudioClipRow: View {
    let url: URL
    let index: Int
    let player: ClipPlayer
    @State private var duration: TimeInterval = 0

    private var isPlaying: Bool { player.playingURL == url }

    var body: some View {
        Button {
            player.toggle(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording \(index + 1)").font(.subheadline.weight(.medium))
                    ProgressView(value: isPlaying ? player.progress : 0)
                }
                Text(duration.clockText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task { duration = ClipPlayer.duration(of: url) }
    }
}
