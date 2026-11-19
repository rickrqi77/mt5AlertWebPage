import Foundation
import FoundationModels

/// 截图识别的唯一路径（ren 2026-11-19 定）：Vision OCR 出文本后，
/// 由 iPhone 本机 AI（Apple Intelligence / Foundation Models）做
/// 结构化提取。本机模型只能读文本、看不了图，但此前的失败多是文本
/// 层问题（标签行粘连、千分位空格、个别字认错），交给它整理正对症。
/// 提取结果照样过交叉校验才采用。iOS 26 起可用。
@available(iOS 26.0, *)
enum OnDeviceScreenshotAI {
    @Generable
    struct ExtractedPosition {
        @Guide(description: "方向：buy 或 sell（sell 时现价高于开仓价则盈亏为负，buy 时相反，方向须与盈亏符号一致）")
        var side: String
        @Guide(description: "手数，如 0.1")
        var lots: Double
        @Guide(description: "开仓价（箭头左边的价格）")
        var entry: Double
        @Guide(description: "现价（箭头右边的价格）")
        var current: Double
        @Guide(description: "该笔盈亏，带正负号")
        var profit: Double
    }

    @Generable
    struct ExtractedTrade {
        @Guide(description: "结余")
        var balance: Double
        @Guide(description: "净值")
        var equity: Double
        @Guide(description: "预付款（不是可用预付款，也不是预付款比率）")
        var margin: Double
        @Guide(description: "全部 GOLD 或 XAU 品种持仓，按出现顺序")
        var positions: [ExtractedPosition]
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func extract(from ocrText: String) async throws -> ExtractedTrade {
        let instructions = """
        你是 MT5 交易截图 OCR 文本的数据提取器。文本可能有错字、行粘连、千分位空格（如 1 262.23 应读作 1262.23）。只提取 GOLD 或 XAU 品种的持仓；开仓价是箭头左边的价格，现价是右边的价格。数字不要带逗号或空格。
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "从下面这段 OCR 文本中提取账户与持仓数据：\n\(ocrText)",
            generating: ExtractedTrade.self
        )
        return response.content
    }
}
