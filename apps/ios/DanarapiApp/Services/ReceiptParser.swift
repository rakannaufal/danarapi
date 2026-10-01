import Foundation

enum ReceiptParser {
    static func lines(from text: String) -> [ReceiptLine] {
        let patterns = [
            #"^\s*(.+?)\s+(\d{1,3})\s*[x×@]\s*(?:Rp\s*)?([\d.]+)(?:\s+(?:Rp\s*)?([\d.]+))?\s*$"#,
            #"^\s*(.+?)\s+(\d{1,3})\s+(?:Rp\s*)?([\d.]+)\s+(?:Rp\s*)?([\d.]+)\s*$"#,
            #"^\s*(.+?)\s+(\d{1,3})\s+(?:Rp\s*)?([\d.]+)\s*$"#
        ]
        return text.split(whereSeparator: \.isNewline).prefix(400).compactMap { raw in
            let line = String(raw)
            let lower = line.lowercased()
            guard !["total", "subtotal", "pajak", "tax", "service", "diskon", "discount", "tunai", "kembali"].contains(where: { lower.hasPrefix($0) }) else { return nil }
            for (index, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let nameRange = Range(match.range(at: 1), in: line), let quantityRange = Range(match.range(at: 2), in: line), let priceRange = Range(match.range(at: 3), in: line),
                      let quantity = Int(line[quantityRange]), quantity > 0,
                      let price = Int64(line[priceRange].replacingOccurrences(of: ".", with: "")), price > 0, price <= Money.maximum / Int64(quantity) else { continue }
                var unitPrice = price
                if index == 2 {
                    guard price % Int64(quantity) == 0 else { continue }
                    unitPrice = price / Int64(quantity)
                } else if match.numberOfRanges > 4, let totalRange = Range(match.range(at: 4), in: line) {
                    guard Int64(line[totalRange].replacingOccurrences(of: ".", with: "")) == price * Int64(quantity) else { continue }
                }
                guard unitPrice <= Money.maximum / Int64(quantity) else { continue }
                return ReceiptLine(name: String(line[nameRange]).trimmingCharacters(in: .whitespaces), quantity: quantity, unitPrice: String(unitPrice))
            }
            return nil
        }.prefix(100).map { $0 }
    }
}
