import Foundation

enum LiquidationCalculator {
    /// JPY account mode (user-defined rules).
    /// availableJPY = balance - margin * 0.2
    /// availableUSD = availableJPY / usdJpy
    /// points = availableUSD / (totalLots * 100)
    /// sell: liq = avg + points ; buy: liq = avg - points
    static func calculateJPY(
        data: ScreenshotTradeData,
        usdJpyRate: Double
    ) throws -> LiquidationResult {
        guard data.totalLots > 0 else {
            throw AppError.message("GOLD 总手数为 0")
        }
        guard let side = data.side else {
            throw AppError.message("GOLD 同时有 buy 和 sell，无法用同一套公式算爆仓价")
        }
        guard usdJpyRate > 0 else {
            throw AppError.message("USD/JPY 汇率无效")
        }

        let average = data.averageEntry
        let availableJPY = data.balance - data.margin * 0.2
        let availableUSD = availableJPY / usdJpyRate
        let affordablePoints = availableUSD / (data.totalLots * 100)
        let liquidation: Double
        switch side {
        case .sell:
            liquidation = average + affordablePoints
        case .buy:
            liquidation = average - affordablePoints
        }

        return LiquidationResult(
            mode: .jpy,
            averagePrice: average,
            totalLots: data.totalLots,
            side: side,
            liquidationPrice: liquidation,
            balance: data.balance,
            margin: data.margin,
            availableJPY: availableJPY,
            usdJpyRate: usdJpyRate,
            availableUSD: availableUSD,
            affordablePoints: affordablePoints
        )
    }
}
