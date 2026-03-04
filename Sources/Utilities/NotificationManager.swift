import Foundation
import UserNotifications

enum NotificationManager {
    private static var available: Bool = {
        // UNUserNotificationCenter crashes when running outside an .app bundle
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return true
    }()

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    static func sendNotification(title: String, body: String) {
        guard available else {
            print("[Notification] \(title): \(body)")
            return
        }
        guard AppDefaults.shared.bool(forKey: "macOSNotificationsEnabled") else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification error: \(error)")
            }
        }
    }
}
