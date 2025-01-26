import SwiftUI

struct MainTabView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView()
                    .navigationTitle("Dashboard")
            }
            .tabItem {
                Image(systemName: "chart.bar.fill")
                Text("Dashboard")
            }
            .tag(0)
            
            NavigationStack {
                NotificationsListView()
            }
            .tabItem {
                Image(systemName: "bell.fill")
                Text("Notifications")
            }
            .badge(notificationManager.pendingNotifications.count)
            .tag(1)
            
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem {
                Image(systemName: "gear")
                Text("Settings")
            }
            .tag(2)
        }
        .tint(appearanceViewModel.currentAccentColor)
    }
} 