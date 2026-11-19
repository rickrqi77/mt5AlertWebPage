import Foundation

/// Parses OCR text from an MT5 Chinese trade screenshot.
/// Only GOLD* / XAU* positions are kept.
///
/// Average entry uses each position's **left** price under GOLD
/// (开仓价 in `3988.21 → 3989.22`), never the right-hand 现价.
enum MT5ScreenshotParser {
    static func parse(ocrText: String) throws -> ScreenshotTradeData {
        let normalized = normalize(ocrText)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let balance = findLabeledNumber(
            in: lines,
            labels: ["结余"],
            rejectIfLineContains: ["净值", "预付款", "可用"]
        ) else {
            throw AppError.message("截图里找不到「结余」")
        }

        guard let margin = findMargin(in: lines) else {
            throw AppError.message("截图里找不到「预付款」")
        }

        // Only real OCR lines — do not append the joined blob (that duplicated positions).
        let (positions, currents, displayedProfits) = try extractGoldPositions(from: lines)
        guard !positions.isEmpty else {
            throw AppError.message("截图里没有 GOLD 持仓")
        }

        // 盈亏交叉校验（第二道防线）：主校验是逐笔比对——每笔持仓行尾
        // MT5 自己显示的盈亏，与按解析出的开仓/现价/手数重算的盈亏，
        // 差超过 max(3 美元, 15%) 即整次作废。合计校验作兜底：重算合计
        // 与「净值−结余」、或与「各笔显示盈亏之和」任一对得上即放行——
        // 净值带千分位空格（1 225.93），OCR 分行时开头的「1」容易丢，
        // 只靠净值一条路时正常截图被误杀（2026-11-19 构建 30–33 连坏
        // 三轮的实因）；显示盈亏是小数字、无千分位，不吃这个亏。
        var computedTotal = 0.0
        for (index, position) in positions.enumerated() {
            let diff = position.side == .buy
                ? currents[index] - position.entryPrice
                : position.entryPrice - currents[index]
            let computed = diff * position.lots * 100
            computedTotal += computed
            if let shown = displayedProfits[index] {
                let tolerance = max(3.0, abs(shown) * 0.15)
                guard abs(computed - shown) <= tolerance else {
                    throw AppError.message(
                        "截图持仓对不上（单笔盈亏：重算 \(fmt2(computed))、显示 \(fmt2(shown))），这次没采用"
                    )
                }
            }
        }
        // 合计参照尽量多备几个独立来源，任一对上即放行：净值−结余、
        // 各笔显示盈亏之和、顶部蓝色总盈亏（「53.10 USD」）。单个数字
        // 被 OCR 读偏时不再一票否决；真读错时三个参照会一致地对不上，
        // 报错里带上重算值与参照值，一眼能看出哪边错、错多少。
        var totalChecks: [Double] = []
        if let equity = findLabeledNumber(
            in: lines,
            labels: ["净值"],
            rejectIfLineContains: ["结余", "预付款", "可用"]
        ) {
            totalChecks.append(equity - balance)
        }
        if displayedProfits.allSatisfy({ $0 != nil }) {
            totalChecks.append(displayedProfits.compactMap { $0 }.reduce(0, +))
        }
        if let headerTotal = findHeaderTotal(in: lines) {
            totalChecks.append(headerTotal)
        }
        if !totalChecks.isEmpty {
            let anyMatch = totalChecks.contains {
                abs(computedTotal - $0) <= max(20.0, abs($0) * 0.20)
            }
            guard anyMatch else {
                let refs = totalChecks.map { fmt2($0) }.joined(separator: "/")
                throw AppError.message(
                    "截图持仓对不上（盈亏合计：重算 \(fmt2(computedTotal))、参照 \(refs)），这次没采用"
                )
            }
        }

        // 最后一道手数合理性检查：MT5 手数按 0.01 步进，合计手数必须是 0.01 的
        // 整数倍；OCR 偶发读串（如手数被拼成 0.2675）时整次解析作废，
        // 自动计算会静默保留上次的好数据，而不是用坏数据覆盖最终价/每行盈亏。
        let totalLots = positions.reduce(0) { $0 + $1.lots }
        let scaledTotalLots = totalLots * 100
        guard abs(scaledTotalLots - scaledTotalLots.rounded()) < 1e-6 else {
            throw AppError.message("截图里的手数不合理")
        }

        return ScreenshotTradeData(balance: balance, margin: margin, positions: positions)
    }

