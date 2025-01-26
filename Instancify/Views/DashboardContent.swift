import SwiftUI
import AWSEC2

struct DashboardContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showSettings = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 24) {
                // Stats Cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Running",
                        count: viewModel.runningInstancesCount,
                        icon: "play.circle.fill",
                        color: .green
                    )
                    .glassEffect()
                    
                    StatCard(
                        title: "Stopped",
                        count: viewModel.stoppedInstancesCount,
                        icon: "stop.circle.fill",
                        color: .red
                    )
                    .glassEffect()
                }
                .padding(.horizontal)
                
                // Cost Overview Card
                if let metrics = viewModel.costMetrics {
                    CostOverviewCard(metrics: metrics)
                        .glassEffect()
                        .padding(.horizontal)
                }
                
                // Quick Actions
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Actions")
                        .font(.headline)
                    
                    // Start All
                    QuickActionButton(
                        title: "Start All",
                        icon: "play.circle.fill",
                        color: .green,
                        isEnabled: viewModel.hasStoppedInstances
                    ) {
                        HapticManager.impact(style: .medium)
                        viewModel.showStartAllConfirmation = true
                    }
                    
                    // Stop All
                    QuickActionButton(
                        title: "Stop All",
                        icon: "stop.circle.fill",
                        color: .red,
                        isEnabled: viewModel.hasRunningInstances
                    ) {
                        HapticManager.impact(style: .medium)
                        viewModel.showStopAllConfirmation = true
                    }
                    
                    // Refresh Status
                    QuickActionButton(
                        title: "Refresh Status",
                        icon: "arrow.clockwise.circle.fill",
                        color: .blue,
                        isEnabled: !viewModel.isLoading
                    ) {
                        HapticManager.impact(style: .light)
                        Task {
                            await viewModel.refresh()
                        }
                    }
                }
                .padding()
                .glassEffect()
                .cornerRadius(12)
                .padding(.horizontal)
                .confirmationDialog(
                    "Start All Instances",
                    isPresented: $viewModel.showStartAllConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Start All") {
                        Task {
                            await viewModel.startAllInstances()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to start all stopped instances? This will incur costs.")
                }
                .confirmationDialog(
                    "Stop All Instances",
                    isPresented: $viewModel.showStopAllConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Stop All", role: .destructive) {
                        Task {
                            await viewModel.stopAllInstances()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to stop all running instances?")
                }
                
                // Instances List
                if !viewModel.instances.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Instances")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        ForEach(viewModel.instances) { instance in
                            InstanceRowView(
                                instance: instance,
                                onAutoStopToggle: { isEnabled in
                                    Task {
                                        await viewModel.toggleAutoStop(for: instance.id, enabled: isEnabled)
                                    }
                                },
                                onAutoStopTimeChanged: { date in
                                    Task {
                                        await viewModel.setAutoStopTime(for: instance.id, time: date)
                                    }
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await viewModel.refresh()
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
    }
}

struct InstanceDetailsSection: View {
    let instance: EC2Instance
    
    var body: some View {
        Section("Instance Details") {
            DetailRow(
                title: "Instance ID",
                value: instance.id,
                icon: "server.rack"
            )
            
            DetailRow(
                title: "Type",
                value: instance.instanceType,
                icon: "cpu"
            )
            
            DetailRow(
                title: "State",
                value: instance.state.rawValue.capitalized,
                icon: "power",
                iconColor: instance.state == .running ? .green : .secondary
            )
            
            RuntimeDetailRow(instance: instance)
            
            if let publicIP = instance.publicIP {
                DetailRow(
                    title: "Public IP",
                    value: publicIP,
                    icon: "network"
                )
            }
            
            if let privateIP = instance.privateIP {
                DetailRow(
                    title: "Private IP",
                    value: privateIP,
                    icon: "lock.shield"
                )
            }
        }
    }
}

#Preview {
    List {
        InstanceDetailsSection(instance: EC2Instance(
            id: "i-1234567890abcdef0",
            instanceType: "t2.micro",
            state: .running,
            name: "Test Instance",
            launchTime: Date(),
            publicIP: "1.2.3.4",
            privateIP: "10.0.0.1",
            autoStopEnabled: false,
            countdown: nil,
            stateTransitionTime: nil,
            hourlyRate: 0.0116,
            runtime: 3600,
            currentCost: 0.0116,
            projectedDailyCost: 0.2784
        ))
    }
} 