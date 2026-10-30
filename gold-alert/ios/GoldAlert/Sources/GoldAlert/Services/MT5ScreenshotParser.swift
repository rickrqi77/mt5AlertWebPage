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
        let positions = extractGoldPositions(from: lines)
        guard !positions.isEmpty else {
            throw AppError.message("截图里没有 GOLD 持仓")
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

    private static func extractGoldPositions(from lines: [String]) -> [GoldPosition] {
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

        // 第二步：收集全部开仓价（「开仓价 → 现价」的左侧价），保持行序；
        // 同一行有多个箭头价对时逐个收。
        var priceEntries: [(index: Int, price: Double)] = []
        for (index, line) in lines.enumerated() {
            for price in entryPrices(inLine: line) {
                priceEntries.append((index: index, price: price))
            }
        }

        // 第三步：按顺序一一配对——第 k 笔持仓取它品种行之后（含本行）、还没被
        // 前面持仓用掉的第一条价格。旧做法「品种行后 4 行窗口里找价格」在
        // Vision 行序交错时会整笔漏掉：2026-10-30 ren 截图（两笔 sell 0.05
        // @4019.91/@4025.39）只读出一笔，合计手数 0.10 变 0.05、平均价只剩
        // 第一笔的开仓价，因第二笔的价格行落在了窗口外。配对只按先后顺序，
        // 不按内容去重：同方向同手数的重复行就是多笔真实订单（2026-10-28
        // dedupe 误杀的教训同样适用）。
        var used = Set<Int>()
        var positions: [GoldPosition] = []
        for start in starts {
            guard let found = priceEntries.enumerated().first(where: {
                $0.element.index >= start.index && !used.contains($0.offset)
            }) else { continue }
            used.insert(found.offset)
            positions.append(
                GoldPosition(
                    symbol: start.symbol,
                    side: start.side,
                    lots: start.lots,
                    entryPrice: found.element.price
                )
            )
        }
        return positions
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

    /// 一行里全部 `开仓价 → 现价` 的左侧开仓价（通常一个）。
    /// Do not treat the hyphen inside `GOLD24-7` as a price arrow.
    private static func entryPrices(inLine line: String) -> [Double] {
        // Both sides must look like gold prices (3+ digits). No bare "-" (breaks GOLD24-7).
        let arrow = try! NSRegularExpression(
            pattern: #"([0-9]{3,}(?:\.[0-9]+)?)\s*(?:→|->|➜|⇒|—|–|>|›|»|\s-\s)\s*([0-9]{3,}(?:\.[0-9]+)?)"#
        )
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [Double] = []
        for pm in arrow.matches(in: line, options: [], range: full) where pm.numberOfRanges >= 3 {
            let left = Double(ns.substring(with: pm.range(at: 1))) ?? 0
            let right = Double(ns.substring(with: pm.range(at: 2))) ?? 0
            if isGoldPrice(left), isGoldPrice(right) { result.append(left) }
        }
        if !result.isEmpty { return result }
        // No arrow glyph: two gold-range prices on one line → left is entry.
        let prices = allNumbers(in: line).filter(isGoldPrice)
        if prices.count >= 2 { return [prices[0]] }
        return []
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
