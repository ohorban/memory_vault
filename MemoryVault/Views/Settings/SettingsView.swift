import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var memories: [Memory]
    @Query private var people: [Person]

    @AppStorage(SettingsKey.claudeModel) private var claudeModel = ""
    @AppStorage(SettingsKey.transcriptionModel) private var transcriptionModel = AppSettings.defaultTranscriptionModel
    @AppStorage(SettingsKey.userName) private var userName = ""
    @AppStorage(SettingsKey.birthYear) private var birthYear = 0
    @AppStorage(SettingsKey.keepAudio) private var keepAudio = true
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled = false
    @AppStorage(SettingsKey.reminderHour) private var reminderHour = 19
    @AppStorage(SettingsKey.reminderMinute) private var reminderMinute = 0
    @AppStorage(SettingsKey.reminderFrequency) private var reminderFrequency = ReminderFrequency.daily.rawValue

    @State private var anthropicKey = ""
    @State private var openAIKey = ""
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var isTesting = false

    private let currentYear = Calendar.current.component(.year, from: Date())

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderHour = c.hour ?? 19
                reminderMinute = c.minute ?? 0
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Anthropic API key (sk-ant-…)", text: $anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: anthropicKey) { Keychain.save(anthropicKey, for: .anthropic) }
                    SecureField("OpenAI API key (sk-…)", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: openAIKey) { Keychain.save(openAIKey, for: .openAI) }
                    Button {
                        Task { await testClaude() }
                    } label: {
                        HStack {
                            Text("Test Claude connection")
                            if isTesting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(anthropicKey.isEmpty || isTesting)
                } header: {
                    Text("API keys")
                } footer: {
                    Text("Stored in the iPhone Keychain. Claude tags people, types and dates and powers the speech helper. OpenAI turns your voice into text.")
                }

                Section {
                    TextField(AppSettings.defaultClaudeModel, text: $claudeModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Picker("Transcription", selection: $transcriptionModel) {
                        ForEach(AppSettings.transcriptionModels, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Keep voice recordings", isOn: $keepAudio)
                } header: {
                    Text("Models")
                } footer: {
                    Text("Leave the Claude model blank to use \(AppSettings.defaultClaudeModel).")
                }

                Section {
                    TextField("Your first name (for speeches)", text: $userName)
                    Picker("Birth year", selection: $birthYear) {
                        Text("Not set").tag(0)
                        ForEach((1920...currentYear).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                } header: {
                    Text("About you")
                } footer: {
                    Text("Your birth year lets you date memories by age (“when I was 7”).")
                }

                Section {
                    Toggle("Remind me of memories", isOn: $remindersEnabled)
                        .onChange(of: remindersEnabled) {
                            Task {
                                if remindersEnabled, !(await ReminderScheduler.requestAuthorization()) {
                                    remindersEnabled = false
                                    message = "Notifications are off for Memory Vault. Turn them on in the iPhone Settings app."
                                }
                                await ReminderScheduler.reschedule(context: context)
                            }
                        }
                    if remindersEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        Picker("How often", selection: $reminderFrequency) {
                            ForEach(ReminderFrequency.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        Button("Send a test reminder") {
                            Task {
                                await ReminderScheduler.sendTest(context: context)
                                message = "A reminder will arrive in about 5 seconds — lock your phone to see it."
                            }
                        }
                        .disabled(memories.isEmpty)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A random memory (or one from this day in past years) as a notification. Tap it to open the memory.")
                }
                .onChange(of: reminderHour) { Task { await ReminderScheduler.reschedule(context: context) } }
                .onChange(of: reminderMinute) { Task { await ReminderScheduler.reschedule(context: context) } }
                .onChange(of: reminderFrequency) { Task { await ReminderScheduler.reschedule(context: context) } }

                Section {
                    LabeledContent("Memories", value: "\(memories.count)")
                    LabeledContent("People", value: "\(people.count)")
                    Button("Export backup (JSON)") { export() }
                    Button("Import backup") { showImporter = true }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Everything lives only on this iPhone. Export a backup now and then (voice recordings aren't included). Text is sent to Anthropic for tagging and audio to OpenAI for transcription.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                anthropicKey = Keychain.read(.anthropic) ?? ""
                openAIKey = Keychain.read(.openAI) ?? ""
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "MemoryVault-\(Date().formatted(.iso8601.year().month().day()))"
            ) { result in
                if case let .failure(error) = result { message = error.localizedDescription }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .alert("Memory Vault", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func testClaude() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let client = try LLMFactory.makeClient()
            let reply = try await client.complete(LLMRequest(
                system: "Reply with a short friendly greeting of at most six words.",
                prompt: "Hello from Memory Vault!",
                maxTokens: 1024
            ))
            message = "Connected to \(AppSettings.claudeModel) ✓\n\n“\(reply)”"
        } catch {
            message = error.localizedDescription
        }
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try BackupService.export(context: context))
            showExporter = true
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let (addedPeople, addedMemories) = try BackupService.importBackup(data, context: context)
            message = "Imported \(addedMemories) memories and \(addedPeople) people."
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}
