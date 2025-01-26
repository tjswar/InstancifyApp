import Foundation
import Combine
import AWSEC2
import AWSCloudWatch
import UserNotifications

@MainActor
class InstanceMonitoringService: ObservableObject {
    static let shared = InstanceMonitoringService()
    private let notificationManager = NotificationManager.shared
    private let ec2Service = EC2Service.shared
    
    @Published private(set) var isMonitoring = false
    private var monitoringTask: Task<Void, Never>?
    private var instances: [EC2Instance] = []
    
    private init() {}
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        monitoringTask = Task {
            while !Task.isCancelled {
                await checkInstances()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 minutes
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        monitoringTask?.cancel()
        monitoringTask = nil
    }
    
    private func checkInstances() async {
        do {
            let newInstances = try await ec2Service.fetchInstances()
            instances = newInstances
            
            for instance in instances {
                if instance.state == .running {
                    let runtime = instance.runtime
                    if runtime >= 3600 { // 1 hour
                        await notificationManager.sendNotification(
                            type: .instanceRunningLong(
                                instanceId: instance.id,
                                name: instance.name ?? instance.id,
                                runtime: TimeInterval(runtime),
                                cost: instance.currentCost
                            )
                        )
                    }
                }
            }
        } catch {
            print("Error checking instances: \(error.localizedDescription)")
        }
    }
} 