import Foundation
import UserNotifications

struct AutoStopSettings: Codable {
    var isEnabled: Bool
    var stopTime: Date?
}

class AutoStopSettingsService {
    static let shared = AutoStopSettingsService()
    private let defaults: UserDefaults
    private let settingsKey = "instanceAutoStopSettings"
    private let suiteName = "group.tech.medilook.Instancify"
    
    private init() {
        // Initialize UserDefaults with app group
        if let suiteDefaults = UserDefaults(suiteName: suiteName) {
            self.defaults = suiteDefaults
            print("✅ Initialized UserDefaults with suite name: \(suiteName)")
            
            // Ensure defaults are synchronized
            self.defaults.synchronize()
            
            // Log current settings
            let settings = getAllSettings()
            print("📊 Current auto-stop settings:")
            print("  • Number of settings: \(settings.count)")
            for (instanceId, setting) in settings {
                print("  • Instance \(instanceId):")
                print("    - Enabled: \(setting.isEnabled)")
                print("    - Stop time: \(String(describing: setting.stopTime))")
            }
        } else {
            self.defaults = UserDefaults.standard
            print("⚠️ Failed to initialize UserDefaults with suite name, falling back to standard")
        }
    }
    
    func saveSettings(for instanceId: String, enabled: Bool, time: Date?) {
        print("\n📝 Saving auto-stop settings for instance \(instanceId)")
        print("  • Enabled: \(enabled)")
        print("  • Stop time: \(String(describing: time))")
        
        var settings = getAllSettings()
        settings[instanceId] = AutoStopSettings(isEnabled: enabled, stopTime: time)
        
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
            // Force synchronize and verify
            let success = defaults.synchronize()
            print("  ✅ Settings saved successfully (synchronized: \(success))")
            
            // Verify the settings were saved
            if let savedSettings = getSettings(for: instanceId) {
                print("  • Verified saved settings:")
                print("    - Enabled: \(savedSettings.isEnabled)")
                print("    - Stop time: \(String(describing: savedSettings.stopTime))")
            } else {
                print("  ⚠️ Warning: Could not verify saved settings")
            }
            
            print("  • Current settings: \(settings)")
        } else {
            print("  ❌ Failed to encode settings")
        }
        
        // Clear notifications if no time is set
        if time == nil {
            Task {
                let warningIntervals = [3600, 1800, 900, 300, 60]
                let warningIds = warningIntervals.map { "warning-\(instanceId)-\($0)" }
                let notificationIds = warningIds + ["final-\(instanceId)"]
                await UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIds)
                await UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notificationIds)
            }
        }
    }
    
    func getSettings(for instanceId: String) -> AutoStopSettings? {
        print("\n🔍 Getting auto-stop settings for instance \(instanceId)")
        let settings = getAllSettings()
        let result = settings[instanceId]
        print("  • Found settings: \(String(describing: result))")
        return result
    }
    
    func getAllSettings() -> [String: AutoStopSettings] {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode([String: AutoStopSettings].self, from: data) else {
            print("  ℹ️ No settings found or failed to decode")
            return [:]
        }
        return settings
    }
    
    func clearSettings(for instanceId: String) {
        print("\n🗑️ Clearing auto-stop settings for instance \(instanceId)")
        
        var settings = getAllSettings()
        settings.removeValue(forKey: instanceId)
        
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
            defaults.synchronize()
            print("  ✅ Settings cleared successfully")
        }
        
        // Clear all notifications
        Task {
            let warningIntervals = [3600, 1800, 900, 300, 60]
            let warningIds = warningIntervals.map { "warning-\(instanceId)-\($0)" }
            let notificationIds = warningIds + ["final-\(instanceId)", "autoStop-\(instanceId)"]
            
            await UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: notificationIds)
            await UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: notificationIds)
        }
    }
    
    func removeAllSettingsForInstance(_ instanceId: String) {
        clearSettings(for: instanceId)
    }
} 