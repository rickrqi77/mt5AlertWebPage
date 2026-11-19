import Foundation

/// Parses OCR text from an MT5 Chinese trade screenshot.
/// Only GOLD* / XAU* positions are kept.
///
/// Average entry uses each position's **left** price under GOLD
/// (开仓价 in `3988.21 → 3989.22`), never the right-hand 现价.
enum MT5ScreenshotParser {
    private static func splitLines(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 供识别记录展示：方向+手数读到几处、黄金价位读到几个，与
    /// GOLD 出现次数对照，一眼看出是哪条流在漏（2026-11-19 构建 49
    /// 实证：文本 GOLD×4、成品只有 2 笔，漏点在提取层而非 OCR）。
    static func extractionStats(
        ocrText: String
    ) -> (sides: Int, prices: Int, pairs: [(entry: Double, current: Double)]) {
        let lines = splitLines(ocrText)
        let s = streams(from: lines)
        return (s.sides.count, s.prices.count, pricePairs(from: lines))
    }

    /// 价位流定对：笔数 = 价位数的一半、再以 GOLD 出现次数封顶
    /// （ren 的规则：每个 GOLD 一笔）；排头多一个杂质时用现价
    /// 整齐度在偏移 0/1 间选。每对 = (左价开仓, 右价现价)，平均价
    /// 只用左价（ren 2026-11-19 明确：右边的实时价不需要）。
    private static func pricePairs(
        from lines: [String]
    ) -> [(entry: Double, current: Double)] {
        let (_, prices) = streams(from: lines)
        var pairCount = prices.count / 2
        if let firstSymbol = lines.firstIndex(where: { goldSymbol(in: $0) != nil }) {
            let symbolCount = lines[firstSymbol...].reduce(0) {
                $0 + goldSymbolCount(in: $1)
            }
            if symbolCount > 0 {
                pairCount = min(pairCount, symbolCount)
            }
        }
        guard pairCount > 0 else { return [] }
        var offset = 0
        if prices.count - 2 * pairCount >= 1 {
            let spread0 = currentSpread(prices: prices, offset: 0, count: pairCount)
            let spread1 = currentSpread(prices: prices, offset: 1, count: pairCount)
            if spread1 < spread0 { offset = 1 }
        }
        return (0..<pairCount).map {
            (entry: prices[offset + 2 * $0], current: prices[offset + 2 * $0 + 1])
        }
    }

    static func parse(ocrText: String) throws -> ScreenshotTradeData {
        let lines = splitLines(ocrText)

        // 结余/预付款先走「整段切段」取数：账户区文本按标签出现位置
        // 切段、取本段第一个数字，不依赖 OCR 把标签和数字拼在同一行
        // （构建 50 实测同一张图结余时有时无——拼行结果逐次不同，
        // 行内取数就跟着翻）。旧的行内找法留作兜底。
        guard let balance = accountValue(in: lines, label: "结余")
            ?? findLabeledNumber(
                in: lines,
                labels: ["结余"],
                rejectIfLineContains: ["净值", "预付款", "可用"]
            ) else {
            throw AppError.message("截图里找不到「结余」")
        }

        guard let margin = accountValue(in: lines, label: "预付款")
            ?? findMargin(in: lines) else {
            throw AppError.message("截图里找不到「预付款」")
        }

        // Only real OCR lines — do not append the joined blob (that duplicated positions).
        // 盈亏对比校验已按 ren 2026-11-19 的决定整体删除：解析只负责
        // 把数字提全、提对，不再做任何盈亏重算比对。
        let positions = extractGoldPositions(from: lines)
        guard !positions.isEmpty else {
            throw AppError.message("截图里没有 GOLD 持仓")
        }

        return ScreenshotTradeData(balance: balance, margin: margin, positions: positions)
    }

    // MARK: - Labels

    /// 账户区整段切段取数：把持仓区之前的所有行拼成一段文本，
    /// 定位标签后，取「本标签到下一个账户标签之间」的第一个数字。
    /// 标签与数字被 OCR 拼成什么行都不影响。
    private static func accountValue(in lines: [String], label: String) -> Double? {
        let accountLines = lines.prefix(while: {
            goldSymbol(in: $0) == nil && !$0.contains("持仓")
        })
        // 拼成一段后再压一次千分位空格：结余过千后带空格分隔
        // （如「1 290.03」），OCR 若把「1」和「290.03」拆成两行，
        // 逐行压缩压不到、firstNumber 会先抓到「1」把结余读成 1
        // （2026-11-20 ren 的 1 290.03 截图实证风险点）。
        let text = collapseThousands(accountLines.joined(separator: " "))
        guard let labelRange = text.range(of: label) else { return nil }
        let tail = text[labelRange.upperBound...]
        var end = tail.endIndex
        var others = ["结余", "净值", "可用预付款", "预付款比率", "持仓"]
        if label != "预付款" { others.append("预付款") }
        for other in others where other != label {
            if let r = tail.range(of: other), r.lowerBound < end {
                end = r.lowerBound
            }
        }
        return firstNumber(in: String(tail[..<end]))
    }

    private static func findMargin(in lines: [String]) -> Double? {
        for (index, line) in lines.enumerated() {
            if line.contains("可用预付款") || line.contains("预付款比率") {
                continue
            }
            if line == "预付款" || line.hasPrefix("预付款 ") || line.hasSuffix(" 预付款") {
                if let n = numberAfterLabel(lines: lines, index: index, label: "预付款") {
                    return n
                }
            }
            if line.contains("预付款"), !line.contains("可用"), !line.contains("比率") {
                if let n = firstNumber(in: line.replacingOccurrences(of: "预付款", with: " ")) {
                    return n
                }
                if let n = numberAfterLabel(lines: lines, index: index, label: "预付款") {
                    return n
                }
            }
        }
        return nil
    }

    private static func findLabeledNumber(
        in lines: [String],
        labels: [String],
        rejectIfLineContains: [String]
    ) -> Double? {
        for (index, line) in lines.enumerated() {
            for label in labels where line.contains(label) {
                guard let labelRange = line.range(of: label) else { continue }
                var after = String(line[labelRange.upperBound...])
                // OCR 把相邻两行拼成一行时（如「结余： 857.83 净值：
                // 910.93」），只取到下一个标签之前——旧做法整行跳过，
                // 会连「结余」都找不到、第一步就报废（2026-11-19 实证）。
                for reject in rejectIfLineContains {
                    if let r = after.range(of: reject) {
                        after = String(after[..<r.lowerBound])
                    }
                }
                if let n = firstNumber(in: after) {
                    return n
                }
                if let n = numberAfterLabel(lines: lines, index: index, label: label) {
                    return n
                }
            }
        }
        return nil
    }

    private static func numberAfterLabel(lines: [String], index: Int, label: String) -> Double? {
        let line = lines[index]
        if let range = line.range(of: label) {
            let after = String(line[range.upperBound...])
            if let n = firstNumber(in: after) { return n }
        }
        for offset in 1...3 {
            let i = index + offset
            guard i < lines.count else { break }
            let candidate = lines[i]
            if candidate.contains("结余") || candidate.contains("净值")
                || candidate.contains("预付款") || candidate.contains("持仓") {
                break
            }
            if let n = firstNumber(in: candidate) { return n }
        }
        return nil
    }

    // MARK: - Positions

    /// 持仓提取（2026-11-19 按 ren 决定重写：只提取、不做盈亏对比）。
    /// 改走「双流对位」，不再以品种行为锚分区块：OCR 的行组装在 ren
    /// 手机上会把相邻持仓行并掉，区块锚点法实证漏掉一半持仓（16:13
    /// 一图四笔只提出两笔，提出的两笔数字全对）。新法在第一个品种行
    /// 之后的整个持仓区里，分别按出现顺序收集两条流——方向+手数流、
    /// 黄金价位流（开仓/现价交替）——再逐个对位。行怎么并、盈亏数字
    /// 漂到哪一行，都不影响两条流的内部顺序。
    /// 价位流可能多出一个杂质（排头），用「现价各位应当几乎相等」
    /// 在偏移 0/1 间选更齐的一边定开仓价位。
    /// 持仓区里的两条流：方向+手数、黄金价位，各按出现顺序。
    private static func streams(
        from lines: [String]
    ) -> (sides: [(side: PositionSide, lots: Double)], prices: [Double]) {
        guard let firstSymbol = lines.firstIndex(where: { goldSymbol(in: $0) != nil }) else {
            return ([], [])
        }
        let region = Array(lines[firstSymbol...])
        let sides = collectSides(in: region.joined(separator: " "))
        var prices: [Double] = []
        for line in region {
            prices.append(contentsOf: goldPrices(inLine: line))
        }
        return (sides, prices)
    }

    /// 持仓提取（2026-11-19 按 ren 决定：只提取、不做盈亏对比）。
    /// 笔数以「价位流」为准：开仓/现价成对出现、现价各笔相同，是
    /// 画面上最硬的信号（构建 49 实证 GOLD×4、方向流与价位流必有
    /// 一条在漏，旧法取两条流的较小值、漏一条就整批缩水）。方向+
    /// 手数按顺序对位；个别笔的方向/手数 token 被 OCR 读坏而缺失
    /// 时，用其余笔的多数派（方向、手数各取众数）补位——同一账户
    /// 的持仓方向、手数通常整齐划一，补位不会改均价，手数合计也对。
    /// 价位流排头多一个杂质时，用「现价各位几乎相等」在偏移 0/1
    /// 间选更齐的一边定开仓价位。
    /// 持仓提取（2026-11-19 按 ren 决定：只提取、不做盈亏对比）。
    /// 笔数与开仓价来自价位对（pricePairs）；方向+手数按顺序对位，
    /// 个别笔的 token 被 OCR 读坏缺失时用其余笔的多数派补位（同一
    /// 账户持仓方向、手数通常整齐划一，补位不改均价、手数合计也对）。
    private static func extractGoldPositions(from lines: [String]) -> [GoldPosition] {
        let (sides, _) = streams(from: lines)
        let pairs = pricePairs(from: lines)
        guard !pairs.isEmpty, !sides.isEmpty else { return [] }

        let majoritySide = sides.map { $0.side }
            .reduce(into: [PositionSide: Int]()) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key ?? sides[0].side
        let majorityLots = sides.map { $0.lots }
            .reduce(into: [Double: Int]()) { $0[$1, default: 0] += 1 }
            .max(by: { $0.value < $1.value })?.key ?? sides[0].lots

        return pairs.enumerated().map { i, pair in
            let sd = i < sides.count
                ? sides[i]
                : (side: majoritySide, lots: majorityLots)
            return GoldPosition(
                symbol: "GOLD",
                side: sd.side,
                lots: sd.lots,
                entryPrice: pair.entry
            )
        }
    }

    /// 某偏移下各笔现价（每对第二位）的极差，用来判断价位流对齐。
    private static func currentSpread(prices: [Double], offset: Int, count: Int) -> Double {
        let currents = (0..<count).map { prices[offset + 2 * $0 + 1] }
        guard let lo = currents.min(), let hi = currents.max() else { return .infinity }
        return hi - lo
    }

    /// 在整段文本里按出现顺序收集全部（方向、手数）：手数必须是
    /// 0.01 步进（小数至多两位），OCR 把手数与后面数字读串时出现的
    /// 四位小数不采信、跳过该候选继续找。
    private static func collectSides(in text: String) -> [(side: PositionSide, lots: Double)] {
        // 方向词后面不加 \b：OCR 偶尔把「sell 0.2」粘成「sell0.2」，
        // sell 与数字之间没有词边界、带 \b 就整笔漏掉，再被多数派
        // 补成 0.1——手数合计与加权均价一起错（2026-11-20 ren 实报
        // 0.2 手没识别出来）。小数点也允许读成逗号（0,2），token
        // 修复时一并换回。
        let pattern = #"(?i)\b(buy|sell)\s*([0-9OIl]+(?:[.,][0-9OIl]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [(side: PositionSide, lots: Double)] = []
        for match in regex.matches(in: text, options: [], range: full) where match.numberOfRanges >= 3 {
            // 手数的 0 常被读成 O、1 读成 l/I（如 O.1），先修复再验。
            let token = ns.substring(with: match.range(at: 2))
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "l", with: "1")
                .replacingOccurrences(of: ",", with: ".")
            guard isValidLotsToken(token),
                  let lots = Double(token), lots > 0, lots < 100 else { continue }
            let sideRaw = ns.substring(with: match.range(at: 1)).lowercased()
            result.append((side: sideRaw == "buy" ? .buy : .sell, lots: lots))
        }
        return result
    }

