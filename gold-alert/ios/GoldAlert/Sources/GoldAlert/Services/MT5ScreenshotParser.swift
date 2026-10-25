import Foundation

/// Parses OCR text from an MT5 Chinese trade screenshot.
/// Only GOLD* symbols are kept; other instruments are ignored.
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

        let positions = extractGoldPositions(from: lines + [normalized])
        guard !positions.isEmpty else {
            throw AppError.message("截图里没有 GOLD 持仓")
        }

        return ScreenshotTradeData(balance: balance, margin: margin, positions: positions)
    }

    // MARK: - Labels

    private static func findMargin(in lines: [String]) -> Double? {
        for (index, line) in lines.enumerated() {
            // Prefer exact 预付款 row; skip 可用预付款 / 预付款比率
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
        // Same line after label
        let line = lines[index]
        if let range = line.range(of: label) {
            let after = String(line[range.upperBound...])
            if let n = firstNumber(in: after) { return n }
        }
        // Next few lines (MT5 often stacks label above value)
        for offset in 1...3 {
            let i = index + offset
            guard i < lines.count else { break }
            let candidate = lines[i]
            // Stop if next label appears
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
        let joined = lines.joined(separator: "\n")

        // Pattern A: GOLD24-7# sell 0.01  (possibly split across lines)
        let symbolSideLots = try! NSRegularExpression(
            pattern: #"(?i)(GOLD[A-Z0-9#._\-]*)\s*(buy|sell)\s*([0-9]+(?:\.[0-9]+)?)"#,
            options: []
        )
        let priceArrow = try! NSRegularExpression(
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:→|->|—|-|–)\s*([0-9]+(?:\.[0-9]+)?)"#,
            options: []
        )

        // Walk line-by-line for pairing with following price arrow
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let match = symbolSideLots.firstMatch(in: line, options: [], range: full),
               match.numberOfRanges >= 4 {
                let symbol = ns.substring(with: match.range(at: 1)).uppercased()
                let sideRaw = ns.substring(with: match.range(at: 2)).lowercased()
                let lots = Double(ns.substring(with: match.range(at: 3))) ?? 0
                let side: PositionSide = sideRaw == "buy" ? .buy : .sell

                // Entry = left number under GOLD (开仓价), never the right-hand 现价.
                let nearby = Array(lines[i..<min(i + 3, lines.count)])
                let entry = leftEntryPrice(in: nearby, priceArrow: priceArrow)

                if lots > 0, let entry, isGoldSymbol(symbol) {
                    positions.append(GoldPosition(symbol: symbol, side: side, lots: lots, entryPrice: entry))
                }
            }
            i += 1
        }

        // Fallback: whole-document regex if line pairing missed (OCR mashed layout)
        if positions.isEmpty {
            let nsJoined = joined as NSString
            let full = NSRange(location: 0, length: nsJoined.length)
            let matches = symbolSideLots.matches(in: joined, options: [], range: full)
            let priceMatches = priceArrow.matches(in: joined, options: [], range: full)
            for (idx, match) in matches.enumerated() where match.numberOfRanges >= 4 {
                let symbol = nsJoined.substring(with: match.range(at: 1)).uppercased()
                guard isGoldSymbol(symbol) else { continue }
                let sideRaw = nsJoined.substring(with: match.range(at: 2)).lowercased()
                let lots = Double(nsJoined.substring(with: match.range(at: 3))) ?? 0
                let side: PositionSide = sideRaw == "buy" ? .buy : .sell
                // Prefer the left price of the first pair after this GOLD match.
                let entry: Double? = {
                    let start = match.range.location
                    for pm in priceMatches where pm.range.location >= start && pm.numberOfRanges >= 2 {
                        let left = Double(nsJoined.substring(with: pm.range(at: 1))) ?? 0
                        if isGoldPrice(left) { return left }
                    }
                    // No arrow: take left of the first two gold-range numbers after match.
                    let from = min(start, nsJoined.length)
                    let len = min(160, nsJoined.length - from)
                    let after = nsJoined.substring(with: NSRange(location: from, length: len))
                    let prices = allNumbers(in: after).filter(isGoldPrice)
                    if prices.count >= 2 { return prices[0] }
                    return prices.first
                }()
                if lots > 0, let entry {
                    positions.append(GoldPosition(symbol: symbol, side: side, lots: lots, entryPrice: entry))
                }
            }
        }

        return positions
    }

    private static func isGoldSymbol(_ symbol: String) -> Bool {
        let s = symbol.uppercased()
        return s.contains("GOLD") || s.hasPrefix("XAU")
    }

    /// Left number of the price pair under GOLD (开仓价); ignore 现价 on the right.
    private static func leftEntryPrice(in lines: [String], priceArrow: NSRegularExpression) -> Double? {
        for line in lines {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let pm = priceArrow.firstMatch(in: line, options: [], range: full),
               pm.numberOfRanges >= 2 {
                let left = Double(ns.substring(with: pm.range(at: 1))) ?? 0
                if isGoldPrice(left) { return left }
            }
            let prices = allNumbers(in: line).filter(isGoldPrice)
            if prices.count >= 2 { return prices[0] }
        }
        let all = lines.flatMap { allNumbers(in: $0) }.filter(isGoldPrice)
        return all.first
    }

    private static func isGoldPrice(_ value: Double) -> Bool {
        value >= 500 && value <= 20000
    }

    // MARK: - Numbers

    private static func normalize(_ text: String) -> String {
        var s = text
        // Common OCR confusions
        s = s.replacingOccurrences(of: "−", with: "-")
        s = s.replacingOccurrences(of: "—", with: "→")
        s = s.replacingOccurrences(of: "–", with: "→")
        s = s.replacingOccurrences(of: "→", with: " → ")
        // Collapse weird spaces but keep newlines
        let lines = s.components(separatedBy: .newlines).map { line -> String in
            var l = line
            // "136 466" / "12 508" / "1 088.51" → remove thousand spaces between digits
            while let range = l.range(of: #"(\d) (\d)"#, options: .regularExpression) {
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
