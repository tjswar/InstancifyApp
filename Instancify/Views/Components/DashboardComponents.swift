import SwiftUI

// MARK: - Instance Stats Card
struct InstanceStatCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .foregroundColor(.secondary)
            }
            .font(.footnote)
            
            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Cost Card
struct CostCard: View {
    let title: String
    let amount: Double
    let trend: CostTrend
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.caption)
                    .foregroundColor(color)
                Text(String(format: "%.2f", amount))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            
            HStack {
                Image(systemName: trend.icon)
                    .foregroundColor(trend.color)
                Text(trend.text)
                    .font(.caption)
                    .foregroundColor(trend.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Cost Overview Section
struct CostOverviewSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cost Overview")
                .font(.title2)
                .fontWeight(.bold)
            
            HStack(spacing: 16) {
                CostCard(
                    title: "Today",
                    amount: viewModel.costMetrics?.dailyCost ?? 0,
                    trend: .up,
                    color: .blue
                )
                
                CostCard(
                    title: "This Month",
                    amount: viewModel.costMetrics?.monthlyCost ?? 0,
                    trend: .down,
                    color: .purple
                )
            }
            
            CostCard(
                title: "Projected",
                amount: viewModel.costMetrics?.projectedCost ?? 0,
                trend: .neutral,
                color: .orange
            )
        }
    }
}

// MARK: - Stats Overview Section
struct DashboardStatsView: View {
    let runningCount: Int
    let stoppedCount: Int
    let totalInstances: Int
    
    var body: some View {
        HStack(spacing: 16) {
            InstanceStatCard(
                title: "Running",
                count: runningCount,
                icon: "play.circle.fill",
                color: .green
            )
            
            InstanceStatCard(
                title: "Stopped",
                count: stoppedCount,
                icon: "stop.circle.fill",
                color: .red
            )
            
            InstanceStatCard(
                title: "Total",
                count: totalInstances,
                icon: "server.rack",
                color: .blue
            )
        }
        .padding(.horizontal)
    }
}

// MARK: - Supporting Types
enum CostTrend {
    case up, down, neutral
    
    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .neutral: return "arrow.right"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .red
        case .down: return .green
        case .neutral: return .orange
        }
    }
    
    var text: String {
        switch self {
        case .up: return "12% vs last week"
        case .down: return "8% vs last month"
        case .neutral: return "Based on usage"
        }
    }
} 