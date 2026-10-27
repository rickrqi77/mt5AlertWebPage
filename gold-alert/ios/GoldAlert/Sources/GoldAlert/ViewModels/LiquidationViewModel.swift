import Foundation
import Photos
import SwiftUI

@MainActor
final class LiquidationViewModel: ObservableObject {
    private static let modeKey = "liquidationMode"
    private static let lastPriceKey = "lastLiquidationPrice_v1"
    private static let processedAssetKey = "lastProcessedScreenshotID_v1"
    private static let tradeDataKey = "lastScreenshotTradeData_v1"
    private static let usdJpyRateKey = "lastUSDJPYRate_v1"

    @Published var mode: LiquidationMode
    @Published var busy = false
    @Published var result: LiquidationResult?
    /// 上一次计算成功的最终价（持久化）。从未计算成功过为 0。
    @Published private(set) var lastLiquidationPrice: Double
    /// 合计手数：最近一次截图解析出的全部 GOLD 持仓手数之和（持久化恢复），
    /// 供每行盈亏数字计算用（点差 × 合计手数）。从未解析成功过为 0。
    @Published private(set) var totalLots: Double
    /// 美日实时汇率（USDJPY）：日元模式算最终价时取得，另持久化上次的值，
    /// 供每行盈亏数字在日元模式下换算用。从未取得过为 0。
    @Published private(set) var usdJpyRate: Double

    init() {
        // 默认美元模式；用户设定过模式则以下次打开仍用上次设定的（modeKey 持久化）。
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let saved = LiquidationMode(rawValue: raw) {
            mode = saved
        } else {
            mode = .usd
        }
        lastLiquidationPrice = UserDefaults.standard.object(forKey: Self.lastPriceKey) as? Double ?? 0
        totalLots = Self.loadTradeData()?.totalLots ?? 0
        usdJpyRate = UserDefaults.standard.object(forKey: Self.usdJpyRateKey) as? Double ?? 0
    }

    /// 刷新美日实时汇率（日元模式下每行盈亏数字要用）；失败静默、保留上次的值。
    func refreshUSDJPYRate() async {
        if let rate = try? await SwissquoteClient.shared.fetchUSDJPY(), rate > 0 {
            usdJpyRate = rate
            UserDefaults.standard.set(rate, forKey: Self.usdJpyRateKey)
        }
    }

    /// 画面实时价下方显示的最终价：本次算出新的用新的，否则显示上次结果（无则 0）。
    /// 注意取的是计算结果的最后一步 liquidationPrice（最终价），不是平均价 averagePrice。
    var displayedLiquidationPrice: Double {
        result?.liquidationPrice ?? lastLiquidationPrice
    }

    /// 点「提醒事项」弹菜单切换日元/美元模式：设定后持久化，下次打开默认就是这个模式。
    /// 切换后立刻按新模式的公式、基于上次截图解析出的持仓数据重算最终价；
    /// 没有可用的持仓数据时回到 0，并放行最新截图让后续自动计算按新模式处理。
    func switchMode(_ newMode: LiquidationMode) async {
        guard mode != newMode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        result = nil

        if let data = Self.loadTradeData() {
            if let calculated = try? await Self.calculate(mode: newMode, data: data) {
                applyResult(calculated)
            }
            // 重算失败（如汇率取不到）时静默保留旧显示值，等下次成功计算再刷新。
        } else {
            lastLiquidationPrice = 0
            UserDefaults.standard.removeObject(forKey: Self.lastPriceKey)
            UserDefaults.standard.removeObject(forKey: Self.processedAssetKey)
            await autoCalculateFromLatestScreenshot()
        }
    }

    /// 画面打开时自动调用：默认去截图相册找最后一张图片并计算最终价，不需点任何按钮。
    /// 找不到图、图片不对、解析/计算失败都静默返回——不弹任何提示，并保留上次结果。
    /// 只有读到新图且计算成功才刷新结果（并持久化）；成功后沿用旧逻辑删掉已用截图。
    func autoCalculateFromLatestScreenshot() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }

        let allowed = await PhotoLibraryService.requestAccess()
        guard allowed else { return }

        do {
            let asset = try PhotoLibraryService.fetchLatestScreenshotAsset()
            // 同一张图已成功算过（删除失败时会残留）：不重复计算、也不重复弹删除确认。
            if asset.localIdentifier == UserDefaults.standard.string(forKey: Self.processedAssetKey) {
                return
            }

            let image = try await PhotoLibraryService.loadImage(from: asset)
            let ocr = try await PhotoLibraryService.recognizeText(in: image)
            let data = try MT5ScreenshotParser.parse(ocrText: ocr)
            // 存下解析出的持仓数据，供切换日元/美元模式时不依赖截图原件即可按新公式重算。
            Self.saveTradeData(data)
            totalLots = data.totalLots

            let calculated = try await Self.calculate(mode: mode, data: data)
            applyResult(calculated)
            UserDefaults.standard.set(asset.localIdentifier, forKey: Self.processedAssetKey)

            // 删除已用截图；失败也静默（结果已保存，下次打开靠 processedAssetKey 跳过）。
            try? await PhotoLibraryService.deleteAsset(asset)
        } catch {
            // 静默：不提示、不清旧结果。
        }
    }

    private func applyResult(_ calculated: LiquidationResult) {
        result = calculated
        lastLiquidationPrice = calculated.liquidationPrice
        UserDefaults.standard.set(calculated.liquidationPrice, forKey: Self.lastPriceKey)
        totalLots = calculated.totalLots
        // 日元模式计算时用的汇率一并留住，供每行盈亏数字换算。
        if let rate = calculated.usdJpyRate, rate > 0 {
            usdJpyRate = rate
            UserDefaults.standard.set(rate, forKey: Self.usdJpyRateKey)
        }
    }

    private static func calculate(mode: LiquidationMode, data: ScreenshotTradeData) async throws -> LiquidationResult {
        switch mode {
        case .jpy:
            let usdJpy = try await SwissquoteClient.shared.fetchUSDJPY()
            return try LiquidationCalculator.calculateJPY(data: data, usdJpyRate: usdJpy)
        case .usd:
            return try LiquidationCalculator.calculateUSD(data: data)
        }
    }

    private static func saveTradeData(_ data: ScreenshotTradeData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: tradeDataKey)
        }
    }

    private static func loadTradeData() -> ScreenshotTradeData? {
        guard let stored = UserDefaults.standard.data(forKey: tradeDataKey) else { return nil }
        return try? JSONDecoder().decode(ScreenshotTradeData.self, from: stored)
    }
}
