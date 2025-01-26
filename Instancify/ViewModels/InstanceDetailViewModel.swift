import SwiftUI
import AWSEC2

@MainActor
class InstanceDetailViewModel: ObservableObject {
    @Published var instance: EC2Instance
    @Published var isLoading = false
    @Published var error: String?
    @Published var showError = false
    @Published var activities: [InstanceActivity] = []
    
    private let ec2Service = EC2Service.shared
    private var costUpdateTimer: Timer?
    
    init(instance: EC2Instance) {
        self.instance = instance
        updateActivities()
        setupCostUpdateTimer()
    }
    
    private func setupCostUpdateTimer() {
        // Update costs every minute
        costUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateCosts()
            }
        }
        // Initial update
        Task { @MainActor in
            await updateCosts()
        }
    }
    
    @MainActor
    private func updateCosts() {
        let (current, projected) = ec2Service.calculateCosts(for: instance)
        var updatedInstance = instance
        updatedInstance.updateCosts(current: current, projected: projected)
        instance = updatedInstance
    }
    
    private func updateActivities() {
        activities = ec2Service.getActivities(for: instance.id)
    }
    
    @MainActor
    func updateFromService() {
        Task { @MainActor in
            if let updatedInstance = ec2Service.instances.first(where: { $0.id == instance.id }) {
                self.instance = updatedInstance
                self.updateCosts()
                self.updateActivities()
            }
        }
    }
    
    @MainActor
    func refresh() async {
        isLoading = true
        do {
            let instances = try await ec2Service.fetchInstances()
            if let updatedInstance = instances.first(where: { $0.id == instance.id }) {
                instance = updatedInstance
                updateCosts()
                updateActivities()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.showError = true
            }
        }
        isLoading = false
    }
    
    @MainActor
    func performAction(_ action: InstanceAction) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            switch action {
            case .start:
                try await ec2Service.startInstance(instance.id)
            case .stop:
                try await ec2Service.stopInstance(instance.id)
            case .reboot:
                try await ec2Service.rebootInstance(instance.id)
            case .terminate:
                try await ec2Service.terminateInstance(instance.id)
            }
            
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refresh()
            HapticManager.notification(type: .success)
        } catch {
            self.error = error.localizedDescription
            self.showError = true
            HapticManager.notification(type: .error)
        }
    }
} 