    // MARK: - Labels

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
            if rejectIfLineContains.contains(where: { line.contains($0) }) { continue }
            for label in labels where line.contains(label) {
                if let n = firstNumber(in: line.replacingOccurrences(of: label, with: " ")) {
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

    /// 返回持仓、各自配对到的现价与 MT5 在该行显示的盈亏（后两者只供
    /// parse 里的盈亏交叉校验用，不进 GoldPosition 模型；显示盈亏读
    /// 不到时为 nil、跳过该笔校验）。
    private static func extractGoldPositions(
        from lines: [String]
    ) throws -> (positions: [GoldPosition], currents: [Double], displayedProfits: [Double?]) {
        // 第一步：收集全部持仓起点（含 GOLD/XAU 品种的行）。方向+手数就在该行
        // 上（MT5 排版如「GOLD# sell 0.05」），或紧随的一两行内；查找止于下一个
        // 品种行，避免把下一笔的方向手数串过来。
        var starts: [(index: Int, symbol: String, side: PositionSide, lots: Double)] = []
        for (index, line) in lines.enumerated() {
            guard let symbol = goldSymbol(in: line) else { continue }
            var end = min(index + 3, lines.count)
            var j = index + 1
            while j < end {
                if goldSymbol(in: lines[j]) != nil { end = j; break }
                j += 1
            }
            if let sideLots = detectSideAndLots(in: Array(lines[index..<end])) {
                starts.append((index: index, symbol: symbol, side: sideLots.side, lots: sideLots.lots))
            }
        }

        // 第二步：逐笔在自己的区块内取价对（2026-11-19 重构）。区块 =
        // 本笔品种行到下一笔品种行之前。区块内按出现顺序遇到的前两个
        // 黄金价位就是开仓价与现价——不依赖箭头符号是否被 OCR 认出、
        // 不依赖价格行有没有被拆成两行。旧做法（全局收集价对再顺序
        // 配对）在 ren 的手机上反复栽在同一处：一行价格认不成对时
        // 后面整体顺移，先是写错均价/手数，改加笔数校验后又变成整次
        // 作废、识别像坏了。区块内不足两个价位才整次作废（保留旧数据）。
        // 区块从品种行开始，账户区的结余/净值等大数字在第一笔之前，
        // 不会落进任何区块；盈亏数字（如 106.40）不在黄金价位区间，
        // 也不会被误收。
        var positions: [GoldPosition] = []
        var currents: [Double] = []
        var displayedProfits: [Double?] = []
        for (k, start) in starts.enumerated() {
            let blockEnd = k + 1 < starts.count ? starts[k + 1].index : lines.count
            var prices: [Double] = []
            for line in lines[start.index..<blockEnd] {
                prices.append(contentsOf: goldPrices(inLine: line))
            }
            guard prices.count >= 2 else {
                throw AppError.message("截图持仓对不上（有持仓的价格没读全），这次没采用")
            }
            positions.append(
                GoldPosition(
                    symbol: start.symbol,
                    side: start.side,
                    lots: start.lots,
                    entryPrice: prices[0]
                )
            )
            currents.append(prices[1])
            displayedProfits.append(
                displayedProfit(inBlock: lines[start.index..<blockEnd], lots: start.lots)
            )
        }
        return (positions, currents, displayedProfits)
    }

    /// 该笔 MT5 显示的盈亏（如 123.90、-25.20）。在整个持仓区块里找：
    /// 带小数点的数字里排除手数本身与黄金价位（开仓/现价），最后一个
    /// 即盈亏；没有则 nil。只查品种行时，若 OCR 把盈亏拼到了价格行上
    /// 就读不到（2026-11-19 构建 34 实证：逐笔校验被整段跳过、只剩
    /// 净值一条参照又被读偏，正常截图被误杀）。要求带小数点，是为了
    /// 不把品种名里的整数（如 GOLD24-7）误当盈亏。
    private static func displayedProfit(inBlock block: ArraySlice<String>, lots: Double) -> Double? {
        let pattern = try! NSRegularExpression(pattern: #"-?[0-9]+\.[0-9]+"#)
        var profit: Double? = nil
        for line in block {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            for match in pattern.matches(in: line, options: [], range: full) {
                guard let value = Double(ns.substring(with: match.range)) else { continue }
                if abs(abs(value) - lots) < 0.0001 { continue }
                if isGoldPrice(abs(value)) { continue }
                profit = value
            }
        }
        return profit
    }

    /// 截图顶部蓝色大字是全部持仓的浮盈合计（如「53.10 USD」），
    /// 字大、位置固定，OCR 最不容易读错——作盈亏合计的独立参照。
    private static func findHeaderTotal(in lines: [String]) -> Double? {
        let pattern = try! NSRegularExpression(
            pattern: #"(-?[0-9][0-9 ]*(?:\.[0-9]+)?)\s*USD"#
        )
        for line in lines.prefix(6) {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let match = pattern.firstMatch(in: line, options: [], range: full),
               match.numberOfRanges >= 2 {
                let raw = ns.substring(with: match.range(at: 1))
                    .replacingOccurrences(of: " ", with: "")
                if let value = Double(raw) { return value }
            }
        }
        return nil
    }

    private static func fmt2(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func goldSymbol(in line: String) -> String? {
        // No trailing \b: symbols often end with '#' (non-word), which breaks \b.
        let pattern = #"(?i)\b(GOLD[A-Z0-9#._\-]*|XAU[A-Z0-9#._\-]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, options: [], range: full) else { return nil }
        return ns.substring(with: match.range(at: 1)).uppercased()
    }

    private static func detectSideAndLots(in lines: [String]) -> (side: PositionSide, lots: Double)? {
        let text = lines.joined(separator: " ")
        let pattern = #"(?i)\b(buy|sell)\b\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        // 逐个候选检查：手数必须是 0.01 步进（小数至多两位）。OCR 把手数和
        // 后面的盈亏数字读串时会出现 0.2675 这类四位小数，不能采信，
        // 跳过这个候选继续找下一个合格的 buy/sell 手数。
        for match in regex.matches(in: text, options: [], range: full) where match.numberOfRanges >= 3 {
            let token = ns.substring(with: match.range(at: 2))
            guard isValidLotsToken(token),
                  let lots = Double(token), lots > 0, lots < 100 else { continue }
            let sideRaw = ns.substring(with: match.range(at: 1)).lowercased()
            let side: PositionSide = sideRaw == "buy" ? .buy : .sell
            return (side, lots)
        }
        return nil
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
            while let range = l.range(of: #"(?<![0-9.])(\d+) (\d{3}(?:\D|$))"#, options: .regularExpression) {
                let compact = l[range].replacingOccurrences(of: " ", with: "")
                l.replaceSubrange(range, with: compact)
            }
            return l
        }
        return lines.joined(separator: "\n")
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
