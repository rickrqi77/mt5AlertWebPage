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
        var positions: [GoldPosition] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard let symbol = goldSymbol(in: line) else {
                i += 1
                continue
            }

            // Same line, or next few lines: "sell 0.01" / "buy 0.01"
            let window = Array(lines[i..<min(i + 4, lines.count)])
            guard let sideLots = detectSideAndLots(in: window) else {
                i += 1
                continue
            }

            // Price line is under the GOLD row, e.g. "3988.21 → 3989.22" → use 3988.21
            guard let entry = leftEntryPrice(in: window) else {
                i += 1
                continue
            }

            positions.append(
                GoldPosition(
                    symbol: symbol,
                    side: sideLots.side,
                    lots: sideLots.lots,
                    entryPrice: entry
                )
            )
            i += 1
        }

        return dedupe(positions)
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
        guard let match = regex.firstMatch(in: text, options: [], range: full),
              match.numberOfRanges >= 3 else { return nil }
        let sideRaw = ns.substring(with: match.range(at: 1)).lowercased()
        let lots = Double(ns.substring(with: match.range(at: 2))) ?? 0
        guard lots > 0, lots < 100 else { return nil }
        let side: PositionSide = sideRaw == "buy" ? .buy : .sell
        return (side, lots)
    }

    /// Left number of `开仓价 → 现价` under GOLD.
    /// Do not treat the hyphen inside `GOLD24-7` as a price arrow.
    private static func leftEntryPrice(in lines: [String]) -> Double? {
        // Both sides must look like gold prices (3+ digits). No bare "-" (breaks GOLD24-7).
        let arrow = try! NSRegularExpression(
            pattern: #"([0-9]{3,}(?:\.[0-9]+)?)\s*(?:→|->|➜|⇒|—|–|>|›|»|\s-\s)\s*([0-9]{3,}(?:\.[0-9]+)?)"#
        )
        for line in lines {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            let matches = arrow.matches(in: line, options: [], range: full)
            for pm in matches where pm.numberOfRanges >= 3 {
                let left = Double(ns.substring(with: pm.range(at: 1))) ?? 0
                let right = Double(ns.substring(with: pm.range(at: 2))) ?? 0
                if isGoldPrice(left), isGoldPrice(right) { return left }
            }
            // No arrow glyph: two gold-range prices on one line → left is entry.
            let prices = allNumbers(in: line).filter(isGoldPrice)
            if prices.count >= 2 { return prices[0] }
        }
        return nil
    }

    private static func dedupe(_ positions: [GoldPosition]) -> [GoldPosition] {
        var out: [GoldPosition] = []
        for p in positions {
            let dup = out.contains {
                $0.symbol == p.symbol
                    && $0.side == p.side
                    && abs($0.lots - p.lots) < 1e-9
                    && abs($0.entryPrice - p.entryPrice) < 1e-6
            }
            if !dup { out.append(p) }
        }
        return out
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
            while let range = l.range(of: #"(\d) (\d{3}(?:\D|$))"#, options: .regularExpression) {
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
