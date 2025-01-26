import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("\n🚀 Application launching...")
        
        // Configure AWS SDK with default settings
        AWSConfigurationService.configure()
        print("  ✅ AWS SDK configured")
        
        // Initialize UserDefaults suite
        if let _ = UserDefaults(suiteName: "tech.medilook.Instancify") {
            print("  ✅ UserDefaults suite initialized")
        } else {
            print("  ⚠️ Failed to initialize UserDefaults suite")
        }
        
        // Initialize app lock service
        _ = AppLockService.shared
        print("  ✅ App lock service initialized")
        
        // Start auto-stop monitoring
        _ = AutoStopService.shared
        print("  ✅ Auto-stop service initialized")
        
        // Initialize EC2 service and restore auto-stop timers
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await EC2Service.shared.restoreAutoStopTimers()
            print("  ✅ Auto-stop timers restored")
            
            // Start instance monitoring
            do {
                try await InstanceMonitoringService.shared.startMonitoring()
                print("  ✅ Instance monitoring started")
            } catch {
                print("  ⚠️ Failed to start instance monitoring: \(error.localizedDescription)")
            }
        }
        
        print("✅ Application launch complete\n")
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        print("\n📱 Application resigning active...")
        Task { @MainActor in
            EC2Service.shared.handleEnterBackground()
            InstanceMonitoringService.shared.stopMonitoring()
            
            // Lock app if enabled
            if AppLockService.shared.isAppLockEnabled {
                AppLockService.shared.lock()
            }
        }
        print("✅ Background handling complete\n")
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("\n📱 Application becoming active...")
        Task { @MainActor in
            EC2Service.shared.handleEnterForeground()
            
            // Check app lock state
            if AppLockService.shared.isAppLockEnabled {
                AppLockService.shared.checkLockState()
            }
            
            do {
                try await InstanceMonitoringService.shared.startMonitoring()
                print("  ✅ Instance monitoring restarted")
            } catch {
                print("  ⚠️ Failed to restart instance monitoring: \(error.localizedDescription)")
            }
        }
        print("✅ Foreground handling complete\n")
    }
} 