import Foundation
import AWSEC2
import AWSCore
import AWSCloudWatch
import UserNotifications
import SwiftUI

@MainActor
class EC2Service: ObservableObject {
    static let shared = EC2Service()
    private var ec2: AWSEC2
    private var currentCredentials: AWSCredentials?
    private var instanceNames: [String: String] = [:]
    @Published private(set) var instances: [EC2Instance] = []
    
    private var costUpdateTimer: Timer?
    
    // Add a debouncer for updates
    private var updateWorkItem: DispatchWorkItem?
    
    // Add throttling for updates
    private var lastUpdateTime: Date = .distantPast
    private let minimumUpdateInterval: TimeInterval = 1.0 // Minimum time between updates
    
    private struct InstanceHistory: Codable {
        let instanceId: String
        let startTime: Date
        let endTime: Date
        let runtime: TimeInterval
        let cost: Double
        let instanceType: String
    }
    
    private struct RuntimeRecord: Codable {
        let date: Date
        let runtime: TimeInterval
        let cost: Double
        let fromState: String
        let toState: String
    }
    
    // Replace installDate with loginDate
    private var loginDate: Date?
    
    private var instanceActivities: [String: [InstanceActivity]] = [:]
    
    // Add this property to track auto-stop timers
    private var autoStopTimers: [String: Timer] = [:]
    
    // Add these properties at the top of the class
    private var countdownTimers: [String: Timer] = [:]
    private var countdownWorkItems: [String: DispatchWorkItem] = [:]
    
    // Add these properties at the top of the class
    @Published private var autoStopConfigs: [String: AutoStopConfig] = [:] {
        didSet {
            print("\n📝 Auto-stop configs updated:")
            print("  • Number of configs: \(autoStopConfigs.count)")
            print("  • Configs: \(autoStopConfigs)")
        }
    }
    private var autoStopUpdateTimer: Timer?
    
    private func setupFirstLaunchDate() {
        if UserDefaults.standard.object(forKey: "appFirstLaunchDate") == nil {
            UserDefaults.standard.set(Date(), forKey: "appFirstLaunchDate")
        }
    }
    
    private init() {
        print("🔧 Initializing EC2Service...")
        
        let defaultConfig = AWSServiceConfiguration(
            region: .USEast2,
            credentialsProvider: AWSAnonymousCredentialsProvider()
        )!
        AWSEC2.register(with: defaultConfig, forKey: "DefaultKey")
        self.ec2 = AWSEC2(forKey: "DefaultKey")
        setupCostUpdateTimer()
        startAutoStopMonitoring()
        print("✅ EC2Service initialization complete")
    }
    
    func updateConfiguration(with credentials: AWSCredentials, region: AWSRegionType) {
        print("🔄 Updating EC2Service configuration...")
        
        // Set login date when credentials are updated
        loginDate = Date()
        
        print("🔑 Using Access Key: \(credentials.accessKeyId)")
        print("🌎 Region: \(region.rawValue)")
        
        currentCredentials = credentials
        
        let credentialsProvider = AWSStaticCredentialsProvider(
            accessKey: credentials.accessKeyId,
            secretKey: credentials.secretAccessKey
        )
        
        let configuration = AWSServiceConfiguration(
            region: region,
            credentialsProvider: credentialsProvider
        )!
        
        AWSEC2.register(with: configuration, forKey: "DefaultKey")
        self.ec2 = AWSEC2(forKey: "DefaultKey")
        
        print("✅ EC2Service configuration updated")
    }
    
