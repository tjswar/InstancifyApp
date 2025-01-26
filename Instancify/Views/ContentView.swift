import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var appLockService = AppLockService.shared
    @StateObject private var appearanceViewModel = AppearanceSettingsViewModel.shared
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            if !authManager.isAuthenticated {
                AuthenticationView()
            } else {
                if appLockService.isLocked {
                    LockScreenView()
                } else {
                    TabView(selection: $selectedTab) {
                        DashboardView()
                            .tabItem {
                                Label("Dashboard", systemImage: "gauge")
                            }
                            .tag(0)
                        
                        SettingsView()
                            .tabItem {
                                Label("Settings", systemImage: "gear")
                            }
                            .tag(1)
                    }
                    .tint(appearanceViewModel.currentAccentColor)
                }
            }
        }
        .environmentObject(appearanceViewModel)
        .tint(appearanceViewModel.currentAccentColor)
        .onChange(of: appLockService.isLocked) { isLocked in
            if isLocked {
                // Add haptic feedback when app is locked
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else {
                // Lock screen is dismissed
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if appLockService.isAppLockEnabled {
                appLockService.lock()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if appLockService.isAppLockEnabled {
                appLockService.checkLockState()
            }
        }
        .animation(.easeInOut, value: appLockService.isLocked)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager.shared)
        .environmentObject(NotificationManager.shared)
} 
