import Foundation
import UserNotifications

/// Native macOS notifications on busy→idle transitions. Respects the in-app toggle
/// (independent of OS authorization). Requires an ad-hoc signed bundle for reliable delivery.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Set by AppState; invoked when the user clicks a notification.
    var onOpenSession: ((String) -> Void)?
    private(set) var authorized = false

    private var center: UNUserNotificationCenter { .current() }

    func bootstrap() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// Post a "waiting for you" notification. No-op when the in-app toggle is off.
    func notifyIdle(sessionId: String, title: String, enabled: Bool, sound: Bool, lang: Language) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = tr("Session waiting", lang)
        content.body = tr("Session “%@” is waiting for your reply.", lang, [title])
        content.sound = sound ? .default : nil
        content.userInfo = ["sessionId": sessionId]
        let req = UNNotificationRequest(identifier: "idle-\(sessionId)-\(Int(Date().timeIntervalSince1970))",
                                        content: content, trigger: nil)
        center.add(req)
    }

    // Show banners even while the app is frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let id = info["sessionId"] as? String {
            Task { @MainActor in self.onOpenSession?(id) }
        }
        completionHandler()
    }
}

#if canImport(AppKit)
import AppKit
#endif
