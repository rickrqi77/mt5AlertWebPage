import Foundation

/// Fetches XAU/USD directly from Swissquote public BBO (not via the website).
actor SwissquoteClient {
    static let shared = SwissquoteClient()

    private let url = URL(
        string: "https://forex-data-feed.swissquote.com/public-quotes/bboquotes/instrument/XAU/USD"
    )!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchQuote() async throws -> Quote {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.message("Swissquote 报价暂时取不到")
        }

        let rows = try JSONDecoder().decode([SwissRow].self, from: data)
        guard let picked = Self.pickQuote(from: rows) else {
            throw AppError.message("Swissquote 报价暂时取不到")
        }
        return picked
    }

    private static func pickQuote(from rows: [SwissRow]) -> Quote? {
        var fallback: Quote?
        for row in rows {
            for profile in row.spreadProfilePrices ?? [] {
                guard let bid = profile.bid, let ask = profile.ask,
                      bid > 0, ask > 0, ask >= bid else { continue }
                let quote = Quote(
                    symbol: "XAUUSD",
                    bid: roundPrice(bid),
                    ask: roundPrice(ask),
                    price: roundPrice((bid + ask) / 2),
                    source: "swissquote"
                )
                if fallback == nil { fallback = quote }
                if profile.spreadProfile == "prime" {
                    return quote
                }
            }
        }
        return fallback
    }

    private static func roundPrice(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
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
