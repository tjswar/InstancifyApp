import SwiftUI
import AWSEC2

#if DEBUG
class MockAuthManager: ObservableObject {
    @Published var isSignedIn: Bool = true
    @Published var currentUsername: String = "preview_user"
    @Published var identityId: String = "preview_identity"
    @Published var selectedRegion: AWSRegion = .usEast1
    @Published var credentials: AWSCredentials = .init(
        accessKeyId: "PREVIEW_ACCESS_KEY",
        secretAccessKey: "PREVIEW_SECRET_KEY"
    )
    
    func signOut() {
        // Preview implementation
    }
}
#endif

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var appearanceViewModel: AppearanceSettingsViewModel
    @EnvironmentObject private var authManager: AuthenticationManager
    
    var body: some View {
        NavigationView {
            DashboardContent(viewModel: viewModel)
                .navigationTitle("Dashboard")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        RegionPickerView(viewModel: viewModel)
                    }
                }
        }
        .tint(appearanceViewModel.currentAccentColor)
    }
}

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .environmentObject(MockAuthManager())
            .environmentObject(NotificationManager.shared)
            .environmentObject(AppearanceSettingsViewModel.shared)
    }
}
#endif

struct InstanceListView: View {
    let instances: [EC2Instance]
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(instances) { instance in
                    InstanceListItem(instance: instance)
                        // Add this to improve scrolling performance
                        .drawingGroup()
                }
            }
            .padding()
        }
    }
}
