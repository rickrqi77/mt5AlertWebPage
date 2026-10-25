import Foundation

/// Parses OCR text from an MT5 Chinese trade screenshot.
/// Only GOLD* symbols are kept; other instruments are ignored.
///
/// Entry price = the **left** number under the GOLD label (开仓价 / 价格列),
/// not the right-hand mark/current price.
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

            let window = Array(lines[i..<min(i + 5, lines.count)])
            let windowText = window.joined(separator: " ")

            guard let side = detectSide(in: windowText) else {
                i += 1
                continue
            }
            guard let lots = detectLots(in: windowText) else {
                i += 1
                continue
            }
            // Left number under GOLD = entry; ignore right-hand mark / current.
            guard let entry = detectEntryPriceLeft(in: window) else {
                i += 1
                continue
            }

            positions.append(
                GoldPosition(symbol: symbol, side: side, lots: lots, entryPrice: entry)
            )
            i += 1
        }

        // Deduplicate near-identical OCR duplicates
        var unique: [GoldPosition] = []
        for p in positions {
            let dup = unique.contains {
                $0.symbol == p.symbol
                    && $0.side == p.side
                    && abs($0.lots - p.lots) < 1e-9
                    && abs($0.entryPrice - p.entryPrice) < 1e-6
            }
            if !dup { unique.append(p) }
        }
        return unique
    }

    private static func goldSymbol(in line: String) -> String? {
        let pattern = #"(?i)\b(GOLD[A-Z0-9#._\-]*|XAU[A-Z0-9#._\-]*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, options: [], range: full) else { return nil }
        return ns.substring(with: match.range(at: 1)).uppercased()
    }

    private static func detectSide(in text: String) -> PositionSide? {
        let lower = text.lowercased()
        let hasBuy = lower.range(of: #"\bbuy\b"#, options: .regularExpression) != nil
        let hasSell = lower.range(of: #"\bsell\b"#, options: .regularExpression) != nil
        if hasBuy && !hasSell { return .buy }
        if hasSell && !hasBuy { return .sell }
        return nil
    }

    private static func detectLots(in text: String) -> Double? {
        // Lot sizes are small (e.g. 0.01); do not confuse with gold prices.
        let numbers = allNumbers(in: text)
        return numbers.first { $0 > 0 && $0 < 100 }
    }

    /// Prefer the left value of a price pair under GOLD (entry ← current).
    private static func detectEntryPriceLeft(in window: [String]) -> Double? {
        let arrow = try! NSRegularExpression(
            pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(?:→|->|—|-|–)\s*([0-9]+(?:\.[0-9]+)?)"#
        )
        for line in window {
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            if let m = arrow.firstMatch(in: line, options: [], range: full), m.numberOfRanges >= 2 {
                let left = Double(ns.substring(with: m.range(at: 1))) ?? 0
                if isGoldPrice(left) { return left }
            }
        }

        // Two large prices on one line / across short window: left = entry.
        for line in window {
            let prices = allNumbers(in: line).filter(isGoldPrice)
            if prices.count >= 2 { return prices[0] }
        }

        let allPrices = window.flatMap { allNumbers(in: $0) }.filter(isGoldPrice)
        if allPrices.count >= 2 { return allPrices[0] }
        return allPrices.first
    }

    private static func isGoldPrice(_ value: Double) -> Bool {
        // XAUUSD-style open prices; excludes lots / tiny OCR noise.
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
