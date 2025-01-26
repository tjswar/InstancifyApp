import Foundation
import SwiftUI

@MainActor
class NotificationSettingsViewModel: ObservableObject {
    static let shared = NotificationSettingsViewModel()
    
    @AppStorage("runtimeAlertsEnabled") var runtimeAlertsEnabled = false
    @AppStorage("warningsEnabled") private var warningsEnabled = true
    @AppStorage("countdownEnabled") private var countdownEnabled = true
    @Published private(set) var warningIntervals: [Int] = []
    @Published var runtimeAlerts: [RuntimeAlert] = []
    
    var autoStopWarningsEnabled: Bool {
        get { warningsEnabled }
        set { warningsEnabled = newValue }
    }
    
    var autoStopCountdownEnabled: Bool {
        get { countdownEnabled }
        set { countdownEnabled = newValue }
    }
    
    var selectedWarningIntervals: Set<Int> {
        get { Set(warningIntervals) }
        set { 
            warningIntervals = Array(newValue).sorted(by: >)
            saveWarningIntervals()
        }
    }
    
    let availableWarningIntervals: [(Int, String)] = [
        (7200, "2 hours"),
        (3600, "1 hour"),
        (1800, "30 minutes"),
        (900, "15 minutes"),
        (600, "10 minutes"),
        (300, "5 minutes"),
        (120, "2 minutes"),
        (60, "1 minute")
    ]
    
    private init() {
        loadWarningIntervals()
        loadAlerts()
    }
    
    func addNewAlert() {
        let newAlert = RuntimeAlert(
            id: UUID().uuidString,
            enabled: true,
            hours: 2,
            minutes: 0
        )
        runtimeAlerts.append(newAlert)
        saveAlerts()
    }
    
    func deleteAlert(at offsets: IndexSet) {
        guard !runtimeAlerts.isEmpty else { return }
        runtimeAlerts.remove(atOffsets: offsets)
        saveAlerts()
    }
    
    func updateAlert(id: String, enabled: Bool? = nil, hours: Int? = nil, minutes: Int? = nil) {
        guard let index = runtimeAlerts.firstIndex(where: { $0.id == id }) else { return }
        var alert = runtimeAlerts[index]
        
        if let enabled = enabled {
            alert.enabled = enabled
        }
        if let hours = hours {
            alert.hours = hours
        }
        if let minutes = minutes {
            alert.minutes = minutes
        }
        
        runtimeAlerts[index] = alert
        saveAlerts()
    }
    
    func toggleWarningInterval(_ interval: Int) {
        if selectedWarningIntervals.contains(interval) {
            selectedWarningIntervals.remove(interval)
        } else {
            selectedWarningIntervals.insert(interval)
        }
    }
    
    private func loadWarningIntervals() {
        if let data = UserDefaults.standard.array(forKey: "warningIntervals") as? [Int] {
            warningIntervals = data
        } else {
            // Set default intervals if none exist
            warningIntervals = [3600, 1800, 900, 300, 120, 60] // 1h, 30m, 15m, 5m, 2m, 1m
            saveWarningIntervals()
        }
    }
    
    private func saveWarningIntervals() {
        UserDefaults.standard.set(warningIntervals, forKey: "warningIntervals")
    }
    
    private func loadAlerts() {
        if let data = UserDefaults.standard.data(forKey: "runtimeAlerts"),
           let alerts = try? JSONDecoder().decode([RuntimeAlert].self, from: data) {
            runtimeAlerts = alerts
        } else {
            // Set a default alert if none exist
            runtimeAlerts = [
                RuntimeAlert(id: UUID().uuidString, enabled: true, hours: 2, minutes: 0)
            ]
            saveAlerts()
        }
    }
    
    private func saveAlerts() {
        if let encoded = try? JSONEncoder().encode(runtimeAlerts) {
            UserDefaults.standard.set(encoded, forKey: "runtimeAlerts")
        }
    }
} 