import Foundation
import SwiftData
import UserNotifications

/// Schedules local "Remember this?" notifications, each featuring a memory.
/// iOS allows 64 pending notifications, so we keep a rolling window and refresh it whenever the app opens.
@MainActor
enum ReminderScheduler {
    private static let idPrefix = "memory-reminder-"
    private static let windowSize = 20

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) })

        guard AppSettings.remindersEnabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let memories = (try? context.fetch(FetchDescriptor<Memory>())) ?? []
        guard !memories.isEmpty else { return }

        let calendar = Calendar.current
        let interval = AppSettings.reminderFrequency.intervalDays
        var fireDate = nextFireDate(after: Date())
        var used = Set<UUID>()

        for index in 0..<windowSize {
            if index > 0 {
                fireDate = calendar.date(byAdding: .day, value: interval, to: fireDate) ?? fireDate
            }
            guard let memory = DailyPick.reminderPick(for: fireDate, from: memories, excluding: used) else { break }
            used.insert(memory.id)
            if used.count >= memories.count { used.removeAll() }

            let content = UNMutableNotificationContent()
            content.title = DailyPick.onThisDay(memory, on: fireDate) ? "On this day 📅" : "Remember this? 💭"
            content.subtitle = "\(memory.displayTitle) · \(memory.memoryDate.displayText)"
            content.body = String(memory.text.prefix(160))
            content.sound = .default
            content.userInfo = ["memoryID": memory.id.uuidString]

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: idPrefix + "\(index)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func sendTest(context: ModelContext) async {
        let memories = (try? context.fetch(FetchDescriptor<Memory>())) ?? []
        guard let memory = memories.randomElement() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Remember this? 💭"
        content.subtitle = "\(memory.displayTitle) · \(memory.memoryDate.displayText)"
        content.body = String(memory.text.prefix(160))
        content.sound = .default
        content.userInfo = ["memoryID": memory.id.uuidString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "memory-test", content: content, trigger: trigger)
        )
    }

    private static func nextFireDate(after date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = AppSettings.reminderHour
        components.minute = AppSettings.reminderMinute
        let today = calendar.date(from: components) ?? date
        return today > date ? today : (calendar.date(byAdding: .day, value: 1, to: today) ?? today)
    }
}
