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

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw AppError.message("截图格式无法识别")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                // Sort top-to-bottom, then left-to-right for MT5 layout.
                let sorted = observations.sorted { a, b in
                    let ay = a.boundingBox.midY
                    let by = b.boundingBox.midY
                    if abs(ay - by) > 0.015 {
                        return ay > by
                    }
                    return a.boundingBox.minX < b.boundingBox.minX
                }
                var lines: [String] = []
                var currentY: CGFloat?
                var currentLine: [VNRecognizedTextObservation] = []

                func flush() {
                    guard !currentLine.isEmpty else { return }
                    let parts = currentLine.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                        .compactMap { $0.topCandidates(1).first?.string }
                    let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if !joined.isEmpty { lines.append(joined) }
                    currentLine.removeAll()
                }

                for obs in sorted {
                    if let y = currentY, abs(obs.boundingBox.midY - y) > 0.018 {
                        flush()
                    }
                    currentY = obs.boundingBox.midY
                    currentLine.append(obs)
                }
                flush()
                continuation.resume(returning: lines.joined(separator: "\n"))
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
