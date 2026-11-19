import Foundation
import Security

enum WatchPriceError: LocalizedError, Sendable {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        }
    }
}

/// 手表端取价：按 ren 2026-11-15 定，表上价格固定 Swiss——直接取 Swissquote
/// 公共报价 XAU/USD 中间价（与 iOS 端 Swiss 来源同一接口、同一取价口径：
/// prime 档优先、中间价保留三位小数）。不需要任何凭据：
/// 设定指令走 WatchConnectivity 交手机执行，token 只留在手机上。
actor WatchAPI {
    static let shared = WatchAPI()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSwissPrice() async throws -> Double {
        guard let url = URL(string: "https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD") else {
            throw WatchPriceError.message("报价地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WatchPriceError.message("Swissquote 黄金报价暂时取不到")
        }
        let rows = try JSONDecoder().decode([SwissRow].self, from: data)
        guard let price = Self.pickMidPrice(from: rows), price > 0 else {
            throw WatchPriceError.message("Swissquote 黄金报价暂时取不到")
        }
        return price
    }

    /// 把网格直接 POST 到服务器 /api/alerts（ren 2026-11-20 改定：
    /// 手表设定直发后台，不再经手机中转；请求格式与手机端
    /// CloudflareClient.saveAlerts 完全一致，服务器据此更新配置、
    /// EA 下个同步周期即采用）。凭据由手机经 WatchConnectivity 的
    /// applicationContext 同步过来、存手表 Keychain（见 WatchSecrets）。
    func postAlerts(baseURL: String, token: String, step: Double, rows: [(price: Double, enabled: Bool)]) async throws {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/alerts") else {
            throw WatchPriceError.message("服务器地址无效")
        }
        let payload: [[String: Any]] = rows.map {
            ["price": $0.price, "enabled": $0.enabled, "triggered": 0]
        }
        let body: [String: Any] = ["alerts": payload, "step": step]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WatchPriceError.message("服务器没有接受设定")
        }
    }

    private static func pickMidPrice(from rows: [SwissRow]) -> Double? {
        var fallback: Double?
        for row in rows {
            for profile in row.spreadProfilePrices ?? [] {
                guard let bid = profile.bid, let ask = profile.ask,
                      bid > 0, ask > 0, ask >= bid else { continue }
                let mid = ((bid + ask) / 2 * 1000).rounded() / 1000
                if fallback == nil { fallback = mid }
                if profile.spreadProfile == "prime" { return mid }
            }
        }
        return fallback
    }
}

/// 手表端凭据存储（服务器地址 + API token）：手机解锁后经
/// applicationContext 同步过来，存 Keychain、只留手表本地，
/// 供设定直发服务器用（ren 2026-11-20 改定）。
enum WatchSecrets {
    private static let service = "com.rickrqi77.goldalert.watch"

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct SwissRow: Decodable, Sendable {
    var spreadProfilePrices: [SwissProfile]?
}

private struct SwissProfile: Decodable, Sendable {
    var spreadProfile: String?
    var bid: Double?
    var ask: Double?
}
