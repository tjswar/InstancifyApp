import Foundation

class CostCalculationService {
    static let shared = CostCalculationService()
    
    // Standard hourly rates for EC2 instances (in USD)
    private let hourlyRates: [String: Double] = [
        "t2.micro": 0.0116,
        "t2.small": 0.023,
        "t2.medium": 0.0464,
        "t2.large": 0.0928,
        "t3.micro": 0.0104,
        "t3.small": 0.0208,
        "t3.medium": 0.0416,
        "t3.large": 0.0832,
        // Add more instance types as needed
    ]
    
    func calculateCosts(for instance: EC2Instance) -> (today: Double, thisMonth: Double, projected: Double) {
        let now = Date()
        let calendar = Calendar.current
        
        // Get the start of today
        let startOfToday = calendar.startOfDay(for: now)
        
        // Get the start of the month
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        
        // Get the end of the month
        let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth)!
        
        // Calculate running time
        let hourlyRate = hourlyRates[instance.instanceType] ?? 0.0116 // Default to t2.micro rate
        
        // Today's cost
        let todayCost = calculateCost(
            from: max(startOfToday, instance.launchTime ?? startOfToday),
            to: instance.state == .running ? now : (instance.stateTransitionTime ?? now),
            hourlyRate: hourlyRate
        )
        
        // This month's cost
        let monthCost = calculateCost(
            from: max(startOfMonth, instance.launchTime ?? startOfMonth),
            to: instance.state == .running ? now : (instance.stateTransitionTime ?? now),
            hourlyRate: hourlyRate
        )
        
        // Projected cost (assuming instance keeps running until end of month)
        let projectedCost: Double
        if instance.state == .running {
            projectedCost = monthCost + calculateCost(
                from: now,
                to: endOfMonth,
                hourlyRate: hourlyRate
            )
        } else {
            projectedCost = monthCost
        }
        
        return (todayCost, monthCost, projectedCost)
    }
    
    private func calculateCost(from startDate: Date, to endDate: Date, hourlyRate: Double) -> Double {
        let runningHours = max(0, endDate.timeIntervalSince(startDate) / 3600)
        return runningHours * hourlyRate
    }
} 