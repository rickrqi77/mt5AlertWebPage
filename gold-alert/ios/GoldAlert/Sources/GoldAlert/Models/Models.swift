import Foundation

struct Quote: Equatable, Sendable {
    var symbol: String
    var bid: Double
    var ask: Double
    var price: Double
    var source: String

    static let empty = Quote(symbol: "XAUUSD", bid: 0, ask: 0, price: 0, source: "")

    var isValid: Bool { price > 0 && bid > 0 && ask > 0 }
}

struct AlertItem: Identifiable, Equatable, Hashable, Sendable, Codable {
    var id: Int?
    /// Stable identity for SwiftUI lists when server id is missing.
    var localID: UUID = UUID()
    var priceText: String
    var enabled: Bool
    var triggered: Bool

    var priceValue: Double? {
        Double(priceText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 列表行身份：价格或状态一变就视为新行。只用 localID 时，整表替换后
    /// LazyVStack 可能复用旧行视图，行内 @State 草稿（显示的价格文本）残留
    /// 上一份设定的值，画面会拼出新旧混合的列表（实测截图里的「中间段不对」）。
    var rowKey: String { "\(localID.uuidString)|\(priceText)|\(enabled)|\(triggered)" }
}

struct StatusPayload: Decodable, Sendable {
    var symbol: String?
    var price: Double?
    var bid: Double?
    var ask: Double?
    var ea_online: Bool?
    var step: Double?
    var alerts_enabled: Bool?
    var paused: Bool?
    var sync_seconds: Int?
    var alerts: [AlertDTO]?
    var config_version: Int?
}

struct AlertsPayload: Decodable, Sendable {
    var alerts: [AlertDTO]
    var max: Int?
}

struct AlertDTO: Decodable, Sendable {
    var id: Int?
    var price: Double
    var enabled: BoolOrInt?
    var triggered: BoolOrInt?

    func asItem() -> AlertItem {
        AlertItem(
            id: id,
            priceText: Self.format(price),
            enabled: enabled?.boolValue ?? true,
            triggered: triggered?.boolValue ?? false
        )
    }

    private static func format(_ value: Double) -> String {
        if abs(value - (value * 100).rounded() / 100) < 1e-9 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }
}

struct SettingsPayload: Decodable, Sendable {
    var step: Double?
    var alerts_enabled: Bool?
    var paused: Bool?
}

struct SaveAlertsResponse: Decodable, Sendable {
    var alerts: [AlertDTO]?
    var message: String?
    var error: String?
}

struct AutoAlertsResponse: Decodable, Sendable {
    var alerts: [AlertDTO]?
    var message: String?
    var step: Double?
    var error: String?
}

struct PauseResponse: Decodable, Sendable {
    var paused: Bool?
    var message: String?
    var error: String?
}

/// Accepts JSON booleans or 0/1 integers from D1.
enum BoolOrInt: Decodable, Sendable {
    case bool(Bool)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else {
            self = .bool(false)
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        }
    }
}

enum AppError: LocalizedError, Sendable {
    case message(String)
    case unauthorized
    case badResponse

    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .unauthorized: return "Token 无效"
        case .badResponse: return "服务器返回异常"
        }
    }
}
