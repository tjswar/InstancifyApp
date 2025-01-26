import Foundation

struct WidgetData: Codable {
    let instanceId: String
    let instanceName: String
    let state: String
    let currentCost: Double
    let projectedDailyCost: Double
    let lastUpdated: Date
    
    static func save(_ data: WidgetData, for instanceId: String) {
        let sharedDefaults = UserDefaults(suiteName: "group.tech.medilook.Instancify")
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(data) {
            sharedDefaults?.set(encoded, forKey: "widget-data-\(instanceId)")
        }
    }
    
    static func load(for instanceId: String) -> WidgetData? {
        let sharedDefaults = UserDefaults(suiteName: "group.tech.medilook.Instancify")
        if let data = sharedDefaults?.data(forKey: "widget-data-\(instanceId)") {
            let decoder = JSONDecoder()
            return try? decoder.decode(WidgetData.self, from: data)
        }
        return nil
    }
    
    static func clearData(for instanceId: String) {
        let sharedDefaults = UserDefaults(suiteName: "group.tech.medilook.Instancify")
        sharedDefaults?.removeObject(forKey: "widget-data-\(instanceId)")
    }
} 