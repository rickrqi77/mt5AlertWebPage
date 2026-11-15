import Foundation

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

private struct SwissRow: Decodable, Sendable {
    var spreadProfilePrices: [SwissProfile]?
}

private struct SwissProfile: Decodable, Sendable {
    var spreadProfile: String?
    var bid: Double?
    var ask: Double?
}
