import SwiftUI

struct InstancesList: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.instances) { instance in
                InstanceRowView(
                    instance: instance,
                    onAutoStopToggle: { isEnabled in
                        Task {
                            await viewModel.toggleAutoStop(for: instance.id, enabled: isEnabled)
                        }
                    },
                    onAutoStopTimeChanged: { time in
                        Task {
                            await viewModel.setAutoStopTime(for: instance.id, time: time)
                        }
                    }
                )
            }
        }
    }
}