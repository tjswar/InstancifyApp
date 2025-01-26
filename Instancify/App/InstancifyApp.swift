import SwiftUI

@main
struct InstancifyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var ec2Service = EC2Service.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var appearanceViewModel = AppearanceSettingsViewModel()
    @StateObject private var appLockService = AppLockService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(notificationManager)
                .environmentObject(ec2Service)
                .environmentObject(appearanceViewModel)
                .environmentObject(appLockService)
                .tint(appearanceViewModel.currentAccentColor)
                .onAppear {
                    // Configure the appearance to use our dynamic accent color
                    UIView.appearance().tintColor = UIColor(appearanceViewModel.currentAccentColor)
                    
                    // Check app lock state on launch
                    if appLockService.isAppLockEnabled {
                        appLockService.checkLockState()
                    }
                }
                .onChange(of: appearanceViewModel.currentAccentColor) { newColor in
                    // Update the global tint when accent color changes
                    UIView.appearance().tintColor = UIColor(newColor)
                }
        }
    }
}