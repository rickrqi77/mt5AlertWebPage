import Foundation

/// Lightweight local cache so the alerts list and header render instantly on open,
/// then `refreshCloudState()` updates them from Cloudflare in the background.
enum LocalCache {
    private static let alertsKey = "cached_alerts_v1"
    private static let stepKey = "cached_step_v1"
    private static let pausedKey = "cached_paused_v1"
    private static let onlineKey = "cached_online_v1"

    static func loadAlerts() -> [AlertItem]? {
        guard let data = UserDefaults.standard.data(forKey: alertsKey) else { return nil }
        return try? JSONDecoder().decode([AlertItem].self, from: data)
    }

    static func saveAlerts(_ alerts: [AlertItem]) {
        if let data = try? JSONEncoder().encode(alerts) {
            UserDefaults.standard.set(data, forKey: alertsKey)
        }
    }

    static func loadStep() -> Double? {
        UserDefaults.standard.object(forKey: stepKey) as? Double
    }

    static func saveStep(_ value: Double) {
        UserDefaults.standard.set(value, forKey: stepKey)
    }

    static func loadPaused() -> Bool? {
        UserDefaults.standard.object(forKey: pausedKey) as? Bool
    }

    static func savePaused(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: pausedKey)
    }

    static func loadOnline() -> Bool? {
        UserDefaults.standard.object(forKey: onlineKey) as? Bool
    }

    static func saveOnline(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: onlineKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: alertsKey)
        UserDefaults.standard.removeObject(forKey: stepKey)
        UserDefaults.standard.removeObject(forKey: pausedKey)
        UserDefaults.standard.removeObject(forKey: onlineKey)
    }
}
