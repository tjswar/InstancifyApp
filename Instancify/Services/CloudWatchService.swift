import Foundation
import AWSCloudWatch
import AWSCore
import AWSEC2

@MainActor
class CloudWatchService {
    static let shared = CloudWatchService()
    private let cloudWatchClient = AWSCloudWatch.default()
    
    private init() {}
    
    func getInstanceMetrics(instanceId: String) async throws -> InstanceMetrics {
        let endTime = Date()
        let startTime = Calendar.current.date(byAdding: .minute, value: -5, to: endTime)!
        
        guard let cpuRequest = AWSCloudWatchGetMetricStatisticsInput(),
              let dimension = AWSCloudWatchDimension() else {
            throw NSError(domain: "CloudWatchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create request"])
        }
        
        cpuRequest.namespace = "AWS/EC2"
        cpuRequest.metricName = "CPUUtilization"
        
        dimension.name = "InstanceId"
        dimension.value = instanceId
        
        cpuRequest.dimensions = [dimension]
        cpuRequest.startTime = startTime
        cpuRequest.endTime = endTime
        cpuRequest.period = NSNumber(value: 300) // 5 minutes
        cpuRequest.statistics = ["Average"]
        
        return try await withCheckedThrowingContinuation { continuation in
            cloudWatchClient.getMetricStatistics(cpuRequest) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let cpuUtilization = response?.datapoints?.first?.average?.doubleValue ?? 0.0
                
                let metrics = InstanceMetrics(
                    cpuUtilization: cpuUtilization,
                    memoryUsage: 0.0,
                    networkIn: 0.0,
                    networkOut: 0.0,
                    diskReadOps: 0.0,
                    diskWriteOps: 0.0
                )
                
                continuation.resume(returning: metrics)
            }
        }
    }
    
    func fetchCostMetrics(for instances: [EC2Instance]) async throws -> CostMetrics {
        // Calculate daily cost (cost for today only)
        let dailyCost = instances.reduce(0.0) { total, instance in
            if instance.state == .running {
                let now = Date()
                let calendar = Calendar.current
                let startOfDay = calendar.startOfDay(for: now)
                let runtime = now.timeIntervalSince(max(startOfDay, instance.launchTime ?? now))
                return total + (instance.hourlyRate * (runtime / 3600))
            }
            return total
        }
        
        // Calculate monthly cost (based on actual runtime this month)
        let monthlyCost = instances.reduce(0.0) { total, instance in
            if let launchTime = instance.launchTime {
                let now = Date()
                let calendar = Calendar.current
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let runtime = now.timeIntervalSince(max(startOfMonth, launchTime))
                return total + (instance.hourlyRate * (runtime / 3600))
            }
            return total
        }
        
        // Calculate projected monthly cost based on current running instances
        let projectedCost = instances.reduce(0.0) { total, instance in
            if instance.state == .running {
                let now = Date()
                let calendar = Calendar.current
                let daysInMonth = Double(calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
                let currentDay = Double(calendar.component(.day, from: now))
                let remainingDays = daysInMonth - currentDay + 1
                
                // Calculate cost for the rest of the month
                let projectedRemainingCost = instance.hourlyRate * 24 * remainingDays
                
                // Add the cost we've already incurred this month
                let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
                let runtime = now.timeIntervalSince(max(startOfMonth, instance.launchTime ?? now))
                let incurredCost = instance.hourlyRate * (runtime / 3600)
                
                return total + incurredCost + projectedRemainingCost
            }
            return total
        }
        
        return CostMetrics(
            dailyCost: (dailyCost * 100).rounded() / 100,
            monthlyCost: (monthlyCost * 100).rounded() / 100,
            projectedCost: (projectedCost * 100).rounded() / 100
        )
    }
} 