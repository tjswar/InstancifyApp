import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationSettings = NotificationSettingsViewModel.shared
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // General Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("General")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        Toggle(isOn: $notificationSettings.runtimeAlertsEnabled) {
                            VStack(alignment: .leading) {
                                Text("Runtime Alerts")
                                    .font(.body)
                                Text("Get notified when instances run longer than specified durations")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .tint(appearanceViewModel.currentAccentColor)
                    }
                    .glassEffect()
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                
                // Alert Thresholds Section
                if notificationSettings.runtimeAlertsEnabled {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Alert Thresholds")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        VStack(spacing: 0) {
                            ForEach(notificationSettings.runtimeAlerts) { alert in
                                AlertThresholdRow(alert: alert)
                                if alert.id != notificationSettings.runtimeAlerts.last?.id {
                                    Divider()
                                }
                            }
                            
                            Button {
                                notificationSettings.addNewAlert()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Alert")
                                }
                                .foregroundColor(appearanceViewModel.currentAccentColor)
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                        }
                        .glassEffect()
                        .cornerRadius(16)
                        
                        Text("You'll be notified when any running instance exceeds these durations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                    .padding(.horizontal)
                }
                
                // Auto-Stop Notifications Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Auto-Stop Notifications")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        Toggle(isOn: $notificationSettings.autoStopWarningsEnabled) {
                            VStack(alignment: .leading) {
                                Text("Auto-Stop Warnings")
                                    .font(.body)
                                Text("Get notified before instances are automatically stopped")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        
                        Divider()
                        
                        Toggle(isOn: $notificationSettings.autoStopCountdownEnabled) {
                            VStack(alignment: .leading) {
                                Text("Countdown Updates")
                                    .font(.body)
                                Text("Get notified at specific intervals before auto-stop")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        
                        if notificationSettings.autoStopWarningsEnabled {
                            ForEach(notificationSettings.availableWarningIntervals, id: \.0) { interval, label in
                                Divider()
                                Toggle(isOn: .init(
                                    get: { notificationSettings.selectedWarningIntervals.contains(interval) },
                                    set: { _ in notificationSettings.toggleWarningInterval(interval) }
                                )) {
                                    Text(label)
                                        .font(.body)
                                }
                                .padding()
                            }
                        }
                    }
                    .glassEffect()
                    .cornerRadius(16)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Notification Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(appearanceViewModel.currentAccentColor)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct AlertThresholdRow: View {
    let alert: RuntimeAlert
    @StateObject private var notificationSettings = NotificationSettingsViewModel.shared
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @State private var hours: Int
    @State private var minutes: Int
    @State private var isEnabled: Bool
    
    init(alert: RuntimeAlert) {
        self.alert = alert
        _hours = State(initialValue: alert.hours)
        _minutes = State(initialValue: alert.minutes)
        _isEnabled = State(initialValue: alert.enabled)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .tint(appearanceViewModel.currentAccentColor)
                .onChange(of: isEnabled) { newValue in
                    notificationSettings.updateAlert(id: alert.id, enabled: newValue)
                }
            
            Picker("Hours", selection: $hours) {
                ForEach(0...24, id: \.self) { hour in
                    Text("\(hour)h").tag(hour)
                }
            }
            .frame(width: 80)
            .onChange(of: hours) { newValue in
                notificationSettings.updateAlert(id: alert.id, hours: newValue)
            }
            
            Picker("Minutes", selection: $minutes) {
                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { minute in
                    Text("\(minute)m").tag(minute)
                }
            }
            .frame(width: 80)
            .onChange(of: minutes) { newValue in
                notificationSettings.updateAlert(id: alert.id, minutes: newValue)
            }
            
            Spacer()
            
            Button {
                if let index = notificationSettings.runtimeAlerts.firstIndex(where: { $0.id == alert.id }) {
                    notificationSettings.deleteAlert(at: IndexSet(integer: index))
                }
            } label: {
                Image(systemName: "bell.slash.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
} 