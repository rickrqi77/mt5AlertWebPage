import Foundation
import Photos
import SwiftUI

@MainActor
final class LiquidationViewModel: ObservableObject {
    @Published var mode: LiquidationMode = .jpy
    @Published var busy = false
    @Published var errorText: String?
    @Published var result: LiquidationResult?
    @Published var debugOCR: String = ""
    @Published var showDeleteConfirm = false
    @Published var lastAssetLocalID: String?

    private var lastAsset: PHAsset?

    func readLatestScreenshotAndCalculate() async {
        errorText = nil
        result = nil
        busy = true
        defer { busy = false }

        let allowed = await PhotoLibraryService.requestAccess()
        guard allowed else {
            errorText = "请在设置里允许访问相册（需可删除权限）"
            return
        }

        do {
            let asset = try PhotoLibraryService.fetchLatestScreenshotAsset()
            lastAsset = asset
            lastAssetLocalID = asset.localIdentifier

            let image = try await PhotoLibraryService.loadImage(from: asset)
            let ocr = try await PhotoLibraryService.recognizeText(in: image)
            debugOCR = ocr

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
            showDeleteConfirm = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    func deleteLastScreenshot() async {
        guard let asset = lastAsset else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoLibraryService.deleteAsset(asset)
            lastAsset = nil
            lastAssetLocalID = nil
            showDeleteConfirm = false
        } catch {
            errorText = "删除失败：\(error.localizedDescription)"
        }
    }

    func keepScreenshot() {
        showDeleteConfirm = false
    }
}
