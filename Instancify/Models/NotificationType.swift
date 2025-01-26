import Foundation
import SwiftUI

enum NotificationType: Identifiable {
    case instanceStarted(instanceId: String, name: String)
    case instanceStopped(instanceId: String, name: String)
    case instanceError(message: String)
    case autoStopEnabled(instanceId: String, name: String, stopTime: Date)
    case autoStopWarning(instanceId: String, name: String, secondsRemaining: Int)
    case instanceAutoStopped(instanceId: String, name: String)
    case instanceStateChanged(instanceId: String, name: String, from: String, to: String)
    case instanceRunningLong(instanceId: String, name: String, runtime: TimeInterval, cost: Double?)
    
    var id: String {
        switch self {
        case .instanceStarted(let instanceId, _): return "start-\(instanceId)"
        case .instanceStopped(let instanceId, _): return "stop-\(instanceId)"
        case .instanceError: return "error-\(UUID().uuidString)"
        case .autoStopEnabled(let instanceId, _, _): return "enabled-\(instanceId)"
        case .autoStopWarning(let instanceId, _, _): return "warning-\(instanceId)"
        case .instanceAutoStopped(let instanceId, _): return "autostop-\(instanceId)"
        case .instanceStateChanged(let instanceId, _, _, _): return "state-\(instanceId)"
        case .instanceRunningLong(let instanceId, _, _, _): return "runtime-\(instanceId)"
        }
    }
    
    var instanceId: String? {
        switch self {
        case .instanceStarted(let instanceId, _),
             .instanceStopped(let instanceId, _),
             .autoStopEnabled(let instanceId, _, _),
             .autoStopWarning(let instanceId, _, _),
             .instanceAutoStopped(let instanceId, _),
             .instanceStateChanged(let instanceId, _, _, _),
             .instanceRunningLong(let instanceId, _, _, _):
            return instanceId
        case .instanceError:
            return nil
        }
    }
    
    var title: String {
        switch self {
        case .instanceStarted: return "Instance Started"
        case .instanceStopped: return "Instance Stopped"
        case .instanceError: return "Error"
        case .autoStopEnabled: return "Auto-Stop Scheduled"
        case .autoStopWarning: return "Auto-Stop Warning"
        case .instanceAutoStopped: return "Auto-Stop Complete"
        case .instanceStateChanged: return "Instance State Changed"
        case .instanceRunningLong: return "⚠️ Long Running Instance"
        }
    }
    
    var body: String {
        switch self {
        case .instanceStarted(_, let name):
            return "Instance '\(name)' has been started"
        case .instanceStopped(_, let name):
            return "Instance '\(name)' has been stopped"
        case .instanceError(let message):
            return message
        case .autoStopEnabled(_, let name, let stopTime):
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Instance '\(name)' will be stopped at \(formatter.string(from: stopTime))"
        case .autoStopWarning(_, let name, let seconds):
            return "Instance '\(name)' will be stopped in \(seconds) seconds"
        case .instanceAutoStopped(_, let name):
            return "Instance '\(name)' has been automatically stopped"
        case .instanceStateChanged(_, let name, let from, let to):
            return "Instance '\(name)' state changed from \(from) to \(to)"
        case .instanceRunningLong(_, let name, let runtime, let cost):
            let hours = Int(runtime) / 3600
            let minutes = Int(runtime) / 60 % 60
            if let cost = cost {
                return "Instance '\(name)' has been running for \(hours)h \(minutes)m (Cost: $\(String(format: "%.2f", cost)))"
            } else {
                return "Instance '\(name)' has been running for \(hours)h \(minutes)m"
            }
        }
    }
} 