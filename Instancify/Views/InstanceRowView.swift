import SwiftUI
import AWSEC2

struct InstanceRowView: View {
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @ObservedObject var instance: EC2Instance
    let onAutoStopToggle: (Bool) -> Void
    let onAutoStopTimeChanged: (Date) -> Void
    
    @State private var showingAutoStopPicker = false
    @State private var isAutoStopEnabled: Bool
    @State private var countdown: String?
    
    init(instance: EC2Instance, onAutoStopToggle: @escaping (Bool) -> Void, onAutoStopTimeChanged: @escaping (Date) -> Void) {
        self.instance = instance
        self.onAutoStopToggle = onAutoStopToggle
        self.onAutoStopTimeChanged = onAutoStopTimeChanged
        _isAutoStopEnabled = State(initialValue: instance.autoStopEnabled)
        _countdown = State(initialValue: instance.countdown)
    }
    
    private func updateAutoStopState() {
        print("Updating auto-stop state: isAutoStopEnabled = \(isAutoStopEnabled), instance.autoStopEnabled = \(instance.autoStopEnabled)")
        if isAutoStopEnabled != instance.autoStopEnabled {
            withAnimation {
                isAutoStopEnabled = instance.autoStopEnabled
            }
        }
        print("Updating countdown: countdown = \(String(describing: countdown)), instance.countdown = \(String(describing: instance.countdown))")
        if countdown != instance.countdown {
            withAnimation {
                countdown = instance.countdown
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: InstanceDetailView(instance: instance)) {
                HStack(spacing: 16) {
                    Circle()
                        .fill(instance.state == .running ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(instance.name ?? instance.id)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                        
                        Text(instance.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        if instance.state == .running, let launchTime = instance.launchTime {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(Calendar.formatRuntime(from: launchTime))
                                    .font(.caption)
                            }
                            .foregroundColor(.green)
                            
                            Text("•")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        Text(instance.state.displayString)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(instance.state == .running ? .green : .red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            
            if instance.state == .running {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack(spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { isAutoStopEnabled },
                        set: { newValue in
                            withAnimation {
                                isAutoStopEnabled = newValue
                                onAutoStopToggle(newValue)
                            }
                        }
                    )) {
                        Label("Auto-stop", systemImage: "timer")
                            .font(.subheadline)
                    }
                    .tint(appearanceViewModel.currentAccentColor)
                    
                    if isAutoStopEnabled {
                        Spacer()
                        
                        Button {
                            showingAutoStopPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                if let currentCountdown = countdown {
                                    Text(currentCountdown)
                                        .monospacedDigit()
                                        .id(currentCountdown)
                                } else {
                                    Text("Set time")
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .font(.subheadline)
                            .foregroundColor(appearanceViewModel.currentAccentColor)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .glassEffect()
        .cornerRadius(16)
        .sheet(isPresented: $showingAutoStopPicker) {
            AutoStopPickerView(
                selectedTime: Date().addingTimeInterval(3600),
                onSave: { date in
                    onAutoStopTimeChanged(date)
                }
            )
        }
        .onChange(of: instance.autoStopEnabled) { _ in
            updateAutoStopState()
        }
        .onChange(of: instance.countdown) { _ in
            updateAutoStopState()
        }
        .onAppear {
            updateAutoStopState()
        }
    }
}

struct AutoStopPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Date) -> Void
    
    @State private var selectedTime: Date
    
    init(selectedTime: Date, onSave: @escaping (Date) -> Void) {
        self._selectedTime = State(initialValue: selectedTime)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            DatePicker(
                "Stop Time",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .navigationTitle("Set Auto-Stop Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selectedTime)
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct InstanceRowView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceRowView(
            instance: EC2Instance(
                id: "i-123456789",
                instanceType: "t2.micro",
                state: .running,
                name: "Preview Instance",
                launchTime: Date(),
                publicIP: "54.123.45.67",
                privateIP: "172.16.0.100",
                autoStopEnabled: false,
                countdown: nil,
                stateTransitionTime: nil,
                hourlyRate: 0.0116,
                runtime: 0,
                currentCost: 0,
                projectedDailyCost: 0
            ),
            onAutoStopToggle: { _ in },
            onAutoStopTimeChanged: { _ in }
        )
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}
#endif