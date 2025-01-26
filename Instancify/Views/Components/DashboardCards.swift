import SwiftUI

struct StatCard: View {
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

struct CostOverviewCard: View {
    let metrics: CostMetrics
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Cost Overview", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text("USD")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                CostMetricView(
                    title: "Today",
                    amount: metrics.dailyCost,
                    icon: "clock",
                    color: appearanceViewModel.currentAccentColor
                )
                
                CostMetricView(
                    title: "This Month",
                    amount: metrics.monthlyCost,
                    icon: "calendar",
                    color: appearanceViewModel.currentAccentColor
                )
            }
            
            CostMetricView(
                title: "Projected",
                amount: metrics.projectedCost,
                icon: "chart.line.uptrend.xyaxis",
                color: appearanceViewModel.currentAccentColor
            )
        }
        .padding()
    }
}

struct QuickActionsCard: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
            
            Button {
                Task {
                    await viewModel.stopAllInstances()
                }
            } label: {
                HStack {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                    Text("Stop All Instances")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoading || viewModel.isPerformingAction)
            
            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(.blue)
                    Text("Refresh Status")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoading || viewModel.isPerformingAction)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

private struct CostMetricView: View {
    let title: String
    let amount: Double
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("$")
                    .font(.caption)
                    .foregroundColor(color)
                Text(String(format: "%.2f", amount))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
} 