    func fetchInstances() async throws -> [EC2Instance] {
        let oldInstances = self.instances
        
        let request = AWSEC2DescribeInstancesRequest()!
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            self?.ec2.describeInstances(request) { response, error in
                Task { @MainActor in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    guard let reservations = response?.reservations else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    var instances: [EC2Instance] = []
                    
                    for reservation in reservations {
                        guard let awsInstances = reservation.instances else { continue }
                        
                        for awsInstance in awsInstances {
                            if let instance = self?.createInstance(from: awsInstance) {
                                instances.append(instance)
                            }
                        }
                    }
                    
                    self?.instances = instances
                    
                    // Track state changes for each instance
                    for instance in instances {
                        if let oldInstance = oldInstances.first(where: { $0.id == instance.id }),
                           oldInstance.state != instance.state {
                            self?.trackStateChange(
                                instance: instance,
                                from: oldInstance.state.rawValue,
                                to: instance.state.rawValue
                            )
                        }
                    }
                    
                    continuation.resume(returning: instances)
                }
            }
        }
    }
    
    private func createInstance(from awsInstance: AWSEC2Instance) -> EC2Instance? {
        guard let instanceId = awsInstance.instanceId else { return nil }
        
        let name = awsInstance.tags?.first(where: { $0.key == "Name" })?.value
        let instanceType = String(describing: awsInstance.instanceType)
            .replacingOccurrences(of: "AWSEC2InstanceType(rawValue: ", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let hourlyRate = self.getInstanceHourlyRate(type: instanceType)
        
        let stateCode = awsInstance.state?.code?.intValue
        let stateString = self.getStateString(from: stateCode)
        let state = InstanceState(rawValue: stateString) ?? .unknown
        
        // Get auto-stop settings
        let autoStopSettings = AutoStopSettingsService.shared.getSettings(for: instanceId)
        let isAutoStopEnabled = autoStopSettings?.isEnabled ?? false
        let stopTime = autoStopSettings?.stopTime
        
        // Calculate initial runtime and costs
        let runtime: Double
        
        if state == .running, let launchTime = awsInstance.launchTime {
            runtime = Date().timeIntervalSince(launchTime)
            let hourlyRuntime = runtime / 3600.0
            let cost = hourlyRuntime * hourlyRate
            let projectedDaily = hourlyRate * 24.0
            
            let instance = EC2Instance(
                id: instanceId,
                instanceType: instanceType,
                state: state,
                name: name ?? instanceId,
                launchTime: awsInstance.launchTime,
                publicIP: awsInstance.publicIpAddress,
                privateIP: awsInstance.privateIpAddress,
                autoStopEnabled: isAutoStopEnabled,
                countdown: stopTime != nil ? DateFormatter.localizedString(from: stopTime!, dateStyle: .none, timeStyle: .short) : (isAutoStopEnabled ? "Set time" : nil),
                stateTransitionTime: nil,
                hourlyRate: hourlyRate,
                runtime: Int(runtime),
                currentCost: cost,
                projectedDailyCost: projectedDaily
            )
            
            self.instanceNames[instanceId] = name ?? instanceId
            instance.updateCosts(
                current: cost,
                projected: projectedDaily
            )
            return instance
        } else {
            runtime = 0
            let instance = EC2Instance(
                id: instanceId,
                instanceType: instanceType,
                state: state,
                name: name ?? instanceId,
                launchTime: awsInstance.launchTime,
                publicIP: awsInstance.publicIpAddress,
                privateIP: awsInstance.privateIpAddress,
                autoStopEnabled: isAutoStopEnabled,
                countdown: stopTime != nil ? DateFormatter.localizedString(from: stopTime!, dateStyle: .none, timeStyle: .short) : (isAutoStopEnabled ? "Set time" : nil),
                stateTransitionTime: nil,
                hourlyRate: hourlyRate,
                runtime: Int(runtime),
                currentCost: 0,
                projectedDailyCost: 0
            )
            
            self.instanceNames[instanceId] = name ?? instanceId
            instance.updateCosts(
                current: 0,
                projected: 0
            )
            return instance
        }
    }
    
    private func getStateString(from stateCode: Int?) -> String {
        guard let code = stateCode else { return "unknown" }
        switch code {
        case 0: return "pending"
        case 16: return "running"
        case 32: return "shutting-down"
        case 48: return "terminated"
        case 64: return "stopping"
        case 80: return "stopped"
        default: return "unknown"
        }
    }
    
    private func getRuntimeKey(for date: Date, instanceId: String) -> String {
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
        return "runtime-\(instanceId)-\(dateString)"
    }
    
    private func getInstanceHourlyRate(type: String) -> Double {
        switch type {
        case "417", "t2.micro": return 0.0116
        case "418", "t2.small": return 0.023
        case "419", "t2.medium": return 0.0464
        case "420", "t2.large": return 0.0928
        case "421", "t3.micro": return 0.0104
        case "422", "t3.small": return 0.0208
        case "423", "t3.medium": return 0.0416
        default:
            print("⚠️ Unknown instance type: \(type), using default pricing")
            return 0.0116 // Default to t2.micro pricing
        }
    }
    
    func startInstances(_ instanceIds: [String]) async throws {
        let request = AWSEC2StartInstancesRequest()!
        request.instanceIds = instanceIds
        
        return try await withCheckedThrowingContinuation { continuation in
            ec2.startInstances(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func stopInstances(_ instanceIds: [String]) async throws {
        let request = AWSEC2StopInstancesRequest()!
        request.instanceIds = instanceIds
        
        return try await withCheckedThrowingContinuation { continuation in
            ec2.stopInstances(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func startInstance(_ instanceId: String) async throws {
        // Create start request
        let request = AWSEC2StartInstancesRequest()!
        request.instanceIds = [instanceId]
        
        // Remove any auto-stop countdown display but keep settings
        if let index = instances.firstIndex(where: { $0.id == instanceId }) {
            let updatedInstance = instances[index]
            let instance = EC2Instance(
                id: updatedInstance.id,
                instanceType: updatedInstance.instanceType,
                state: updatedInstance.state,
                name: updatedInstance.name,
                launchTime: updatedInstance.launchTime,
                publicIP: updatedInstance.publicIP,
                privateIP: updatedInstance.privateIP,
                autoStopEnabled: updatedInstance.autoStopEnabled,
                countdown: nil,
                stateTransitionTime: updatedInstance.stateTransitionTime,
                hourlyRate: updatedInstance.hourlyRate,
                runtime: updatedInstance.runtime,
                currentCost: updatedInstance.currentCost,
                projectedDailyCost: updatedInstance.projectedDailyCost
            )
            instances[index] = instance
        }
        
        // Post notification to cancel auto-stop timer
        NotificationCenter.default.post(
            name: Notification.Name("CancelAutoStop"),
            object: nil,
            userInfo: ["instanceId": instanceId]
        )
        
        // Send notification when instance is started
        if let instance = instances.first(where: { $0.id == instanceId }) {
            NotificationManager.shared.sendNotification(
                type: .instanceStarted(
                    instanceId: instanceId,
                    name: instance.name ?? instanceId
                )
            )
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            ec2.startInstances(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func stopInstance(_ instanceId: String, isAutoStop: Bool = false) async throws {
        HapticManager.notification(type: .success)
        
        // Cancel auto-stop timer if this is a manual stop
        if !isAutoStop {
            await cancelAutoStop(for: instanceId)
        }
        
        // Save runtime record before stopping
        if let instance = instances.first(where: { $0.id == instanceId }) {
            saveRuntimeRecord(for: instance, fromState: "running", toState: "stopped")
        }
        
        updateInstanceRuntime(instanceId)
        let request = AWSEC2StopInstancesRequest()!
        request.instanceIds = [instanceId]
        
        // Only send notification if it's a manual stop or if auto-stop warnings are enabled
        if !isAutoStop || NotificationSettingsViewModel.shared.autoStopWarningsEnabled {
            if let instance = instances.first(where: { $0.id == instanceId }) {
                NotificationManager.shared.sendNotification(
                    type: .instanceStopped(
                        instanceId: instanceId,
                        name: instance.name ?? instanceId
                    )
                )
            }
        }
        
        return try await withCheckedThrowingContinuation { [self] continuation in
            ec2.stopInstances(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func rebootInstance(_ instanceId: String) async throws {
        HapticManager.notification(type: .success)
        let request = AWSEC2RebootInstancesRequest()!
        request.instanceIds = [instanceId]
        
        return try await withCheckedThrowingContinuation { [self] continuation in
            ec2.rebootInstances(request) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func terminateInstance(_ instanceId: String) async throws {
        HapticManager.notification(type: .success)
        let request = AWSEC2TerminateInstancesRequest()!
        request.instanceIds = [instanceId]
        
        return try await withCheckedThrowingContinuation { [self] continuation in
            ec2.terminateInstances(request) { response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func validateCredentials() async throws {
        let request = AWSEC2DescribeRegionsRequest()!
        
        return try await withCheckedThrowingContinuation { [self] continuation in
            ec2.describeRegions(request) { response, error in
                if let error = error {
                    print("❌ Credential validation failed: \(error.localizedDescription)")
                    continuation.resume(throwing: AuthenticationError.invalidCredentials)
                } else {
                    print("✅ Credentials validated successfully")
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    @MainActor
    func getActivities(for instanceId: String) -> [InstanceActivity] {
        guard let data = UserDefaults.standard.data(forKey: "activities-\(instanceId)"),
              let activities = try? JSONDecoder().decode([InstanceActivity].self, from: data),
              let loginDate = loginDate else {
            return []
        }
        
        // Filter activities after login date
        return activities.filter { $0.timestamp >= loginDate }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    func updateInstanceRuntime(_ instanceId: String) {
        guard let instance = instances.first(where: { $0.id == instanceId }),
              let launchTime = instance.launchTime else { return }
        
        let now = Date()
        let runtime = now.timeIntervalSince(launchTime)
        let key = getRuntimeKey(for: now, instanceId: instanceId)
        
        // Store the runtime for this session
        UserDefaults.standard.set(runtime, forKey: key)
    }
    
    private func setupCostUpdateTimer() {
        costUpdateTimer?.invalidate()
        
        // Create a timer that fires every second
        DispatchQueue.main.async { [weak self] in
            self?.costUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.updateInstanceRuntimes()
                    self?.updateInstanceCosts()
                }
            }
        }
    }
    
    private func debouncedUpdateCosts() async {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= minimumUpdateInterval else { return }
        
        updateWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                try? await self?.updateCosts()
                self?.lastUpdateTime = Date()
            }
        }
        
        updateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
    
    private func updateCosts() async throws {
        // Batch updates to reduce UI updates
        let updatedInstances = instances
        
        for index in updatedInstances.indices where updatedInstances[index].state == .running {
            if let launchTime = updatedInstances[index].launchTime {
                let now = Date()
                let runtime = now.timeIntervalSince(launchTime)
                updatedInstances[index].runtime = Int(runtime / 3600)
            }
        }
        
        // Single UI update
        instances = updatedInstances
    }
    
    func cleanup() {
        DispatchQueue.main.async { [weak self] in
            self?.costUpdateTimer?.invalidate()
            self?.costUpdateTimer = nil
        }
    }
    
    func handleEnterBackground() {
        print("📱 App entering background")
        // Invalidate all timers but keep settings
        for (_, timer) in autoStopTimers {
            timer.invalidate()
        }
        autoStopTimers.removeAll()
        
        for (_, timer) in countdownTimers {
            timer.invalidate()
        }
        countdownTimers.removeAll()
        
        autoStopUpdateTimer?.invalidate()
        autoStopUpdateTimer = nil
    }
    
    func handleEnterForeground() {
        print("📱 App entering foreground")
        Task { @MainActor [weak self] in
            try? await self?.refreshInstances()
            await self?.restoreAutoStopTimers()
            self?.startAutoStopMonitoring()
        }
    }
    
    func refreshInstances() async throws {
        do {
            _ = try await fetchInstances()
            for index in instances.indices {
                if instances[index].state == .running {
                    let activities = getActivities(for: instances[index].id)
                    if let latestActivity = activities.first {
                        // Create a new instance with updated runtime
                        let updatedInstance = EC2Instance(
                            id: instances[index].id,
                            instanceType: instances[index].instanceType,
                            state: instances[index].state,
                            name: instances[index].name,
                            launchTime: instances[index].launchTime,
                            publicIP: instances[index].publicIP,
                            privateIP: instances[index].privateIP,
                            autoStopEnabled: instances[index].autoStopEnabled,
                            countdown: instances[index].countdown,
                            stateTransitionTime: instances[index].stateTransitionTime,
                            hourlyRate: instances[index].hourlyRate,
                            runtime: Int(latestActivity.runtime),
                            currentCost: latestActivity.cost ?? 0.0,
                            projectedDailyCost: instances[index].projectedDailyCost
                        )
                        instances[index] = updatedInstance
                    }
                }
            }
        } catch {
            print("❌ Failed to refresh instances: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func saveInstanceHistory(_ instance: EC2Instance, endTime: Date) {
        guard let launchTime = instance.launchTime,
              let loginDate = loginDate else { return }
        
        let runtime = endTime.timeIntervalSince(launchTime)
        let cost = (runtime / 3600.0) * instance.hourlyRate
        
        let history = InstanceHistory(
            instanceId: instance.id,
            startTime: launchTime,
            endTime: endTime,
            runtime: runtime,
            cost: cost,
            instanceType: instance.instanceType
        )
        
        var histories = getStoredHistories(for: instance.id)
        
        // Only keep history after login date
        histories = histories.filter { $0.startTime >= loginDate }
        histories.append(history)
        
        if let encoded = try? JSONEncoder().encode(histories) {
            UserDefaults.standard.set(encoded, forKey: "history-\(instance.id)")
        }
    }
    
    private func getStoredHistories(for instanceId: String) -> [InstanceHistory] {
        guard let data = UserDefaults.standard.data(forKey: "history-\(instanceId)"),
              let histories = try? JSONDecoder().decode([InstanceHistory].self, from: data) else {
            return []
        }
        return histories
    }
    
    func saveRuntimeRecord(for instance: EC2Instance, fromState: String, toState: String) {
        guard let loginDate = loginDate else { return }
        
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        
        // Calculate runtime and cost
        let runtime: Double
        let todayRuntime: Double
        
        if let launchTime = instance.launchTime {
            runtime = now.timeIntervalSince(launchTime)
            let startTime = max(launchTime, startOfToday)
            todayRuntime = now.timeIntervalSince(startTime)
        } else {
            runtime = 0
            todayRuntime = 0
        }
        
        // Calculate activity cost based on today's runtime
        let activityCost = (todayRuntime / 3600.0) * instance.hourlyRate
        
        let activity = InstanceActivity(
            id: UUID().uuidString,
            instanceId: instance.id,
            timestamp: now,
            runtime: runtime,
            state: InstanceState(rawValue: toState) ?? .unknown,
            type: .stateChange(from: fromState, to: toState)
        )
        
        // Save activity and update costs
        var activities = getActivities(for: instance.id)
        activities.append(activity)
        activities = activities.filter { $0.timestamp >= loginDate }
        
        if let encoded = try? JSONEncoder().encode(activities) {
            UserDefaults.standard.set(encoded, forKey: "activities-\(instance.id)")
        }
        
        // Update instance runtime and costs
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            let updatedInstance = EC2Instance(
                id: instance.id,
                instanceType: instance.instanceType,
                state: instance.state,
                name: instance.name,
                launchTime: instance.launchTime,
                publicIP: instance.publicIP,
                privateIP: instance.privateIP,
                autoStopEnabled: instance.autoStopEnabled,
                countdown: instance.countdown,
                stateTransitionTime: instance.stateTransitionTime,
                hourlyRate: instance.hourlyRate,
                runtime: Int(runtime),
                currentCost: activityCost,
                projectedDailyCost: instance.projectedDailyCost
            )
            
            updatedInstance.updateCosts(
                current: activityCost,
                projected: instance.projectedDailyCost
            )
            
            instances[index] = updatedInstance
        }
    }
    
    // Add this method to track state changes with runtime
    private func trackStateChange(instance: EC2Instance, from oldState: String, to newState: String) {
        if oldState != newState {
            saveRuntimeRecord(for: instance, fromState: oldState, toState: newState)
        }
    }
    
    private func calculateRuntime(for instance: EC2Instance) -> (runtime: Double, displayString: String) {
        let now = Date()
        var runtime: Double = 0
        
        if instance.state == .running, let launchTime = instance.launchTime {
            runtime = now.timeIntervalSince(launchTime)
        } else if let stateTransitionTime = instance.stateTransitionTime {
            runtime = now.timeIntervalSince(stateTransitionTime)
        }
        
        let hours = Int(floor(runtime / 3600))
        let minutes = Int(floor(runtime.truncatingRemainder(dividingBy: 3600) / 60))
        let displayString = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        
        return (runtime, displayString)
    }
    
    func calculateInstanceCosts(for instance: EC2Instance) -> (hourly: Double, current: Double, projected: Double) {
        let activities = getActivities(for: instance.id)
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        
        // Calculate current cost from today's activities
        let todayActivities = activities.filter { $0.timestamp >= startOfToday }
        let currentCost = todayActivities.reduce(0.0) { $0 + ($1.cost ?? 0.0) }
        
        // Project daily cost based on current state and hourly rate
        let projectedCost = instance.state == .running ? 
            instance.hourlyRate * 24 : currentCost
            
        return (instance.hourlyRate, currentCost, projectedCost)
    }
    
    // Add haptic feedback for errors
    private func handleError(_ error: Error, for instanceId: String) {
        if let instance = instances.first(where: { $0.id == instanceId }) {
            NotificationManager.shared.sendNotification(
                type: .instanceError(
                    message: "Error with instance '\(instance.name ?? instanceId)': \(error.localizedDescription)"
                )
            )
        }
    }
    
    func clearAllData() {
        print("🧹 Clearing all EC2Service data...")
        instances.forEach { instance in
            // Clear activities for each instance
            UserDefaults.standard.removeObject(forKey: "activities-\(instance.id)")
            UserDefaults.standard.removeObject(forKey: "history-\(instance.id)")
            UserDefaults.standard.removeObject(forKey: "runtime-\(instance.id)")
        }
        
        // Reset login date
        loginDate = nil
        instances = []
    }
    
    func calculateCosts(for instance: EC2Instance) -> (current: Double, projected: Double) {
        guard instance.state == .running else { return (0, 0) }
        
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        
        // Calculate today's runtime and cost
        let runtime: Double
        if let launchTime = instance.launchTime {
            let startTime = max(launchTime, startOfToday)
            runtime = now.timeIntervalSince(startTime)
        } else {
            runtime = 0
        }
        
        let currentCost = (runtime / 3600.0) * instance.hourlyRate
        
        // Calculate projected cost
        let hoursRemaining = calculateRemainingHours(from: now)
        let projectedAdditionalCost = instance.hourlyRate * hoursRemaining
        let projectedTotalCost = currentCost + projectedAdditionalCost
        
        return (currentCost, projectedTotalCost)
    }
    
    private func updateInstanceCosts() {
        // Update costs for all instances
        for (index, instance) in instances.enumerated() {
            let (current, projected) = calculateCosts(for: instance)
            let updatedInstance = EC2Instance(
                id: instance.id,
                instanceType: instance.instanceType,
                state: instance.state,
                name: instance.name,
                launchTime: instance.launchTime,
                publicIP: instance.publicIP,
                privateIP: instance.privateIP,
                autoStopEnabled: instance.autoStopEnabled,
                countdown: instance.countdown,
                stateTransitionTime: instance.stateTransitionTime,
                hourlyRate: instance.hourlyRate,
                runtime: instance.runtime,
                currentCost: current,
                projectedDailyCost: instance.projectedDailyCost
            )
            instances[index] = updatedInstance
        }
    }
    
    // Add this method to update instance runtimes
    private func updateInstanceRuntimes() {
        let updatedInstances = instances
        let now = Date()
        
        for index in updatedInstances.indices {
            if updatedInstances[index].state == .running,
               let launchTime = updatedInstances[index].launchTime {
                // Calculate runtime
                let runtime = now.timeIntervalSince(launchTime)
                updatedInstances[index].runtime = Int(runtime)
                
                // Calculate costs
                let hourlyRate = updatedInstances[index].hourlyRate
                let currentCost = (runtime / 3600.0) * hourlyRate
                let projectedCost = hourlyRate * 24.0
                
                updatedInstances[index].updateCosts(
                    current: currentCost,
                    projected: projectedCost
                )
            }
        }
        
        // Update the published instances array
        instances = updatedInstances
    }
    
    private func formatRuntime(_ runtime: TimeInterval) -> String {
        let hours = Int(floor(Double(runtime) / 3600))
        let minutes = Int(floor(Double(runtime).truncatingRemainder(dividingBy: 3600) / 60))
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    private func calculateRemainingHours(from now: Date) -> Double {
        let calendar = Calendar.current
        let hour = Double(calendar.component(.hour, from: now))
        let minute = Double(calendar.component(.minute, from: now))
        return 24.0 - hour - (minute / 60.0)
    }
    
    @MainActor
    func toggleAutoStop(for instanceId: String, isEnabled: Bool) async throws {
        print("\n🔄 Toggling auto-stop for instance \(instanceId) to \(isEnabled)")
        
        guard let index = instances.firstIndex(where: { $0.id == instanceId }) else { return }
        
        // Create a local copy of the instance
        let updatedInstance = instances[index]
        
        // Update instance state
        let instance = EC2Instance(
            id: updatedInstance.id,
            instanceType: updatedInstance.instanceType,
            state: updatedInstance.state,
            name: updatedInstance.name,
            launchTime: updatedInstance.launchTime,
            publicIP: updatedInstance.publicIP,
            privateIP: updatedInstance.privateIP,
            autoStopEnabled: isEnabled,
            countdown: updatedInstance.countdown,
            stateTransitionTime: updatedInstance.stateTransitionTime,
            hourlyRate: updatedInstance.hourlyRate,
            runtime: updatedInstance.runtime,
            currentCost: updatedInstance.currentCost,
            projectedDailyCost: updatedInstance.projectedDailyCost
        )
        
        if isEnabled {
            // When enabling, start fresh with no time set and clear any existing settings
            instance.countdown = "Set time"
            AutoStopSettingsService.shared.saveSettings(
                for: instance.id,
                enabled: true,
                time: nil
            )
            // Remove any existing auto-stop config
            autoStopConfigs.removeValue(forKey: instance.id)
        } else {
            // When disabling, clean up everything
            await clearNotifications(for: instance.id)
            autoStopConfigs.removeValue(forKey: instance.id)
            AutoStopSettingsService.shared.clearSettings(for: instance.id)
            await endLiveActivity(for: instance.id)
            instance.countdown = nil
        }
        
        // Update the instance in the array with animation
        withAnimation {
            instances[index] = instance
        }
        
        // Force a UI update
        objectWillChange.send()
        
        print("📊 Final auto-stop state for instance \(instanceId):")
        print("  • Instance state:")
        print("    - Auto-stop enabled: \(instance.autoStopEnabled)")
        print("    - Countdown: \(instance.countdown ?? "nil")")
        print("    - Config exists: \(autoStopConfigs[instance.id] != nil)")
        
        if let settings = AutoStopSettingsService.shared.getSettings(for: instance.id) {
            print("  • Settings state:")
            print("    - Enabled: \(settings.isEnabled)")
            print("    - Stop time: \(String(describing: settings.stopTime))")
        }
    }
    
    private func endLiveActivity(for instanceId: String) async {
        // No-op - Live Activities removed
    }
    
    private func updateLiveActivities() {
        // No-op - Live Activities removed
    }
    
    // Update cancelAutoStop to remove Live Activities
    func cancelAutoStop(for instanceId: String) async {
        guard let index = instances.firstIndex(where: { $0.id == instanceId }) else { return }
        
        // Clear notifications
        await clearNotifications(for: instanceId)
        
        // Update the instance
        let updatedInstance = instances[index]
        let instance = EC2Instance(
            id: updatedInstance.id,
            instanceType: updatedInstance.instanceType,
            state: updatedInstance.state,
            name: updatedInstance.name,
            launchTime: updatedInstance.launchTime,
            publicIP: updatedInstance.publicIP,
            privateIP: updatedInstance.privateIP,
            autoStopEnabled: updatedInstance.autoStopEnabled,
            countdown: nil,
            stateTransitionTime: updatedInstance.stateTransitionTime,
            hourlyRate: updatedInstance.hourlyRate,
            runtime: updatedInstance.runtime,
            currentCost: updatedInstance.currentCost,
            projectedDailyCost: updatedInstance.projectedDailyCost
        )
        
        // Remove from autoStopConfigs
        autoStopConfigs.removeValue(forKey: instance.id)
        
        // Update the instance in the array
        instances[index] = instance
        
        print("Auto-stop cancelled for instance \(instanceId)")
    }
    
    // Update scheduleWarningNotifications to use more frequent intervals
    private func scheduleWarningNotifications(for instanceId: String, stopTime: Date) async {
        print("\n📅 Scheduling notifications for instance \(instanceId):")
        print("  • Stop time: \(stopTime)")
        
        // Check notification settings using shared instance
        let notificationSettings = NotificationSettingsViewModel.shared
        guard notificationSettings.autoStopWarningsEnabled else {
            print("  ℹ️ Auto-stop warnings are disabled in settings")
            // Clear any existing notifications since warnings are disabled
            await clearNotifications(for: instanceId)
            return
        }
        
        // Use more intervals: 2 hours, 1 hour, 30 mins, 15 mins, 10 mins, 5 mins, 2 mins, 1 min
        let intervals = [7200, 3600, 1800, 900, 600, 300, 120, 60]
        print("  • Warning intervals: \(intervals.map { formatInterval($0) })")
        
        // First, clear any existing notifications
        await clearNotifications(for: instanceId)
        
        let timeInterval = stopTime.timeIntervalSinceNow
        
        // Schedule warning notifications if countdown updates are enabled
        if notificationSettings.autoStopCountdownEnabled {
            for interval in intervals where timeInterval > Double(interval) {
                let warningTime = stopTime.addingTimeInterval(-Double(interval))
                
                if warningTime > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = "⏰ Auto-Stop Warning"
                    if let instance = instances.first(where: { $0.id == instanceId }) {
                        content.body = "Instance '\(instance.name ?? instanceId)' will stop in \(formatInterval(interval))"
                    }
                    content.sound = .default
                    content.interruptionLevel = .timeSensitive
                    
                    let trigger = UNTimeIntervalNotificationTrigger(
                        timeInterval: warningTime.timeIntervalSinceNow,
                        repeats: false
                    )
                    
                    let request = UNNotificationRequest(
                        identifier: "\(instanceId)-warning-\(interval)",
                        content: content,
                        trigger: trigger
                    )
                    
                    do {
                        try await UNUserNotificationCenter.current().add(request)
                        print("  ✅ Warning scheduled for \(formatInterval(interval)) before stop")
                    } catch {
                        print("  ❌ Failed to schedule warning: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            print("  ℹ️ Countdown updates are disabled in settings")
        }
        
        // Schedule the final notification
        let finalContent = UNMutableNotificationContent()
        finalContent.title = "🛑 Instance Auto-Stopped"
        if let instance = instances.first(where: { $0.id == instanceId }) {
            finalContent.body = "Instance '\(instance.name ?? instanceId)' has been automatically stopped"
        }
        finalContent.sound = .default
        finalContent.interruptionLevel = .timeSensitive
        
        let finalTrigger = UNTimeIntervalNotificationTrigger(
            timeInterval: timeInterval,
            repeats: false
        )
        
        let finalRequest = UNNotificationRequest(
            identifier: "\(instanceId)-autostop",
            content: finalContent,
            trigger: finalTrigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(finalRequest)
            print("  ✅ Final notification scheduled")
        } catch {
            print("  ❌ Failed to schedule final notification: \(error.localizedDescription)")
        }
    }
    
    private func formatInterval(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let remainingMinutes = (seconds % 3600) / 60
            if remainingMinutes > 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s") and \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds > 0 {
                return "\(minutes) minute\(minutes == 1 ? "" : "s") and \(remainingSeconds) second\(remainingSeconds == 1 ? "" : "s")"
            }
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
    }
    
    // Add this method to verify auto-stop configuration
    func verifyAutoStopConfig(for instanceId: String) {
        print("\n🔍 Verifying auto-stop config for instance \(instanceId)")
        
        if let config = autoStopConfigs[instanceId] {
            print("  • Found config:")
            print("    - Stop time: \(config.stopTime)")
            print("    - Time remaining: \(Int(config.stopTime.timeIntervalSinceNow)) seconds")
        } else {
            print("  ❌ No config found")
        }
        
        if let instance = instances.first(where: { $0.id == instanceId }) {
            print("  • Instance state:")
            print("    - Auto-stop enabled: \(instance.autoStopEnabled)")
            print("    - Countdown: \(instance.countdown ?? "Not set")")
        } else {
            print("  ❌ Instance not found")
        }
    }
    
    // Add this method to debug auto-stop configurations
    private func debugAutoStopState() {
        print("\n🔍 Current Auto-Stop State:")
        print("  • Number of configs: \(autoStopConfigs.count)")
        print("  • Configs: \(autoStopConfigs)")
        
        for (instanceId, config) in autoStopConfigs {
            print("\n  Instance: \(instanceId)")
            print("    • Stop time: \(config.stopTime)")
            print("    • Time remaining: \(Int(config.stopTime.timeIntervalSinceNow)) seconds")
            
            if let instance = instances.first(where: { $0.id == instanceId }) {
                print("    • Instance state: \(instance.state.rawValue)")
                print("    • Auto-stop enabled: \(instance.autoStopEnabled)")
                print("    • Countdown: \(instance.countdown ?? "Not set")")
            } else {
                print("    ❌ Instance not found")
            }
        }
    }
    
    // Add stopAutoStopMonitoring function
    private func stopAutoStopMonitoring() {
        print("\n🛑 Stopping auto-stop monitoring")
        
        // Invalidate and clear all timers
        autoStopUpdateTimer?.invalidate()
        autoStopUpdateTimer = nil
        
        for (_, timer) in autoStopTimers {
            timer.invalidate()
        }
        autoStopTimers.removeAll()
        
        for (_, timer) in countdownTimers {
            timer.invalidate()
        }
        countdownTimers.removeAll()
        
        print("  ✅ Auto-stop monitoring stopped")
    }
    
    // Update clearNotifications to handle all intervals
    private func clearNotifications(for instanceId: String) async {
        let intervals = [7200, 3600, 1800, 900, 600, 300, 120, 60]
        var notificationIds = ["\(instanceId)-autostop"]
        
        // Add all warning notification IDs
        notificationIds.append(contentsOf: intervals.map { "\(instanceId)-warning-\($0)" })
        
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: notificationIds)
        center.removeDeliveredNotifications(withIdentifiers: notificationIds)
        
        print("  ✅ Cleared all notifications for instance \(instanceId)")
    }
    
    // Update checkAutoStopConfigurations to be async
    private func checkAutoStopConfigurations() async {
        print("\n⏰ Checking auto-stop configurations...")
        
        // Load configurations from settings if autoStopConfigs is empty
        if autoStopConfigs.isEmpty {
            for instance in instances {
                // Only load configs for running instances
                if instance.state == .running,
                   let settings = AutoStopSettingsService.shared.getSettings(for: instance.id),
                   settings.isEnabled,
                   let stopTime = settings.stopTime {
                    autoStopConfigs[instance.id] = AutoStopConfig(instanceId: instance.id, stopTime: stopTime)
                    print("  • Loaded config for \(instance.id): stop at \(stopTime)")
                }
            }
        }
        
        // Create a copy to avoid modifying while iterating
        let configsToCheck = autoStopConfigs
        
        // Check each configuration
        for (instanceId, config) in configsToCheck {
            // Skip if instance is not running
            guard let instance = instances.first(where: { $0.id == instanceId }),
                  instance.state == .running else {
                // Remove config if instance is not running
                autoStopConfigs.removeValue(forKey: instanceId)
                continue
            }
            
            let timeRemaining = config.stopTime.timeIntervalSinceNow
            print("  • Instance \(instanceId): \(Int(timeRemaining))s remaining")
            
            if timeRemaining <= 0 {
                do {
                    print("  • Stop time reached for \(instanceId)")
                    // Remove config before stopping to prevent repeated attempts
                    autoStopConfigs.removeValue(forKey: instanceId)
                    
                    // Clear settings after successful stop
                    AutoStopSettingsService.shared.clearSettings(for: instanceId)
                    
                    // Stop the instance
                    try await stopInstance(instanceId, isAutoStop: true)
                } catch {
                    print("  ❌ Failed to stop instance: \(error.localizedDescription)")
                }
            }
        }
        
        // Stop monitoring if no configs are active
        if autoStopConfigs.isEmpty {
            stopAutoStopMonitoring()
        }
    }
    
    // Add startAutoStopMonitoring function
    private func startAutoStopMonitoring() {
        print("\n🔄 Starting auto-stop monitoring")
        
        // Invalidate existing timer
        autoStopUpdateTimer?.invalidate()
        autoStopUpdateTimer = nil
        
        // Create new timer that runs every second to update countdowns
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                print("\n🔄 Auto-stop monitoring tick")
                print("  • Active configs: \(self.autoStopConfigs.count)")
                
                // Update countdowns for all active configs
                for (instanceId, config) in self.autoStopConfigs {
                    await self.updateCountdown(for: instanceId, stopTime: config.stopTime)
                }
                
                // Check configurations every 5 seconds
                if Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 5) < 1 {
                    await self.checkAutoStopConfigurations()
                }
            }
        }
        
        // Make sure timer stays valid by adding it to the main run loop
        RunLoop.main.add(timer, forMode: .common)
        autoStopUpdateTimer = timer
        
        // Force an immediate check
        Task { @MainActor [weak self] in
            await self?.checkAutoStopConfigurations()
        }
        
        print("\n📊 Monitoring summary:")
        print("  • Timer scheduled and started")
        print("  • Current configs: \(autoStopConfigs)")
    }
    
    // Add restoreAutoStopTimers function
    func restoreAutoStopTimers() async {
        print("\n🔄 Restoring auto-stop timers")
        
        // First, stop monitoring and clear all existing timers
        stopAutoStopMonitoring()
        
        // Clear all existing timers and configs
        autoStopTimers.removeAll()
        countdownTimers.removeAll()
        autoStopConfigs.removeAll()
        
        // Get all settings first
        let allSettings = AutoStopSettingsService.shared.getAllSettings()
        print("📊 Current settings:")
        print("  • Number of settings: \(allSettings.count)")
        
        // Restore configurations from settings and update instance states
        for (index, instance) in instances.enumerated() {
            if let settings = allSettings[instance.id] {
                print("\n🔍 Restoring settings for instance \(instance.id)")
                print("  • Found settings: \(settings)")
                
                let updatedInstance = EC2Instance(
                    id: instance.id,
                    instanceType: instance.instanceType,
                    state: instance.state,
                    name: instance.name,
                    launchTime: instance.launchTime,
                    publicIP: instance.publicIP,
                    privateIP: instance.privateIP,
                    autoStopEnabled: settings.isEnabled,
                    countdown: settings.stopTime != nil ? DateFormatter.localizedString(from: settings.stopTime!, dateStyle: .none, timeStyle: .short) : (settings.isEnabled ? "Set time" : nil),
                    stateTransitionTime: instance.stateTransitionTime,
                    hourlyRate: instance.hourlyRate,
                    runtime: instance.runtime,
                    currentCost: instance.currentCost,
                    projectedDailyCost: instance.projectedDailyCost
                )
                
                // Update instance in array with animation
                withAnimation {
                    instances[index] = updatedInstance
                }
            }
        }
        
        // Start monitoring if we have any configurations
        if !autoStopConfigs.isEmpty {
            startAutoStopMonitoring()
        }
        
        // Force a UI update
        objectWillChange.send()
        
        print("\n📊 Restore summary:")
        print("  • Restored configs count: \(autoStopConfigs.count)")
        print("  • Current configs: \(autoStopConfigs)")
        print("  ✅ Auto-stop timers restored")
    }
    
    @MainActor
    private func updateCountdown(for instanceId: String, stopTime: Date) async {
        print("\n⏱️ Updating countdown for instance \(instanceId)")
        guard let index = instances.firstIndex(where: { $0.id == instanceId }) else {
            print("  ❌ Instance not found")
            return
        }
        
        let timeRemaining = stopTime.timeIntervalSince(Date())
        print("  • Time remaining: \(timeRemaining) seconds")
        
        let updatedInstance = instances[index]
        
        if timeRemaining <= 0 {
            print("  • Time has elapsed, stopping instance")
            do {
                await cancelAutoStop(for: instanceId)
                try await stopInstance(instanceId, isAutoStop: true)
            } catch {
                print("  ❌ Failed to stop instance: \(error.localizedDescription)")
            }
        } else {
            // Format and display the actual stop time
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let stopTimeDisplay = formatter.string(from: stopTime)
            
            // Only update if the display has changed
            if updatedInstance.countdown != stopTimeDisplay {
                print("  • Updating stop time display to: \(stopTimeDisplay)")
                let instance = EC2Instance(
                    id: updatedInstance.id,
                    instanceType: updatedInstance.instanceType,
                    state: updatedInstance.state,
                    name: updatedInstance.name,
                    launchTime: updatedInstance.launchTime,
                    publicIP: updatedInstance.publicIP,
                    privateIP: updatedInstance.privateIP,
                    autoStopEnabled: updatedInstance.autoStopEnabled,
                    countdown: stopTimeDisplay,
                    stateTransitionTime: updatedInstance.stateTransitionTime,
                    hourlyRate: updatedInstance.hourlyRate,
                    runtime: updatedInstance.runtime,
                    currentCost: updatedInstance.currentCost,
                    projectedDailyCost: updatedInstance.projectedDailyCost
                )
                instances[index] = instance
            }
        }
    }
    
    func setupAutoStop(for instanceId: String, at stopTime: Date) async throws {
        print("\n⏰ Setting up auto-stop for instance \(instanceId) at \(stopTime)")
        
        guard let index = instances.firstIndex(where: { $0.id == instanceId }) else {
            print("  ❌ Instance not found")
            return
        }
        
        // Create and store the auto-stop configuration
        autoStopConfigs[instanceId] = AutoStopConfig(instanceId: instanceId, stopTime: stopTime)
        
        // Save settings
        AutoStopSettingsService.shared.saveSettings(
            for: instanceId,
            enabled: true,
            time: stopTime
        )
        
        // Schedule notifications
        await scheduleWarningNotifications(for: instanceId, stopTime: stopTime)
        
        // Update instance display
        let updatedInstance = instances[index]
        let instance = EC2Instance(
            id: updatedInstance.id,
            instanceType: updatedInstance.instanceType,
            state: updatedInstance.state,
            name: updatedInstance.name,
            launchTime: updatedInstance.launchTime,
            publicIP: updatedInstance.publicIP,
            privateIP: updatedInstance.privateIP,
            autoStopEnabled: true,
            countdown: DateFormatter.localizedString(from: stopTime, dateStyle: .none, timeStyle: .short),
            stateTransitionTime: updatedInstance.stateTransitionTime,
            hourlyRate: updatedInstance.hourlyRate,
            runtime: updatedInstance.runtime,
            currentCost: updatedInstance.currentCost,
            projectedDailyCost: updatedInstance.projectedDailyCost
        )
        
        // Update the instance in the array
        instances[index] = instance
        
        // Start monitoring if not already running
        startAutoStopMonitoring()
        
        print("✅ Auto-stop setup complete")
    }
}

// Add this computed property to EC2Instance
extension EC2Instance {
    var formattedRuntime: String {
        let hours = Int(floor(Double(runtime) / 3600))
        let minutes = Int(floor(Double(runtime).truncatingRemainder(dividingBy: 3600) / 60))
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}