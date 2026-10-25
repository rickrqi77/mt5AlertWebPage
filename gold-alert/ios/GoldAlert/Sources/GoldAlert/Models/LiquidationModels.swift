import Foundation

enum LiquidationMode: String, CaseIterable, Identifiable, Sendable {
    case jpy = "日元模式"
    case usd = "美元模式"

    var id: String { rawValue }
}

enum PositionSide: String, Sendable {
    case buy
    case sell
}

struct GoldPosition: Equatable, Sendable {
    var symbol: String
    var side: PositionSide
    var lots: Double
    var entryPrice: Double
}

struct ScreenshotTradeData: Equatable, Sendable {
    var balance: Double
    var margin: Double
    var positions: [GoldPosition]

    var totalLots: Double { positions.reduce(0) { $0 + $1.lots } }

    var averageEntry: Double {
        let lots = totalLots
        guard lots > 0 else { return 0 }
        let weighted = positions.reduce(0.0) { $0 + $1.entryPrice * $1.lots }
        return weighted / lots
    }

    var side: PositionSide? {
        let sides = Set(positions.map(\.side))
        guard sides.count == 1, let only = sides.first else { return nil }
        return only
    }
}

struct LiquidationResult: Equatable, Sendable {
    var mode: LiquidationMode
    var averagePrice: Double
    var totalLots: Double
    var side: PositionSide
    var liquidationPrice: Double
    var balance: Double
    var margin: Double
    var availableJPY: Double
    var usdJpyRate: Double
    var availableUSD: Double
    var affordablePoints: Double
}
