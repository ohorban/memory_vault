import SwiftData
import SwiftUI

/// The home screen: log a memory as fast as possible, by typing or talking.
struct LogMemoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Memory.sortDate, order: .reverse) private var memories: [Memory]
    @Query(sort: \Person.name) private var people: [Person]

    /// The draft survives the app being closed.
    @AppStorage(SettingsKey.draftText) private var text = ""
    @State private var memoryDate = MemoryDate.today
    @State private var dateWasChosen = false
    @State private var taggedPeople: [Person] = []
    @State private var isFavorite = false

    @State private var recorder = AudioRecorder()
    @State private var audioClips: [URL] = []
    @State private var transcripts: [String] = []
    @State private var isTranscribing = false
    @State private var failedClip: URL?

    @State private var showDateSheet = false
    @State private var showPeoplePicker = false
    @State private var review: ReviewTarget?
    @State private var toast: Toast?
    @State private var toastTask: Task<Void, Never>?
    @State private var alertMessage: String?
    @State private var shuffledPick: Memory?
    @State private var savedCount = 0
    @FocusState private var editorFocused: Bool

    struct ReviewTarget: Identifiable {
        let id = UUID()
        let memory: Memory
        let draft: ReviewDraft
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var dailyPick: Memory? { shuffledPick ?? DailyPick.memoryOfTheDay(from: memories) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !editorFocused, let pick = dailyPick {
                        DailyMemoryCard(memory: pick, isShuffled: shuffledPick != nil) {
                            withAnimation { shuffledPick = memories.filter { $0.id != pick.id }.randomElement() ?? pick }
                        }
                    }
                    editor
                    detailsRow
                    if isTranscribing {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Transcribing…").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    if failedClip != nil {
                        Button {
                            if let clip = failedClip { Task { await transcribe(clip, isRetry: true) } }
                        } label: {
                            Label("Transcription failed — tap to retry", systemImage: "arrow.clockwise")
                        }
                        .font(.subheadline)
                        .tint(.orange)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .overlay(alignment: .top) {
                if let toast { ToastView(toast: toast).padding(.top, 4) }
            }
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }
                }
            }
            .sheet(isPresented: $showDateSheet) {
                MemoryDateSheet(initial: memoryDate) { newDate in
                    memoryDate = newDate
                    dateWasChosen = true
                }
            }
            .sheet(isPresented: $showPeoplePicker) {
                PeoplePickerSheet(initialSelection: taggedPeople) { taggedPeople = $0 }
            }
            .sheet(item: $review) { target in
                ReviewSheet(memory: target.memory, draft: target.draft) { summary in
                    showToast(Toast(message: summary))
                }
            }
            .alert("Heads up", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: savedCount)
            .onChange(of: memories.count) { shuffledPick = nil }
            .onChange(of: scenePhase) {
                // A new day: "Today" should mean today.
                if scenePhase == .active, !dateWasChosen { memoryDate = .today }
            }
            .vaultDestinations()
        }
    }

    // MARK: - Pieces

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What happened? Type or tap the mic and just talk…", text: $text, axis: .vertical)
                .lineLimit(8...)
                .focused($editorFocused)
                .font(.body)
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            if !trimmedText.isEmpty {
                HStack {
                    Text("\(trimmedText.split { $0.isWhitespace }.count) words")
                    Spacer()
                    Button("Clear", role: .destructive) { clearDraft() }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsRow: some View {
        FlowLayout(spacing: 8) {
            Button { showDateSheet = true } label: {
                Chip(text: memoryDate.isToday ? "Today" : memoryDate.displayText, systemImage: "calendar",
                     isSelected: dateWasChosen)
            }
            ForEach(taggedPeople) { person in
                Button { taggedPeople.removeAll { $0.id == person.id } } label: {
                    HStack(spacing: 6) {
                        PersonAvatar(person: person, size: 20)
                        Text(person.displayName)
                        Image(systemName: "xmark").imageScale(.small).foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            Button { showPeoplePicker = true } label: {
                Chip(text: taggedPeople.isEmpty ? "Who was there?" : "Add", systemImage: "person.badge.plus")
            }
            Button { isFavorite.toggle() } label: {
                Chip(text: "Favorite", systemImage: isFavorite ? "star.fill" : "star", isSelected: isFavorite, tint: .yellow)
            }
            if !audioClips.isEmpty {
                Chip(text: "\(audioClips.count) recording\(audioClips.count == 1 ? "" : "s")", systemImage: "waveform")
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            RecordButton(isRecording: recorder.isRecording, level: recorder.level, elapsed: recorder.elapsed,
                         isBusy: isTranscribing) {
                Task { await toggleRecording() }
            }
            Button(action: save) {
                Text("Save memory")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(trimmedText.isEmpty || recorder.isRecording || isTranscribing)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Recording

    private func toggleRecording() async {
        if recorder.isRecording {
            UIApplication.shared.isIdleTimerDisabled = false
            guard let url = recorder.stop() else { return }
            await transcribe(url, isRetry: false)
            return
        }
        guard AppSettings.hasOpenAIKey else {
            alertMessage = "Add your OpenAI API key in Settings to record memories by voice."
            return
        }
        guard await recorder.requestPermission() else {
            alertMessage = "Microphone access is off. Turn it on in the iPhone Settings app → Memory Vault."
            return
        }
        editorFocused = false
        do {
            try recorder.start()
            // Don't let the screen auto-lock in the middle of a long story.
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func transcribe(_ url: URL, isRetry: Bool) async {
        if !isRetry { audioClips.append(url) }
        failedClip = nil
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            let service = try TranscriptionService.makeDefault()
            let vocabulary = people.flatMap(\.allNames)
            let result = try await service.transcribe(fileURL: url, vocabulary: vocabulary)
            transcripts.append(result)
            if trimmedText.isEmpty {
                text = result
            } else {
                text = trimmedText + "\n\n" + result
            }
        } catch {
            failedClip = url
            alertMessage = "\(error.localizedDescription)\n\nYour recording is kept — tap retry below."
        }
    }

    // MARK: - Saving

    private func save() {
        guard !trimmedText.isEmpty else { return }
        let memory = Memory(text: trimmedText, date: dateWasChosen ? memoryDate : .today)
        memory.dateIsPlaceholder = !dateWasChosen
        memory.isFavorite = isFavorite
        if !transcripts.isEmpty { memory.transcript = transcripts.joined(separator: "\n\n") }
        if AppSettings.keepAudio {
            memory.audioFileNames = audioClips.compactMap(AudioStorage.persist)
        } else {
            audioClips.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        context.insert(memory)
        memory.people = taggedPeople
        try? context.save()

        savedCount += 1
        resetForm()
        Task { await analyze(memory) }
    }

    private func analyze(_ memory: Memory) async {
        guard AppSettings.hasAnthropicKey else {
            memory.analysisState = .skipped
            showToast(Toast(message: "Saved ✓  (add a Claude key in Settings for auto-tagging)"))
            return
        }
        showToast(Toast(message: "Saved ✓ Tagging…", isProgress: true), autoHide: false)
        do {
            let draft = try await MemoryProcessor.analyze(memory, context: context)
            if draft.needsReview {
                memory.analysisState = .needsReview
                try? context.save()
                hideToast()
                review = ReviewTarget(memory: memory, draft: draft)
            } else {
                let summary = MemoryProcessor.apply(draft, to: memory, context: context)
                showToast(Toast(message: summary))
            }
        } catch {
            memory.analysisState = .failed
            memory.analysisError = error.localizedDescription
            try? context.save()
            showToast(Toast(message: "Saved ✓ Tagging failed — retry from the memory"))
        }
    }

    private func resetForm() {
        text = ""
        memoryDate = .today
        dateWasChosen = false
        taggedPeople = []
        isFavorite = false
        audioClips = []
        transcripts = []
        failedClip = nil
        editorFocused = false
    }

    private func clearDraft() {
        audioClips.forEach { try? FileManager.default.removeItem(at: $0) }
        resetForm()
    }

    private func showToast(_ newToast: Toast, autoHide: Bool = true) {
        toastTask?.cancel()
        withAnimation { toast = newToast }
        guard autoHide else { return }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    private func hideToast() {
        toastTask?.cancel()
        withAnimation { toast = nil }
    }
}

/// Big round mic button with a level-reactive pulse while recording.
struct RecordButton: View {
    let isRecording: Bool
    let level: Double
    let elapsed: TimeInterval
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .scaleEffect(1 + level * 0.45)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
                Circle()
                    .fill(isRecording ? Color.red : Color.accentColor)
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)
            .overlay(alignment: .bottom) {
                if isRecording {
                    Text(elapsed.clockText)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                        .offset(y: 12)
                }
            }
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.5 : 1)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record a memory")
    }
}

/// Front-page card that resurfaces one memory a day (or an anniversary).
struct DailyMemoryCard: View {
    let memory: Memory
    let isShuffled: Bool
    let onShuffle: () -> Void

    private var header: String {
        if !isShuffled, DailyPick.onThisDay(memory, on: Date()) {
            let years = Calendar.current.component(.year, from: Date()) - (memory.year ?? 0)
            return "On this day · \(years) year\(years == 1 ? "" : "s") ago"
        }
        return isShuffled ? "From your vault" : "Today's memory"
    }

    var body: some View {
        NavigationLink(value: memory) {
            VStack(alignment: .leading, spacing: 6) {
                Label(header, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.trailing, 40)
                Text(memory.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(memory.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(memory.memoryDate.displayText)
                    if !memory.people.isEmpty {
                        Text("·")
                        AvatarStack(people: memory.sortedPeople, size: 18)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onShuffle) {
                Image(systemName: "shuffle")
                    .font(.subheadline.weight(.semibold))
                    .padding(12)
            }
            .accessibilityLabel("Shuffle")
        }
    }
}
