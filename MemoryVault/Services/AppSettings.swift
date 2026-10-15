import Foundation

/// UserDefaults keys, shared by `@AppStorage` in views and `AppSettings` in services.
enum SettingsKey {
    static let claudeModel = "claudeModel"
    static let transcriptionModel = "transcriptionModel"
    static let userName = "userName"
    static let birthYear = "birthYear"
    static let keepAudio = "keepAudio"
    static let remindersEnabled = "remindersEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    static let reminderFrequency = "reminderFrequency"
    static let draftText = "draftText"
}

enum ReminderFrequency: String, CaseIterable, Identifiable {
    case daily, everyOtherDay, twiceAWeek, weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .everyOtherDay: "Every other day"
        case .twiceAWeek: "Twice a week"
        case .weekly: "Once a week"
        }
    }

    var intervalDays: Int {
        switch self {
        case .daily: 1
        case .everyOtherDay: 2
        case .twiceAWeek: 3
        case .weekly: 7
        }
    }
}

enum AppSettings {
    static let defaultClaudeModel = "claude-haiku-5-5"
    static let defaultTranscriptionModel = "gpt-4o-transcribe"
    static let transcriptionModels = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]

    private static var defaults: UserDefaults { .standard }

    static var claudeModel: String {
        let value = defaults.string(forKey: SettingsKey.claudeModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? defaultClaudeModel : value
    }

    static var transcriptionModel: String {
        let value = defaults.string(forKey: SettingsKey.transcriptionModel) ?? ""
        return value.isEmpty ? defaultTranscriptionModel : value
    }

    static var userName: String { defaults.string(forKey: SettingsKey.userName) ?? "" }

    static var birthYear: Int? {
        let value = defaults.integer(forKey: SettingsKey.birthYear)
        return value > 1900 ? value : nil
    }

    static var keepAudio: Bool {
        defaults.object(forKey: SettingsKey.keepAudio) as? Bool ?? true
    }

    static var remindersEnabled: Bool { defaults.bool(forKey: SettingsKey.remindersEnabled) }

    static var reminderHour: Int {
        defaults.object(forKey: SettingsKey.reminderHour) as? Int ?? 19
    }

    static var reminderMinute: Int {
        defaults.object(forKey: SettingsKey.reminderMinute) as? Int ?? 0
    }

    static var reminderFrequency: ReminderFrequency {
        ReminderFrequency(rawValue: defaults.string(forKey: SettingsKey.reminderFrequency) ?? "") ?? .daily
    }

    static var hasAnthropicKey: Bool { Keychain.read(.anthropic) != nil }
    static var hasOpenAIKey: Bool { Keychain.read(.openAI) != nil }
}
