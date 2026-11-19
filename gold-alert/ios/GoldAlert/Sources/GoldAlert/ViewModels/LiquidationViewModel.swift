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
    private static let recognitionNoteKey = "lastRecognitionNote_v1"

    /// 最近一次截图识别的结果说明（成功写读到的笔数/均价/手数，失败写
    /// 失败在哪一步），持久化并显示在最终价明细页底部。识别失败历来是
    /// 静默保留旧数据，2026-11-19 连续几轮「识别不动」全靠猜——留这条
    /// 记录后，一眼就能定位是取图、OCR 还是解析哪一步出的问题。
    @Published private(set) var lastRecognitionNote: String = ""

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
    /// 持仓方向（最近截图解析的全部持仓同为 buy 或同为 sell 时才有值）：
    /// 每行盈亏数字在 sell 时要再乘 −1（ren 定版公式）。混仓或无数据为 nil（不翻转）。
    @Published private(set) var positionSide: PositionSide?
    /// 所有开单的平均价（按手数加权，与最终价计算用的平均价同一个，
    /// 来自最近截图解析并持久化）：每行盈亏公式的被减基准就是它——
    /// ren 22:59 明确纠正：公式里原来写「实时价格」的地方应该是这个平均价。
    /// 无持仓数据为 0。
    @Published private(set) var averageEntry: Double

    init() {
        // 默认美元模式；用户设定过模式则以下次打开仍用上次设定的（modeKey 持久化）。
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let saved = LiquidationMode(rawValue: raw) {
            mode = saved
        } else {
            mode = .usd
        }
        lastRecognitionNote = UserDefaults.standard.string(forKey: Self.recognitionNoteKey) ?? ""
        lastLiquidationPrice = UserDefaults.standard.object(forKey: Self.lastPriceKey) as? Double ?? 0
        totalLots = Self.loadTradeData()?.totalLots ?? 0
        usdJpyRate = UserDefaults.standard.object(forKey: Self.usdJpyRateKey) as? Double ?? 0
        positionSide = Self.loadTradeData()?.side
        averageEntry = Self.loadTradeData()?.averageEntry ?? 0
    }

    /// 刷新美日实时汇率（日元模式下每行盈亏数字要用）；失败静默、保留上次的值。
    func refreshUSDJPYRate() async {
        if let rate = try? await SwissquoteClient.shared.fetchUSDJPY(), rate > 0 {
            usdJpyRate = rate
            UserDefaults.standard.set(rate, forKey: Self.usdJpyRateKey)
        }
    }

    /// 最终价明细页展示/编辑的当前计算输入：优先最近一次计算结果，
    /// 其次上次存下的截图解析数据；都没有时用已发布的平均价/手数兜底。
    var currentInputs: (balance: Double, margin: Double, averageEntry: Double, totalLots: Double, side: PositionSide?) {
        if let r = result {
            return (r.balance, r.margin, r.averagePrice, r.totalLots, r.side)
        }
        if let data = Self.loadTradeData() {
            return (data.balance, data.margin, data.averageEntry, data.totalLots, data.side)
        }
        return (0, 0, averageEntry, totalLots, positionSide)
    }

    /// 明细页手工修改后保存：用改后的值重算最终价，并把这份数据存为当前持仓
    /// 数据（每行盈亏用的平均价/合计手数/方向也随之更新——手工修正解析错误
    /// 时两处一起对齐）。日元模式优先用用户改的汇率，没给才去取实时汇率。
    /// 计算失败静默、保留旧显示（与自动计算失败时的行为一致）。
    func applyManualInputs(balance: Double, margin: Double, averageEntry: Double, totalLots: Double, side: PositionSide, usdJpyRate editedRate: Double?) async {
        let data = ScreenshotTradeData(
            balance: balance,
            margin: margin,
            positions: [GoldPosition(symbol: "GOLD", side: side, lots: totalLots, entryPrice: averageEntry)]
        )
        Self.saveTradeData(data)
        self.totalLots = data.totalLots
        self.positionSide = data.side
        self.averageEntry = data.averageEntry

        do {
            let calculated: LiquidationResult
            switch mode {
            case .usd:
                calculated = try LiquidationCalculator.calculateUSD(data: data)
            case .jpy:
                let rate: Double
                if let editedRate, editedRate > 0 {
                    rate = editedRate
                } else {
                    rate = try await SwissquoteClient.shared.fetchUSDJPY()
                }
                calculated = try LiquidationCalculator.calculateJPY(data: data, usdJpyRate: rate)
            }
            applyResult(calculated)
        } catch {
            // 静默保留旧结果。
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
        guard allowed else {
            setRecognitionNote("识别失败 · 没有相册权限")
            return
        }

        do {
            let asset = try PhotoLibraryService.fetchLatestScreenshotAsset()
            // 同一张图已成功算过（删除失败时会残留）：不重复计算、也不重复弹删除确认。
            if asset.localIdentifier == UserDefaults.standard.string(forKey: Self.processedAssetKey) {
                return
            }

            let image = try await PhotoLibraryService.loadImage(from: asset)
            let ocrText = try await PhotoLibraryService.recognizeText(in: image)
            // 识别只走 iPhone 本机 AI 一条路（ren 2026-11-19 定，不要
            // 其他的）：OCR 出文本 → 本机大模型结构化提取 → 交叉校验。
            // 规则解析与云端视觉 AI 都已撤除。
            let data: ScreenshotTradeData
            if #available(iOS 26.0, *), OnDeviceScreenshotAI.isAvailable {
                data = try await Self.parseViaOnDeviceAI(ocrText: ocrText)
            } else {
                throw AppError.message("本机 AI 不可用（需 iOS 26 且 Apple Intelligence 就绪）")
            }
            // 先算成功才存：计算中途失败（如数据不合公式）绝不能把
            // 上次的好数据覆盖掉（2026-11-19 实证：AI 编造数据先落存、
            // 计算才报错，结余被冲成 0）。
            let calculated = try await Self.calculate(mode: mode, data: data)
            // 存下解析出的持仓数据，供切换日元/美元模式时不依赖截图原件即可按新公式重算。
            Self.saveTradeData(data)
            applyResult(calculated)
            setRecognitionNote(
                "识别成功 · \(data.positions.count) 笔 · 均价 \(String(format: "%.2f", data.averageEntry)) · 手数 \(String(format: "%.2f", data.totalLots))"
            )
            UserDefaults.standard.set(asset.localIdentifier, forKey: Self.processedAssetKey)

            // 删除已用截图；失败也静默（结果已保存，下次打开靠 processedAssetKey 跳过）。
            try? await PhotoLibraryService.deleteAsset(asset)
        } catch {
            // 静默：不提示、不清旧结果；但把失败原因记下来供明细页查看。
            setRecognitionNote("识别失败 · \(error.localizedDescription)")
        }
    }

    /// 本机 AI 提取结果的整形+校验：把原始数字组成持仓，过逐笔盈亏
    /// 与盈亏合计（对净值−结余）交叉校验才采用——读错宁可不用。
    private struct RawPosition {
        let side: PositionSide
        let lots: Double
        let entry: Double
        let current: Double
        let profit: Double?
    }

    private static func buildValidated(
        balance: Double,
        margin: Double,
        equity: Double?,
        raw: [RawPosition],
        source: String
    ) throws -> ScreenshotTradeData {
        guard !raw.isEmpty else {
            throw AppError.message("\(source) 没读到持仓")
        }
        // 基本合理性闸门：本机 AI 偶尔会编造整套数字（2026-11-19 实证
        // 它把指令示例里的数字当成数据交回来），编造值过不了这几关；
        // 真数据必然结余为正、方向统一、开仓价在金价区间内。
        guard balance > 0, margin >= 0 else {
            throw AppError.message("\(source) 结果不合理（结余/预付款异常）")
        }
        if let equity, equity <= 0 {
            throw AppError.message("\(source) 结果不合理（净值异常）")
        }
        guard raw.allSatisfy({ $0.side == raw[0].side }) else {
            throw AppError.message("\(source) 结果方向不统一（buy/sell 混杂）")
        }
        guard raw.allSatisfy({
            $0.entry >= 500 && $0.entry <= 20000 && $0.lots > 0 && $0.lots < 100
        }) else {
            throw AppError.message("\(source) 结果不合理（开仓价/手数异常）")
        }
        var positions: [GoldPosition] = []
        var computedList: [Double] = []
        // 与显示盈亏只差一个符号的笔先记下、不当场判死：可能是 AI 把
        // 方向标反，也可能是它把某笔盈亏的正负号读反（2026-11-19
        // 实证：3750.10 那笔实际 +113.40 蓝字盈利，AI 报成 -113.40，
        // 重算反而是对的）。两种猜测由合计（净值−结余）仲裁。
        var flipCandidates: [Int] = []
        for (index, item) in raw.enumerated() {
            let diff = item.side == .buy
                ? item.current - item.entry
                : item.entry - item.current
            let computed = diff * item.lots * 100
            computedList.append(computed)
            positions.append(
                GoldPosition(symbol: "GOLD", side: item.side, lots: item.lots, entryPrice: item.entry)
            )
            if let shown = item.profit {
                let tolerance = max(3.0, abs(shown) * 0.15)
                if abs(computed - shown) > tolerance {
                    if abs(computed + shown) <= tolerance {
                        flipCandidates.append(index)
                    } else {
                        throw AppError.message(
                            "\(source) 结果自相矛盾（单笔盈亏：重算 \(String(format: "%.2f", computed))、显示 \(String(format: "%.2f", shown))）"
                        )
                    }
                }
            }
        }
        var computedTotal = computedList.reduce(0, +)
        if let equity {
            let expected = equity - balance
            let totalTolerance = max(20.0, abs(expected) * 0.20)
            if abs(computedTotal - expected) > totalTolerance, !flipCandidates.isEmpty {
                // 原样对不上合计 → 试把存疑几笔的方向翻过来再对：
                // 翻后对上，说明 AI 标反的是方向，采用翻向版本。
                var flippedTotal = computedTotal
                for index in flipCandidates {
                    flippedTotal -= 2 * computedList[index]
                }
                if abs(flippedTotal - expected) <= totalTolerance {
                    for index in flipCandidates {
                        let old = positions[index]
                        positions[index] = GoldPosition(
                            symbol: old.symbol,
                            side: old.side == .buy ? .sell : .buy,
                            lots: old.lots,
                            entryPrice: old.entryPrice
                        )
                    }
                    computedTotal = flippedTotal
                }
            }
            guard abs(computedTotal - expected) <= totalTolerance else {
                throw AppError.message(
                    "\(source) 结果自相矛盾（盈亏合计：重算 \(String(format: "%.2f", computedTotal))、参照 \(String(format: "%.2f", expected))）"
                )
            }
        }
        return ScreenshotTradeData(balance: balance, margin: margin, positions: positions)
    }

    /// 唯一的识别路径：iPhone 本机 AI 整理 OCR 文本（离线、免费）。
    @available(iOS 26.0, *)
    private static func parseViaOnDeviceAI(ocrText: String) async throws -> ScreenshotTradeData {
        let extracted = try await OnDeviceScreenshotAI.extract(from: ocrText)
        let raw: [RawPosition] = extracted.positions.compactMap { item in
            guard let side = PositionSide(rawValue: item.side.lowercased()) else { return nil }
            return RawPosition(
                side: side, lots: item.lots, entry: item.entry,
                current: item.current, profit: item.profit
            )
        }
        return try buildValidated(
            balance: extracted.balance, margin: extracted.margin,
            equity: extracted.equity, raw: raw, source: "本机AI"
        )
    }

    private func setRecognitionNote(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let note = "\(formatter.string(from: Date())) \(text)"
        lastRecognitionNote = note
        UserDefaults.standard.set(note, forKey: Self.recognitionNoteKey)
    }

    private func applyResult(_ calculated: LiquidationResult) {
        result = calculated
        lastLiquidationPrice = calculated.liquidationPrice
        UserDefaults.standard.set(calculated.liquidationPrice, forKey: Self.lastPriceKey)
        totalLots = calculated.totalLots
        positionSide = calculated.side
        averageEntry = calculated.averagePrice
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
