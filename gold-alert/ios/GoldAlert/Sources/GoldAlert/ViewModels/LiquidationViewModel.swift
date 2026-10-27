import Foundation
import Photos
import SwiftUI

@MainActor
final class LiquidationViewModel: ObservableObject {
    private static let modeKey = "liquidationMode"
    private static let lastPriceKey = "lastLiquidationPrice_v1"
    private static let processedAssetKey = "lastProcessedScreenshotID_v1"

    @Published var mode: LiquidationMode
    @Published var busy = false
    @Published var result: LiquidationResult?
    /// 上一次计算成功的最终价（持久化）。从未计算成功过为 0。
    @Published private(set) var lastLiquidationPrice: Double

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let saved = LiquidationMode(rawValue: raw) {
            mode = saved
        } else {
            mode = .jpy
        }
        lastLiquidationPrice = UserDefaults.standard.object(forKey: Self.lastPriceKey) as? Double ?? 0
    }

    /// 画面实时价下方显示的最终价：本次算出新的用新的，否则显示上次结果（无则 0）。
    var displayedLiquidationPrice: Double {
        result?.liquidationPrice ?? lastLiquidationPrice
    }

    func setMode(_ newMode: LiquidationMode) {
        guard mode != newMode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        // Previous result used the other formula — clear until recalculated.
        result = nil
        lastLiquidationPrice = 0
        UserDefaults.standard.removeObject(forKey: Self.lastPriceKey)
    }

    func toggleMode() {
        setMode(mode == .jpy ? .usd : .jpy)
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
            let calculated: LiquidationResult
            switch mode {
            case .jpy:
                let usdJpy = try await SwissquoteClient.shared.fetchUSDJPY()
                calculated = try LiquidationCalculator.calculateJPY(data: data, usdJpyRate: usdJpy)
            case .usd:
                calculated = try LiquidationCalculator.calculateUSD(data: data)
            }
            result = calculated
            lastLiquidationPrice = calculated.liquidationPrice
            UserDefaults.standard.set(calculated.liquidationPrice, forKey: Self.lastPriceKey)
            UserDefaults.standard.set(asset.localIdentifier, forKey: Self.processedAssetKey)

            // 删除已用截图；失败也静默（结果已保存，下次打开靠 processedAssetKey 跳过）。
            try? await PhotoLibraryService.deleteAsset(asset)
        } catch {
            // 静默：不提示、不清旧结果。
        }
    }
}
