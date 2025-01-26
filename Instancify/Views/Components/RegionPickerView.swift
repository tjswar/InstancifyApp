import SwiftUI

struct RegionPickerView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        Menu {
            ForEach(AWSRegion.allCases, id: \.rawValue) { region in
                Button {
                    Task {
                        authManager.selectedRegion = region
                        await viewModel.changeRegion(region)
                    }
                } label: {
                    HStack {
                        Text(region.displayName)
                        if authManager.selectedRegion == region {
                            Image(systemName: "checkmark")
                                .foregroundStyle(appearanceViewModel.currentAccentColor)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .foregroundStyle(appearanceViewModel.currentAccentColor)
                Text(authManager.selectedRegion.displayName)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .foregroundStyle(appearanceViewModel.currentAccentColor)
                    .font(.caption)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(appearanceViewModel.currentAccentColor.opacity(0.1))
            .cornerRadius(8)
        }
        .tint(appearanceViewModel.currentAccentColor)
    }
} 