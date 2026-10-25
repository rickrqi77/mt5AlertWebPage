import Foundation

enum LiquidationCalculator {
    /// JPY account:
    /// availableJPY = balance - margin * 0.2
    /// availableUSD = availableJPY / usdJpy
    /// points = availableUSD / (totalLots * 100)
    static func calculateJPY(
        data: ScreenshotTradeData,
        usdJpyRate: Double
    ) throws -> LiquidationResult {
        guard usdJpyRate > 0 else {
            throw AppError.message("USD/JPY 汇率无效")
        }
        let availableJPY = data.balance - data.margin * 0.2
        let availableUSD = availableJPY / usdJpyRate
        return try finish(
            mode: .jpy,
            data: data,
            availableUSD: availableUSD,
            availableJPY: availableJPY,
            usdJpyRate: usdJpyRate
        )
    }

    /// USD account: skip FX conversion.
    /// availableUSD = balance - margin * 0.2
    /// then same points / liquidation as JPY mode.
    static func calculateUSD(data: ScreenshotTradeData) throws -> LiquidationResult {
        let availableUSD = data.balance - data.margin * 0.2
        return try finish(
            mode: .usd,
            data: data,
            availableUSD: availableUSD,
            availableJPY: nil,
            usdJpyRate: nil
        )
    }

    private static func finish(
        mode: LiquidationMode,
        data: ScreenshotTradeData,
        availableUSD: Double,
        availableJPY: Double?,
        usdJpyRate: Double?
    ) throws -> LiquidationResult {
        guard data.totalLots > 0 else {
            throw AppError.message("GOLD 总手数为 0")
        }
        guard let side = data.side else {
            throw AppError.message("GOLD 同时有 buy 和 sell，无法用同一套公式算爆仓价")
        }

        let average = data.averageEntry
        let affordablePoints = availableUSD / (data.totalLots * 100)
        let liquidation: Double
        switch side {
        case .sell:
            liquidation = average + affordablePoints
        case .buy:
            liquidation = average - affordablePoints
        }

        return LiquidationResult(
            mode: mode,
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
