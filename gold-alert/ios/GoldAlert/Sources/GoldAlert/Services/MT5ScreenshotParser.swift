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
        // 盈亏对比校验已按 ren 2026-11-19 的决定整体删除：解析只负责
        // 把数字提全、提对，不再做任何盈亏重算比对。
        let positions = extractGoldPositions(from: lines)
        guard !positions.isEmpty else {
            throw AppError.message("截图里没有 GOLD 持仓")
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
    private static func extractGoldPositions(from lines: [String]) -> [GoldPosition] {
        guard let firstSymbol = lines.firstIndex(where: { goldSymbol(in: $0) != nil }) else {
            return []
        }
        let region = Array(lines[firstSymbol...])

        // 方向+手数流：整段文本上逐个收集（合并行里有两个也照单全收）。
        let sides = collectSides(in: region.joined(separator: " "))
        guard !sides.isEmpty else { return [] }

        // 黄金价位流：逐行按出现顺序收集（带 O→0 等数字修复）。
        var prices: [Double] = []
        for line in region {
            prices.append(contentsOf: goldPrices(inLine: line))
        }

        let pairCount = min(sides.count, prices.count / 2)
        guard pairCount > 0 else { return [] }

        // 偏移选择：现价在每对的第二位，各笔现价应几乎相同；
        // 偏移 0 与 1（价位流排头多一个杂质时）比谁的现价更整齐。
        var offset = 0
        if prices.count - 2 * pairCount >= 1 {
            let spread0 = currentSpread(prices: prices, offset: 0, count: pairCount)
            let spread1 = currentSpread(prices: prices, offset: 1, count: pairCount)
            if spread1 < spread0 { offset = 1 }
        }

        return (0..<pairCount).map { i in
            GoldPosition(
                symbol: "GOLD",
                side: sides[i].side,
                lots: sides[i].lots,
                entryPrice: prices[offset + 2 * i]
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
        let pattern = #"(?i)\b(buy|sell)\b\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [(side: PositionSide, lots: Double)] = []
        for match in regex.matches(in: text, options: [], range: full) where match.numberOfRanges >= 3 {
            let token = ns.substring(with: match.range(at: 2))
            guard isValidLotsToken(token),
                  let lots = Double(token), lots > 0, lots < 100 else { continue }
            let sideRaw = ns.substring(with: match.range(at: 1)).lowercased()
            result.append((side: sideRaw == "buy" ? .buy : .sell, lots: lots))
        }
        return result
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