    /// 一行里 GOLD/XAU 品种名出现的次数（合并行里有两个也算两个）。
    private static func goldSymbolCount(in line: String) -> Int {
        let pattern = #"(?i)\b(GOLD[A-Z0-9#._\-]*|XAU[A-Z0-9#._\-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let ns = line as NSString
        return regex.numberOfMatches(
            in: line, options: [], range: NSRange(location: 0, length: ns.length)
        )
    }

    private static func goldSymbol(in line: String) -> String? {
        let pattern = #"(?i)\b(GOLD[A-Z0-9#._\-]*|XAU[A-Z0-9#._\-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, options: [], range: full) else { return nil }
        return ns.substring(with: match.range(at: 1)).uppercased()
    }

    /// MT5 手数按 0.01 步进：整数，或小数部分至多两位（如 0.2 / 0.25 / 1.50）。
    private static func isValidLotsToken(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return true
        case 2:
            return parts[1].count <= 2
        default:
            return false
        }
    }

    /// 一行里全部黄金价位（500–20000），按出现顺序。带数字修复：
    /// OCR 常把 0 认成 O、1 认成 l/I（如 3724.9O），只对「数字开头、
    /// 含小数点」的价格形 token 做替换，修完能解析且落在黄金价位
    /// 区间才收。手数（0.1）、盈亏（106.40）不在区间内，天然排除。
    private static func goldPrices(inLine line: String) -> [Double] {
        let tokenPattern = try! NSRegularExpression(
            pattern: #"[0-9][0-9OIl]*(?:\.[0-9OIl]+)?"#
        )
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [Double] = []
        for match in tokenPattern.matches(in: line, options: [], range: full) {
            var token = ns.substring(with: match.range)
            token = token
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "l", with: "1")
            if let value = Double(token), isGoldPrice(value) {
                result.append(value)
            }
        }
        return result
    }

    private static func isGoldPrice(_ value: Double) -> Bool {
        value >= 500 && value <= 20000
    }

    // MARK: - Numbers

    private static func normalize(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "−", with: "-")
        s = s.replacingOccurrences(of: "—", with: "→")
        s = s.replacingOccurrences(of: "–", with: "→")
        s = s.replacingOccurrences(of: "→", with: " → ")
        let lines = s.components(separatedBy: .newlines).map { line -> String in
            var l = line
            // Only collapse thousand separators like "136 466" / "1 088.51".
            // Do NOT join separate values such as "0.01 3988.21" or "3988.21 3989.22".
            // 空格前的整数必须是独立整数（前面不能是数字或小数点），否则持仓行
            // 同一行里的「buy 0.2 683.40」（手数 + 盈亏）会被拼成 0.2683.40，
            // 手数被误读成 0.2683（2026-10-27 实测踩中：0.2 与 675.xx 拼成 0.2675）。
            // 前置条件必须用 lookbehind 不能消费掉：旧写法 (^|[^0-9.]) 会把整数前
            // 的分隔空格一起吃进匹配，压缩时连它一起删掉，把前面的手数和盈亏粘
            // 成一个数——「sell 0.05 6 781」→「sell 0.056781」，手数变成六位小数
            // 被判无效、整笔持仓被跳过（2026-10-30 实测：两笔 sell 0.05 只读到
            // 第一笔，日元账户盈亏带千分位空格、同行排版时踩中）。
            return collapseThousands(l)
        }
        return lines.joined(separator: "\n")
    }

    /// 压掉千分位空格（「1 290.03」→「1290.03」）。逐行压是
    /// normalize 的老规矩；accountValue 把多行拼成一段后也要再压
    /// 一次，防 OCR 把千位数字拆到两行时漏压。
    private static func collapseThousands(_ s: String) -> String {
        var l = s
        while let range = l.range(of: #"(?<![0-9.])(\d+) (\d{3}(?:\D|$))"#, options: .regularExpression) {
            let compact = l[range].replacingOccurrences(of: " ", with: "")
            l.replaceSubrange(range, with: compact)
        }
        return l
    }

    private static func firstNumber(in text: String) -> Double? {
        allNumbers(in: text).first
    }

    private static func allNumbers(in text: String) -> [Double] {
        let pattern = #"-?[0-9]+(?:\.[0-9]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: text, options: [], range: range).compactMap {
            Double(ns.substring(with: $0.range))
        }
    }
}
