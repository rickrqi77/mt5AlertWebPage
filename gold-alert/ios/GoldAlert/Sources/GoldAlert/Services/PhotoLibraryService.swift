import Foundation
import Photos
import UIKit
import Vision

enum PhotoLibraryService {
    static func requestAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    /// Latest asset in the Screenshots album; falls back to latest camera-roll image.
    static func fetchLatestScreenshotAsset() throws -> PHAsset {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )
        if let album = albums.firstObject {
            let assets = PHAsset.fetchAssets(in: album, options: options)
            if let asset = assets.firstObject {
                return asset
            }
        }

        let all = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = all.firstObject else {
            throw AppError.message("相册里没有可读取的截图")
        }
        return asset
    }

    static func loadImage(from asset: PHAsset) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .none
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(throwing: AppError.message("读取截图已取消"))
                    return
                }
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let image = UIImage(data: data) else {
                    continuation.resume(throwing: AppError.message("无法解码截图"))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    /// 一次 Vision 识别的最小结果：整图归一化坐标的包围盒 + 文本。
    private struct Obs {
        var box: CGRect
        var text: String
    }

    private static func observe(cgImage: CGImage) async throws -> [Obs] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: observations.map {
                    Obs(box: $0.boundingBox, text: $0.topCandidates(1).first?.string ?? "")
                })
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw AppError.message("截图格式无法识别")
        }

        // 整图先识别一遍。
        var all = try await observe(cgImage: cgImage)

        // 再逐条带识别并合并（2026-11-19 ren 指出每行交易间距相同、
        // 不许漏）：整图一遍在 ren 手机上反复整行漏掉持仓（第 2、4 笔
        // 没读坏、是根本没进结果）。把整图切成互相重叠的横条逐条识
        // 别，每条里只有一两行字，无从漏起；结果换算回整图坐标合并。
        let stripHeight: CGFloat = 0.08
        let stripStep: CGFloat = 0.04
        var stripMinY: CGFloat = 0
        while stripMinY < 1.0 {
            let band = CGRect(
                x: 0, y: stripMinY, width: 1,
                height: min(stripHeight, 1 - stripMinY)
            )
            if let crop = cropImage(cgImage, visionBand: band) {
                let local = try await observe(cgImage: crop)
                for o in local {
                    let globalBox = CGRect(
                        x: o.box.minX,
                        y: band.minY + o.box.minY * band.height,
                        width: o.box.width,
                        height: o.box.height * band.height
                    )
                    all.append(Obs(box: globalBox, text: o.text))
                }
            }
            stripMinY += stripStep
        }

        // 去重：整图与条带、相邻条带会重复读到同一行。按包围盒判同：
        // 中心纵距 < 0.012 且横距 < 0.05 视为同一处文字，只留先到的
        // （整图结果在前）。相邻持仓行纵距约 0.073，不会误杀。
        var unique: [Obs] = []
        for o in all where !o.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if unique.contains(where: {
                abs($0.box.midY - o.box.midY) < 0.012
                    && abs($0.box.midX - o.box.midX) < 0.05
            }) {
                continue
            }
            unique.append(o)
        }
        return assembleLines(unique)
    }

    /// 按 Vision 归一化坐标（原点在左下）裁出一条横带。
    private static func cropImage(_ cgImage: CGImage, visionBand band: CGRect) -> CGImage? {
        let w = CGFloat(cgImage.width)
        let h = CGFloat(cgImage.height)
        let rect = CGRect(
            x: 0,
            y: (1 - band.maxY) * h,
            width: w,
            height: band.height * h
        ).integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard rect.height >= 8 else { return nil }
        return cgImage.cropping(to: rect)
    }

    /// 把识别碎片按纵向重叠拼成行（自上而下）。同一视觉行的碎片纵向
    /// 必然重叠：与当前行区间重叠达较矮一方四成即同行；一组里已有
    /// 品种行时，下一个品种行强制另起一组（每个 GOLD 独占一笔）。
    private static func assembleLines(_ observations: [Obs]) -> String {
        let sorted = observations.sorted { a, b in
            if abs(a.box.maxY - b.box.maxY) > 0.01 {
                return a.box.maxY > b.box.maxY
            }
            return a.box.minX < b.box.minX
        }
        var lines: [String] = []
        var currentLine: [Obs] = []
        var lineMinY: CGFloat = 0
        var lineMaxY: CGFloat = 0
        var groupHasSymbol = false

        func flush() {
            guard !currentLine.isEmpty else { return }
            let parts = currentLine.sorted { $0.box.minX < $1.box.minX }.map { $0.text }
            let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { lines.append(joined) }
            currentLine.removeAll()
            groupHasSymbol = false
        }

        for obs in sorted {
            let box = obs.box
            let upper = obs.text.uppercased()
            let isSymbol = upper.contains("GOLD") || upper.contains("XAU")
            if currentLine.isEmpty {
                currentLine.append(obs)
                lineMinY = box.minY
                lineMaxY = box.maxY
                groupHasSymbol = isSymbol
                continue
            }
            if isSymbol && groupHasSymbol {
                flush()
                currentLine.append(obs)
                lineMinY = box.minY
                lineMaxY = box.maxY
                groupHasSymbol = true
                continue
            }
            let overlap = min(lineMaxY, box.maxY) - max(lineMinY, box.minY)
            let minHeight = min(lineMaxY - lineMinY, box.height)
            if overlap >= 0.4 * minHeight {
                currentLine.append(obs)
                lineMinY = min(lineMinY, box.minY)
                lineMaxY = max(lineMaxY, box.maxY)
                groupHasSymbol = groupHasSymbol || isSymbol
            } else {
                flush()
                currentLine.append(obs)
                lineMinY = box.minY
                lineMaxY = box.maxY
                groupHasSymbol = isSymbol
            }
        }
        flush()
        return lines.joined(separator: "\n")
    }

    static func deleteAsset(_ asset: PHAsset) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: AppError.message("删除截图失败"))
                }
            })
        }
    }
}
