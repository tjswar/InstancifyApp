import Foundation
import UserNotifications

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    @Published var pendingNotifications: [NotificationType] = []
    @Published private(set) var isAuthorized = false
    @Published var mutedInstanceIds: Set<String> = []
    
    private override init() {
        super.init()
        Task {
            await setupNotificationCategories()
            await requestAuthorization()
        }
    }
    
    private func setupNotificationCategories() async {
        let stopAction = UNNotificationAction(
            identifier: "STOP_INSTANCE",
            title: "Stop Instance",
            options: [.destructive]
        )
        
        let muteAction = UNNotificationAction(
            identifier: "MUTE_INSTANCE",
            title: "Mute Notifications",
            options: []
        )
        
        let instanceCategory = UNNotificationCategory(
            identifier: "INSTANCE_NOTIFICATION",
            actions: [stopAction, muteAction],
            intentIdentifiers: [],
            options: []
        )
        
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([instanceCategory])
    }
    
    private func requestAuthorization() async {
        do {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            print("\n📱 Checking notification settings:")
            print("  • Authorization status: \(settings.authorizationStatus.rawValue)")
            print("  • Alert setting: \(settings.alertSetting.rawValue)")
            print("  • Sound setting: \(settings.soundSetting.rawValue)")
            print("  • Badge setting: \(settings.badgeSetting.rawValue)")
            
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                isAuthorized = granted
                print("  ✅ Notification authorization \(granted ? "granted" : "denied")")
                
            case .authorized:
                isAuthorized = true
                print("  ✅ Notifications already authorized")
                
            case .denied:
                isAuthorized = false
                print("  ⚠️ Notifications denied by user")
                
            case .provisional, .ephemeral:
                isAuthorized = true
                print("  ✅ Notifications authorized (provisional/ephemeral)")
                
            @unknown default:
                isAuthorized = false
                print("  ❌ Unknown notification authorization status")
            }
        } catch {
            print("  ❌ Error requesting notification authorization: \(error.localizedDescription)")
            isAuthorized = false
        }
    }
    
    func sendNotification(type: NotificationType) {
        guard isAuthorized else {
            print("\n⚠️ Cannot send notification - not authorized")
            print("  • Type: \(type.title)")
            print("  • Body: \(type.body)")
            return
        }
        
        // Check if notifications are muted for this instance
        if let instanceId = type.instanceId, mutedInstanceIds.contains(instanceId) {
            print("\n⚠️ Skipping notification - instance is muted")
            return
        }
        
        print("\n📱 Sending notification:")
        print("  • Type: \(type.title)")
        print("  • Body: \(type.body)")
        
        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = type.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "INSTANCE_NOTIFICATION"
        content.userInfo = ["instanceId": type.instanceId ?? ""]
        
        // Add to pending notifications
        pendingNotifications.append(type)
        
        let request = UNNotificationRequest(
            identifier: type.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                print("  ✅ Notification scheduled successfully")
                HapticManager.notification(type: .success)
            } catch {
                print("  ❌ Failed to schedule notification: \(error.localizedDescription)")
                // Remove from pending if failed to schedule
                pendingNotifications.removeAll(where: { $0.id == type.id })
            }
        }
    }
    
    func muteInstance(_ instanceId: String) {
        mutedInstanceIds.insert(instanceId)
        // Remove any pending notifications for this instance
        pendingNotifications.removeAll(where: { $0.instanceId == instanceId })
        Task {
            let center = UNUserNotificationCenter.current()
            await center.removeDeliveredNotifications(withIdentifiers: pendingNotifications.filter { $0.instanceId == instanceId }.map { $0.id })
        }
    }
    
    func unmuteInstance(_ instanceId: String) {
        mutedInstanceIds.remove(instanceId)
    }
    
    func clearNotifications() {
        pendingNotifications.removeAll()
        Task {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        }
    }
    
    func removeNotification(at index: Int) {
        guard index < pendingNotifications.count else { return }
        let notification = pendingNotifications[index]
        pendingNotifications.remove(at: index)
        
        Task {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [notification.id])
            center.removeDeliveredNotifications(withIdentifiers: [notification.id])
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let instanceId = response.notification.request.content.userInfo["instanceId"] as? String ?? ""
        
        switch response.actionIdentifier {
        case "STOP_INSTANCE":
            if !instanceId.isEmpty {
                // Stop the instance
                Task {
                    do {
                        try await EC2Service.shared.stopInstance(instanceId)
                        print("✅ Instance \(instanceId) stopped via notification action")
                    } catch {
                        print("❌ Failed to stop instance: \(error.localizedDescription)")
                    }
                }
            }
            
        case "MUTE_INSTANCE":
            if !instanceId.isEmpty {
                muteInstance(instanceId)
                print("🔕 Muted notifications for instance \(instanceId)")
            }
            
        default:
            break
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
} 