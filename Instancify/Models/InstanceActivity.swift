import Foundation

struct InstanceActivity: Identifiable, Equatable, Codable {
    let id: String
    let instanceId: String
    let timestamp: Date
    let runtime: TimeInterval
    let state: InstanceState
    let type: ActivityType
    
    init(
        id: String = UUID().uuidString,
        instanceId: String,
        timestamp: Date,
        runtime: TimeInterval,
        state: InstanceState,
        type: ActivityType
    ) {
        self.id = id
        self.instanceId = instanceId
        self.timestamp = timestamp
        self.runtime = runtime
        self.state = state
        self.type = type
    }
    
    var duration: TimeInterval? {
        runtime
    }
    
    var cost: Double? {
        nil
    }
    
    var runtimeHours: Double {
        runtime / 3600
    }
    
    var dayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: timestamp)
    }
    
    enum ActivityType: Equatable, Codable {
        case stateChange(from: String, to: String)
        case userAction(String)
        
        // Add coding keys for Codable conformance
        private enum CodingKeys: String, CodingKey {
            case type, fromState, toState, action
        }
        
        enum ActivityTypeEnum: String, Codable {
            case stateChange, userAction
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .stateChange(let from, let to):
                try container.encode(ActivityTypeEnum.stateChange, forKey: .type)
                try container.encode(from, forKey: .fromState)
                try container.encode(to, forKey: .toState)
            case .userAction(let action):
                try container.encode(ActivityTypeEnum.userAction, forKey: .type)
                try container.encode(action, forKey: .action)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(ActivityTypeEnum.self, forKey: .type)
            switch type {
            case .stateChange:
                let from = try container.decode(String.self, forKey: .fromState)
                let to = try container.decode(String.self, forKey: .toState)
                self = .stateChange(from: from, to: to)
            case .userAction:
                let action = try container.decode(String.self, forKey: .action)
                self = .userAction(action)
            }
        }
    }
} 