import Foundation
import FoundationModels

/// iPhone 本机 AI（Apple Intelligence / Foundation Models）整理 OCR 文本：
/// 本地规则解析失败时的第二层。本机模型只能读文本、看不了图，但规则
/// 解析栽的多是文本层问题（标签行粘连、千分位空格、个别字认错），
/// 把 Vision 的原始文本交给它做结构化提取正对症。提取结果回主流程
/// 后照样过交叉校验才采用。iOS 26 起可用，不可用时静默跳过这一层。
@available(iOS 26.0, *)
enum OnDeviceScreenshotAI {
    @Generable
    struct ExtractedPosition {
        @Guide(description: "方向：buy 或 sell")
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
