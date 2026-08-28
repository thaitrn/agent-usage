import Foundation
import UsageCore
import UserNotifications

/// Fires a notification the first time a limit crosses 80% and again at 95%,
/// then stays quiet until that window resets — the poll runs every minute, so
/// "notify whenever it is high" would mean a notification every minute.
@MainActor
final class UsageAlerts {
    private var announced: [String: Severity] = [:]
    private var windows: [String: Date?] = [:]
    private var authorized = false

    /// Notifications need a bundle identifier, so this is a no-op under `swift run`.
    func requestAuthorization() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func process(_ groups: [UsageGroup]) {
        for group in groups {
            for limit in group.limits {
                // A new reset time means a fresh window: allow it to announce again.
                if windows[limit.id] ?? nil != limit.resetsAt {
                    windows[limit.id] = limit.resetsAt
                    announced[limit.id] = nil
                }
                let severity = limit.severity
                let previous = announced[limit.id] ?? .normal
                guard severity > previous else {
                    if severity < previous { announced[limit.id] = severity }
                    continue
                }
                announced[limit.id] = severity
                notify(group: group, limit: limit)
            }
        }
    }

    private func notify(group: UsageGroup, limit: UsageLimit) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(group.name) · \(limit.title)"
        content.body = ["Đã dùng \(limit.percent)%", limit.resetLabel].compactMap { $0 }.joined(separator: " · ")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(limit.id)-\(limit.percent)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
