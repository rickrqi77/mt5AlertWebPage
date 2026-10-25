import Foundation

/// Same Cloudflare Worker / Pages API as the website.
actor CloudflareClient {
    static let shared = CloudflareClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func unlock(baseURL: String, token: String) async throws {
        _ = try await getStatus(baseURL: baseURL, token: token)
    }

    func getStatus(baseURL: String, token: String) async throws -> StatusPayload {
        try await get("/api/status", baseURL: baseURL, token: token)
    }

    func getAlerts(baseURL: String, token: String) async throws -> AlertsPayload {
        try await get("/api/alerts", baseURL: baseURL, token: token)
    }

    func getSettings(baseURL: String, token: String) async throws -> SettingsPayload {
        try await get("/api/settings", baseURL: baseURL, token: token)
    }

    /// Upload Swissquote quote so Cloudflare holds the latest mid for settings/auto.
    func uploadPrice(baseURL: String, token: String, quote: Quote) async throws -> PriceUploadResponse {
        let body: [String: Any] = [
            "symbol": quote.symbol,
            "bid": quote.bid,
            "ask": quote.ask,
            "price": quote.price,
            "source": quote.source.isEmpty ? "swissquote" : quote.source,
        ]
        return try await post("/api/app/price", baseURL: baseURL, token: token, json: body)
    }

    func saveAlerts(
        baseURL: String,
        token: String,
        alerts: [AlertItem],
        step: Double
    ) async throws -> SaveAlertsResponse {
        let payload: [[String: Any]] = alerts.map { item in
            [
                "price": item.priceValue ?? 0,
                "enabled": item.enabled,
                "triggered": item.enabled ? 0 : (item.triggered ? 1 : 0),
            ]
        }
        let body: [String: Any] = [
            "alerts": payload,
            "step": step,
        ]
        return try await post("/api/alerts", baseURL: baseURL, token: token, json: body)
    }

    func autoGenerate(
        baseURL: String,
        token: String,
        step: Double,
        price: Double
    ) async throws -> AutoAlertsResponse {
        let body: [String: Any] = [
            "step": step,
            "price": price,
        ]
        return try await post("/api/alerts/auto", baseURL: baseURL, token: token, json: body)
    }

    func setPaused(baseURL: String, token: String, paused: Bool) async throws -> PauseResponse {
        try await post("/api/pause", baseURL: baseURL, token: token, json: ["paused": paused])
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, baseURL: String, token: String) async throws -> T {
        let request = try makeRequest(path: path, baseURL: baseURL, token: token, method: "GET", body: nil)
        return try await send(request)
    }

    private func post<T: Decodable>(
        _ path: String,
        baseURL: String,
        token: String,
        json: [String: Any]
    ) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        let request = try makeRequest(path: path, baseURL: baseURL, token: token, method: "POST", body: data)
        return try await send(request)
    }

    private func makeRequest(
        path: String,
        baseURL: String,
        token: String,
        method: String,
        body: Data?
    ) throws -> URLRequest {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + path) else {
            throw AppError.message("API 地址无效")
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
            throw AppError.badResponse
        }
        if http.statusCode == 401 {
            throw AppError.unauthorized
        }
        if !(200..<300).contains(http.statusCode) {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = obj["error"] as? String {
                throw AppError.message(err)
            }
            throw AppError.message("请求失败 (\(http.statusCode))")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AppError.badResponse
        }
    }
}
