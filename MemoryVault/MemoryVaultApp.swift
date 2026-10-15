import SwiftData
import SwiftUI
import UserNotifications

@main
struct MemoryVaultApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer = {
        // SwiftData stores in Application Support, which doesn't exist on a fresh install.
        // Creating it up front avoids a burst of harmless "Failed to stat path" CoreData errors.
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        do {
            return try ModelContainer(for: Memory.self, Person.self)
        } catch {
            fatalError("Could not open the memory database: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppRouter.shared)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                // Keep a fresh rolling window of reminder notifications.
                Task { @MainActor in await ReminderScheduler.reschedule(context: container.mainContext) }
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show reminders even while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Tapping a reminder opens that memory.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let idString = response.notification.request.content.userInfo["memoryID"] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run {
            AppRouter.shared.openMemory = AppRouter.MemoryLink(id: id)
        }
    }
}
