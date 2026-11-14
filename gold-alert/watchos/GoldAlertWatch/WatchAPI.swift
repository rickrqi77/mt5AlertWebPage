import Foundation

enum WatchAPIError: LocalizedError, Sendable {
    case message(String)
    case unauthorized
    case badResponse

    var errorDescription: String? {
        switch self {
        case .message(let s): return s
        case .unauthorized: return "凭据已失效，请在 iPhone 上重新解锁"
        case .badResponse: return "服务器返回异常"
        }
    }
}

/// 手表端自带的最小 API 客户端，与 iOS 端用同一个 Cloudflare 接口：
/// - GET /api/status：EA 最新价、当前间隔、已设定列表、EA 在线状态；
/// - POST /api/alerts/auto：按 {step, price} 让服务器生成间隔网格并保存。
///   服务器端的网格规则与手机端 buildGrid 完全一致（起点 = 价格整数部分、
///   上下各 7 个、起点关闭其余打开，共 15 个），保存后 config_version 递增，
///   EA 在下一次 3 秒同步时自动采用新手表上选的设定——即“推送到 EA”。
/// - Swissquote 公共报价：无需凭据，手表在还没同步到凭据时也能显示最新价
///   （与 iOS 端 Swiss 来源同一接口）。
actor WatchAPI {
    static let shared = WatchAPI()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    struct Status: Decodable, Sendable {
        var price: Double?
        var step: Double?
        var ea_online: Bool?
        var paused: Bool?
        var alerts: [AlertDTO]?
    }

    struct AlertDTO: Decodable, Sendable {
        var price: Double
        var enabled: BoolOrInt?
        var triggered: BoolOrInt?
    }

    struct AutoResponse: Decodable, Sendable {
        var alerts: [AlertDTO]?
        var message: String?
        var step: Double?
        var error: String?
    }

    func getStatus(baseURL: String, token: String) async throws -> Status {
        let request = try makeRequest(path: "/api/status", baseURL: baseURL, token: token, method: "GET", body: nil)
        return try await send(request)
    }

    func autoGenerate(baseURL: String, token: String, step: Double, price: Double) async throws -> AutoResponse {
        let body: [String: Any] = ["step": step, "price": price]
        let data = try JSONSerialization.data(withJSONObject: body, options: [])
        let request = try makeRequest(path: "/api/alerts/auto", baseURL: baseURL, token: token, method: "POST", body: data)
        return try await send(request)
    }

    /// Swissquote XAU/USD 中间价（prime 档优先，与 iOS 端同一取价口径）。
    func fetchSwissPrice() async throws -> Double {
        guard let url = URL(string: "https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD") else {
            throw WatchAPIError.message("报价地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WatchAPIError.message("Swissquote 黄金报价暂时取不到")
        }
        let rows = try JSONDecoder().decode([SwissRow].self, from: data)
        guard let price = Self.pickMidPrice(from: rows), price > 0 else {
            throw WatchAPIError.message("Swissquote 黄金报价暂时取不到")
        }
        return price
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

    // MARK: - HTTP

    private func makeRequest(path: String, baseURL: String, token: String, method: String, body: Data?) throws -> URLRequest {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + path) else {
            throw WatchAPIError.message("API 地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WatchAPIError.badResponse
        }
        if http.statusCode == 401 {
            throw WatchAPIError.unauthorized
        }
        if !(200..<300).contains(http.statusCode) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw WatchAPIError.message(err)
            }
            throw WatchAPIError.message("请求失败 (\(http.statusCode))")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WatchAPIError.badResponse
        }
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

/// 与 iOS 端相同：接受 JSON 布尔或 0/1 整数。
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
