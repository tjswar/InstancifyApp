import WidgetKit
import SwiftUI

struct InstanceEntry: TimelineEntry {
    let date: Date
    let instance: EC2Instance?
    let configuration: InstanceWidgetConfiguration
}

struct InstanceWidgetConfiguration {
    let instanceId: String
    let displayMode: InstanceWidgetDisplayMode
}

enum InstanceWidgetDisplayMode: String, CaseIterable {
    case status
    case cost
    case both
    
    var displayName: String {
        switch self {
        case .status: return "Status"
        case .cost: return "Cost"
        case .both: return "Status & Cost"
        }
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> InstanceEntry {
        InstanceEntry(
            date: Date(),
            instance: nil,
            configuration: InstanceWidgetConfiguration(
                instanceId: "",
                displayMode: .both
            )
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (InstanceEntry) -> Void) {
        let entry = InstanceEntry(
            date: Date(),
            instance: nil,
            configuration: InstanceWidgetConfiguration(
                instanceId: "",
                displayMode: .both
            )
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<InstanceEntry>) -> Void) {
        Task {
            do {
                // Get AWS credentials and configure AWS services
                let authManager = await AuthenticationManager.shared
                guard let credentials = try? await authManager.getAWSCredentials() else {
                    throw AWSError.noCredentialsFound
                }
                
                try await AWSManager.shared.configure(
                    accessKey: credentials.accessKeyId,
                    secretKey: credentials.secretAccessKey,
                    region: authManager.selectedRegion.awsRegionType
                )
                
                // Fetch instances
                let ec2Service = await EC2Service.shared
                let instances = try await ec2Service.fetchInstances()
                
                // Create timeline entries
                let currentDate = Date()
                let entries = [
                    InstanceEntry(
                        date: currentDate,
                        instance: instances.first,
                        configuration: InstanceWidgetConfiguration(
                            instanceId: instances.first?.id ?? "",
                            displayMode: .both
                        )
                    )
                ]
                
                // Update every 15 minutes
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
                let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
                
                completion(timeline)
            } catch {
                print("Widget error: \(error.localizedDescription)")
                let entry = InstanceEntry(
                    date: Date(),
                    instance: nil,
                    configuration: InstanceWidgetConfiguration(
                        instanceId: "",
                        displayMode: .both
                    )
                )
                let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
                completion(timeline)
            }
        }
    }
}

struct InstanceWidgetEntryView: View {
    let entry: InstanceEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        if let instance = entry.instance {
            switch entry.configuration.displayMode {
            case .status:
                InstanceStatusView(instance: instance)
            case .cost:
                InstanceCostView(instance: instance)
            case .both:
                VStack(spacing: 8) {
                    InstanceStatusView(instance: instance)
                    InstanceCostView(instance: instance)
                }
            }
        } else {
            Text("No Instance Data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct InstanceStatusView: View {
    let instance: EC2Instance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(instance.name ?? instance.id)
                .font(.headline)
                .lineLimit(1)
            
            HStack {
                Circle()
                    .fill(instance.state.color)
                    .frame(width: 8, height: 8)
                Text(instance.state.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct InstanceCostView: View {
    let instance: EC2Instance
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Cost")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(String(format: "$%.2f", instance.currentCost))
                .font(.headline)
            
            Text("Projected Daily")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(String(format: "$%.2f", instance.projectedDailyCost))
                .font(.subheadline)
        }
    }
}

struct InstancifyWidgets: Widget {
    private let kind = "InstancifyWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: Provider()
        ) { entry in
            InstanceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Instance Monitor")
        .description("Monitor your EC2 instance status and costs.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct InstancifyWidgets_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            InstanceWidgetEntryView(entry: InstanceEntry(
                date: Date(),
                instance: EC2Instance(
                    id: "i-123456789",
                    instanceType: "t2.micro",
                    state: .running,
                    name: "Test Instance",
                    launchTime: Date(),
                    publicIP: "1.2.3.4",
                    privateIP: "10.0.0.1",
                    autoStopEnabled: true,
                    countdown: "1h",
                    stateTransitionTime: Date(),
                    hourlyRate: 0.023,
                    runtime: 3600,
                    currentCost: 0.023,
                    projectedDailyCost: 0.552
                ),
                configuration: InstanceWidgetConfiguration(
                    instanceId: "i-123456789",
                    displayMode: .both
                )
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            
            InstanceWidgetEntryView(entry: InstanceEntry(
                date: Date(),
                instance: EC2Instance(
                    id: "i-123456789",
                    instanceType: "t2.micro",
                    state: .running,
                    name: "Test Instance",
                    launchTime: Date(),
                    publicIP: "1.2.3.4",
                    privateIP: "10.0.0.1",
                    autoStopEnabled: true,
                    countdown: "1h",
                    stateTransitionTime: Date(),
                    hourlyRate: 0.023,
                    runtime: 3600,
                    currentCost: 0.023,
                    projectedDailyCost: 0.552
                ),
                configuration: InstanceWidgetConfiguration(
                    instanceId: "i-123456789",
                    displayMode: .both
                )
            ))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}