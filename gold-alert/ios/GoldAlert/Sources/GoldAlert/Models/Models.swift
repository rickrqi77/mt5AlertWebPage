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

    /// 列表行身份：只能用稳定的 localID（ForEach 与 .id 都用它），
    /// 绝不能把价格/状态拼进去，更不能叠加 .id(行号) 按位置认行。
    /// 价格是可编辑内容：拼进身份的话，用户在输入框打一个数字、
    /// priceText 一变身份就变，SwiftUI 会把整行当新行销毁重建，
    /// 正在编辑的 UITextField 随之被销毁、键盘立刻消失
    /// （ren 2026-10-30 实报：点价格输入框打一个数字键盘就没了）。
    /// 防新旧混合不靠内容身份：价格已无行内草稿、直接绑定模型值；
    /// 重新生成网格时每行都是新 localID，云端刷新也只在价格对上时
    /// 才继承旧 localID（见 refreshCloudState），身份不同不复用旧行。
    var rowKey: String { localID.uuidString }
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
