import Foundation

public struct ItemAllocation: Codable, Hashable, Sendable {
    public var memberID: String
    public var quantity: Int
    public init(memberID: String, quantity: Int) { self.memberID = memberID; self.quantity = quantity }
}

public struct ReceiptLine: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var quantity: Int
    public var unitPrice: String
    public var allocations: [ItemAllocation]
    public init(id: String = UUID().uuidString, name: String, quantity: Int, unitPrice: String, allocations: [ItemAllocation] = []) {
        self.id = id; self.name = name; self.quantity = quantity; self.unitPrice = unitPrice; self.allocations = allocations
    }
}

public struct ReceiptSettings: Codable, Hashable, Sendable {
    public var serviceRate: Double
    public var taxRate: Double
    public var taxOnService: Bool
    public var taxIncluded: Bool?
    public init(serviceRate: Double = 5, taxRate: Double = 10, taxOnService: Bool = false, taxIncluded: Bool = false) {
        self.serviceRate = serviceRate; self.taxRate = taxRate; self.taxOnService = taxOnService; self.taxIncluded = taxIncluded
    }
}

public struct ReceiptShare: Equatable, Sendable, Identifiable {
    public let id: String
    public let subtotal: Int64
    public let service: Int64
    public let tax: Int64
    public let discount: Int64
    public let rounding: Int64
    public var total: Int64 { subtotal - discount + service + tax + rounding }
}

public struct ReceiptCalculation: Sendable {
    public let rows: [ReceiptShare]
    public let unassigned: [String]
    public var total: Int64 { rows.reduce(0) { $0 + $1.total } }
    public var result: ItemSplitResult { ItemSplitResult(total: String(total), shares: Dictionary(uniqueKeysWithValues: rows.map { ($0.id, String($0.total)) })) }
}

public struct ItemSplit: Codable, Hashable, Sendable {
    public var items: [ReceiptLine]
    public var tax: String
    public var service: String
    public var discount: String
    public var settings: ReceiptSettings?
    public var rounding: String?
    public init(items: [ReceiptLine], tax: String = "0", service: String = "0", discount: String = "0", settings: ReceiptSettings? = nil, rounding: String = "0") {
        self.items = items; self.tax = tax; self.service = service; self.discount = discount; self.settings = settings; self.rounding = rounding
    }
}

public struct ItemSplitResult: Codable, Equatable, Sendable {
    public let total: String
    public let shares: [String: String]
}

public struct ReceiptScanImage: Codable, Sendable {
    public var mimeType: String
    public var data: String
    public init(mimeType: String = "image/jpeg", data: String) { self.mimeType = mimeType; self.data = data }
}
public struct ReceiptScanRequest: Encodable, Sendable { public let images: [ReceiptScanImage] }
public struct ReceiptScanResponse: Decodable, Sendable {
    public let status: String
    public let data: ScannedReceipt?
    public var message: String {
        switch status {
        case "ok": "Struk terbaca. Periksa semua angka sebelum melanjutkan."
        case "quota_exceeded": "Kuota scan habis. Coba besok atau isi manual."
        case "config_error": "Scan belum dikonfigurasi. Isi manual tetap tersedia."
        case "not_a_receipt": "Menu tidak ditemukan. Pilih foto struk yang lengkap."
        case "no_result": "Struk belum terbaca. Foto ulang dengan cahaya cukup."
        case "busy": "Scan sedang diproses. Tunggu sebentar lalu coba lagi."
        case "invalid_image": "Pilih maksimal tiga foto, total maksimal 4 MB."
        default: "Layanan pembaca struk bermasalah. Isi manual tetap tersedia."
        }
    }
}
public struct ScannedReceiptItem: Codable, Hashable, Sendable {
    public var name: String
    public var qty: Int
    public var unitPrice: Int64?
    public var lineTotal: Int64?
    public var note: String?
    enum CodingKeys: String, CodingKey { case name, qty, note; case unitPrice = "unit_price"; case lineTotal = "line_total" }
    public init(name: String = "", qty: Int = 1, unitPrice: Int64? = nil, lineTotal: Int64? = nil, note: String? = nil) { self.name = name; self.qty = qty; self.unitPrice = unitPrice; self.lineTotal = lineTotal; self.note = note }
}
public struct ScannedReceipt: Codable, Hashable, Sendable {
    public var merchant: String?
    public var date: String?
    public var items: [ScannedReceiptItem]
    public var subtotal: Int64?
    public var serviceCharge: Int64?
    public var tax: Int64?
    public var discount: Int64
    public var rounding: Int64
    public var grandTotal: Int64?
    public var taxIncludedInPrice: Bool
    public var unreadableFields: [String]
    enum CodingKeys: String, CodingKey {
        case merchant, date, items, subtotal, tax, discount, rounding
        case serviceCharge = "service_charge"; case grandTotal = "grand_total"
        case taxIncludedInPrice = "tax_included_in_price"; case unreadableFields = "unreadable_fields"
    }
    public var validation: ScannedReceiptValidation {
        var problems: [String] = []; var badRows: [Int] = []; var warnings: [String] = []
        let rupiah: (Int64) -> String = { "Rp \($0.formatted(.number.locale(Locale(identifier: "id_ID"))))" }
        let amounts = [subtotal, serviceCharge, tax, grandTotal, discount] + items.flatMap { [$0.unitPrice, $0.lineTotal] }
        guard items.count <= 100, amounts.compactMap({ $0 }).allSatisfy({ (0...Money.maximum).contains($0) }), rounding >= -Money.maximum, rounding <= Money.maximum else {
            return ScannedReceiptValidation(problems: ["Nominal atau jumlah menu di luar batas. Periksa kembali struk."], warnings: [], badRows: Array(items.indices))
        }
        for (index, item) in items.enumerated() {
            if item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(1...999999).contains(item.qty) || item.unitPrice == nil || item.lineTotal == nil || unreadableFields.contains(where: { $0.hasPrefix("items[\(index)]") }) {
                problems.append("Menu \(index + 1): nama, jumlah atau harga belum lengkap."); badRows.append(index); continue
            }
            guard let price = item.unitPrice, let line = item.lineTotal, (0...Money.maximum).contains(price), (0...Money.maximum).contains(line) else { problems.append("Menu \(index + 1): harga tidak valid."); badRows.append(index); continue }
            if abs(Int64(item.qty) * price - line) > 100 { problems.append("\(item.name): \(item.qty.formatted(.number.locale(Locale(identifier: "id_ID")))) × \(rupiah(price)) = \(rupiah(Int64(item.qty) * price)), tetapi total baris tercetak \(rupiah(line)) (selisih \(rupiah(abs(Int64(item.qty) * price - line))))."); badRows.append(index) }
        }
        if items.isEmpty { problems.append("Belum ada menu.") }
        let sum = items.reduce(Int64(0)) { $0 + ($1.lineTotal ?? 0) }
        if let subtotal, abs(sum - subtotal) > 100 { problems.append("Jumlah menu \(rupiah(sum)), subtotal struk \(rupiah(subtotal)) (selisih \(rupiah(abs(sum - subtotal)))).") }
        if let grandTotal {
            if let base = taxIncludedInPrice ? sum : subtotal {
                let expected = base + (taxIncludedInPrice ? 0 : (serviceCharge ?? 0) + (tax ?? 0)) - discount + rounding
                if abs(expected - grandTotal) > 100 { problems.append("Total hitungan \(rupiah(expected)), total struk \(rupiah(grandTotal)) (selisih \(rupiah(abs(expected - grandTotal)))).") }
            } else { problems.append("Subtotal belum terbaca; isi dari struk.") }
        } else { warnings.append("Total struk belum terbaca; isi untuk mencocokkan tagihan.") }
        if !unreadableFields.isEmpty { warnings.append("Periksa field belum terbaca: \(unreadableFields.joined(separator: ", ")).") }
        if let date {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            if let value = formatter.date(from: date), formatter.string(from: value) == date {} else { warnings.append("Tanggal struk belum valid; gunakan YYYY-MM-DD.") }
        }
        if let subtotal, subtotal > 0 {
            for (name, amount) in [("Service", serviceCharge), ("Pajak", tax)] { if let amount, Double(amount) / Double(subtotal) > 0.25 { warnings.append("\(name) di luar rentang wajar 0–25%.") } }
        }
        return ScannedReceiptValidation(problems: problems, warnings: warnings, badRows: badRows)
    }
}
public struct ScannedReceiptValidation: Sendable {
    public let problems: [String]
    public let warnings: [String]
    public let badRows: [Int]
    public var passed: Bool { problems.isEmpty }
}

extension ScannedReceiptItem {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(qty, forKey: .qty)
        try container.encode(unitPrice.map(String.init), forKey: .unitPrice)
        try container.encode(lineTotal.map(String.init), forKey: .lineTotal)
        try container.encode(note, forKey: .note)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        qty = try container.decode(Int.self, forKey: .qty)
        unitPrice = try container.receiptAmount(.unitPrice)
        lineTotal = try container.receiptAmount(.lineTotal)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

extension ScannedReceipt {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(merchant, forKey: .merchant)
        try container.encode(date, forKey: .date)
        try container.encode(items, forKey: .items)
        try container.encode(subtotal.map(String.init), forKey: .subtotal)
        try container.encode(serviceCharge.map(String.init), forKey: .serviceCharge)
        try container.encode(tax.map(String.init), forKey: .tax)
        try container.encode(String(discount), forKey: .discount)
        try container.encode(String(rounding), forKey: .rounding)
        try container.encode(grandTotal.map(String.init), forKey: .grandTotal)
        try container.encode(taxIncludedInPrice, forKey: .taxIncludedInPrice)
        try container.encode(unreadableFields, forKey: .unreadableFields)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        merchant = try container.decodeIfPresent(String.self, forKey: .merchant)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        items = try container.decode([ScannedReceiptItem].self, forKey: .items)
        subtotal = try container.receiptAmount(.subtotal)
        serviceCharge = try container.receiptAmount(.serviceCharge)
        tax = try container.receiptAmount(.tax)
        discount = try container.receiptAmount(.discount) ?? 0
        rounding = try container.receiptAmount(.rounding) ?? 0
        grandTotal = try container.receiptAmount(.grandTotal)
        taxIncludedInPrice = try container.decodeIfPresent(Bool.self, forKey: .taxIncludedInPrice) ?? false
        unreadableFields = try container.decodeIfPresent([String].self, forKey: .unreadableFields) ?? []
    }
}

private extension KeyedDecodingContainer {
    func receiptAmount(_ key: Key) throws -> Int64? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Int64.self, forKey: key) { return value }
        let text = try decode(String.self, forKey: key)
        guard text.range(of: #"^-?\d+$"#, options: .regularExpression) != nil, let value = Int64(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Nominal struk harus angka bulat atau string desimal.")
        }
        return value
    }
}

public enum ReceiptTextParser {
    public static func parse(_ text: String) -> ScannedReceipt {
        let lines = text.split(whereSeparator: \.isNewline).prefix(400).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var items: [ScannedReceiptItem] = []
        var subtotal: Int64?
        var service: Int64?
        var tax: Int64?
        var discount: Int64 = 0
        var rounding: Int64 = 0
        var grandTotal: Int64?
        var previousName: String?
        var pendingCost: String?
        var unreadable: [String] = []
        let money = #"(?:Rp\s*)?([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]+)(?:[.,]00)?"#
        let patterns = [
            "^(.+?)\\s+(\\d{1,6})\\s*[x×@]\\s*" + money + "(?:\\s+" + money + ")?$",
            "^(.+?)\\s+(\\d{1,6})\\s+" + money + "\\s+" + money + "$"
        ]
        for line in lines {
            let lower = line.lowercased()
            if parsedDate(line) != nil { previousName = nil; pendingCost = nil; continue }
            if let costKey = pendingCost, let match = captures("^" + money + "$", line), let value = amount(match[0]) {
                switch costKey {
                case "subtotal": subtotal = value
                case "discount": discount = value
                case "total": grandTotal = value
                case "service": service = value
                case "tax": tax = value
                default: break
                }
                previousName = nil
                pendingCost = nil
                continue
            }
            pendingCost = nil
            if let match = captures(#"^(?:total\s+)?(?:discount|diskon|disc)(?:\s+[0-9.,]+\s*%)?\s*[:=]?\s*-?"# + money + "$", line) { discount = amount(match[0]) ?? 0; previousName = nil; continue }
            if captures(#"^(?:\d+\s*(?:item|barang)\s*)?(?:jumlah|sub\s*total|subtotal)\s*[:=]?\s*$"#, line) != nil { pendingCost = "subtotal"; previousName = nil; continue }
            if captures(#"^(?:total\s+)?(?:discount|diskon|disc)\s*[:=]?\s*$"#, line) != nil { pendingCost = "discount"; previousName = nil; continue }
            if captures(#"^(?:grand\s*total|total)\s*[:=]?\s*$"#, line) != nil { pendingCost = "total"; previousName = nil; continue }
            if captures(#"^(?:service(?:\s+charge)?|servis)\s*[:=]?\s*$"#, line) != nil { pendingCost = "service"; previousName = nil; continue }
            if captures(#"^(?:tax|pajak|ppn|pb1)\s*[:=]?\s*$"#, line) != nil { pendingCost = "tax"; previousName = nil; continue }
            if let match = captures(#"^(?:sub\s*total|subtotal)\s*[:=]?\s*"# + money + "$", line) { subtotal = amount(match[0]); previousName = nil; continue }
            if let match = captures(#"^(?:grand\s*total|total(?:\s+(?:bayar|pembayaran|amount))?|net\s*total)\s*[:=]?\s*"# + money + "$", line) { grandTotal = amount(match[0]); previousName = nil; continue }
            if let match = captures(#"^(?:service(?:\s+charge)?|servis)(?:\s+[0-9.,]+\s*%)?\s*[:=]?\s*"# + money + "$", line) { service = amount(match[0]); previousName = nil; continue }
            if let match = captures(#"^(?:tax|pajak|ppn|pb1)(?:\s+[0-9.,]+\s*%)?\s*[:=]?\s*"# + money + "$", line) { tax = amount(match[0]); previousName = nil; continue }
            if let match = captures(#"^(?:discount|diskon|disc)(?:\s+[0-9.,]+\s*%)?\s*[:=]?\s*-?"# + money + "$", line) { discount = amount(match[0]) ?? 0; previousName = nil; continue }
            if let match = captures(#"^(?:rounding|pembulatan)\s*[:=]?\s*(-?)"# + money + "$", line), let value = amount(match[1]) { rounding = match[0] == "-" ? -value : value; previousName = nil; continue }
            if let match = captures(#"^([0-9.,]+\s*%)\s+"# + money + "$", line), !items.isEmpty {
                items[items.count - 1].note = match[0]
                items[items.count - 1].lineTotal = amount(match[1])
                continue
            }
            if captures(#"^[0-9.,]+\s*%$"#, line) != nil, !items.isEmpty {
                items[items.count - 1].note = line
                if line.replacingOccurrences(of: " ", with: "") == "0%" { items[items.count - 1].lineTotal = items.last?.lineTotal ?? items.last?.unitPrice }
                continue
            }
            if ["total", "subtotal", "tunai", "cash", "kembali", "change", "paid", "bayar", "harga", "price", "qty", "item", "jumlah", "date", "tanggal", "invoice", "no.", "telp"].contains(where: { lower.hasPrefix($0) }) { previousName = nil; continue }
            var parsed: ScannedReceiptItem?
            for pattern in patterns {
                if let match = captures(pattern, line), let quantity = Int(match[1]), quantity > 0 {
                    parsed = ScannedReceiptItem(name: match[0], qty: quantity, unitPrice: amount(match[2]), lineTotal: match.count > 3 ? amount(match[3]) : nil)
                    break
                }
            }
            if parsed == nil, let previousName, let match = captures("^(\\d{1,6})\\s+" + money + "\\s+" + money + "$", line), let quantity = Int(match[0]), quantity > 0 {
                parsed = ScannedReceiptItem(name: previousName, qty: quantity, unitPrice: amount(match[1]), lineTotal: amount(match[2]))
            }
            if parsed == nil, let match = captures("^(.+?)\\s+(?:-\\s*)?" + money + "$", line), match[0].contains(where: \.isLetter), !isMetadata(match[0]) {
                parsed = ScannedReceiptItem(name: match[0].trimmingCharacters(in: .whitespaces), qty: 1, unitPrice: amount(match[1]), lineTotal: nil)
                unreadable.append("items[\(items.count)].qty")
            }
            if let parsed, items.count < 100 { items.append(parsed); previousName = nil; continue }
            if line.contains(where: \.isLetter), !line.contains("/"), !lower.contains("www."), !lower.contains("@") { previousName = line }
            else { previousName = nil }
        }
        let date = parsedDate(text)
        if grandTotal == nil { unreadable.append("grand_total") }
        if subtotal == nil { unreadable.append("subtotal") }
        if date == nil { unreadable.append("date") }
        return ScannedReceipt(merchant: merchantName(lines), date: date, items: items, subtotal: subtotal, serviceCharge: service, tax: tax, discount: discount, rounding: rounding, grandTotal: grandTotal, taxIncludedInPrice: false, unreadableFields: unreadable)
    }

    private static func isMetadata(_ value: String) -> Bool {
        let lower = value.lowercased().trimmingCharacters(in: .whitespaces)
        return ["jl.", "jl ", "jalan", "wa ", "tel", "ig ", "instagram", "nb:", "note", "mohon", "terima", "tanggal", "date", "invoice", "no.", "kasir", "cashier", "receipt", "total", "diskon", "disc", "subtotal", "jumlah", "bayar", "kembali"].contains { lower.hasPrefix($0) } || value.contains("/")
    }

    private static func merchantName(_ lines: [String]) -> String? {
        for line in lines.prefix(8) where !isMetadata(line) && line.contains(where: \.isLetter) {
            if captures(#"\d"#, line) == nil { return line }
        }
        for line in lines.prefix(8) {
            if let match = captures(#"(?:\big\b|instagram)\s*[:@]?\s*([A-Za-z][A-Za-z0-9_.]+)"#, line) { return "@" + match[0] }
        }
        return nil
    }

    private static func amount(_ text: String) -> Int64? {
        let canonical = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        guard let value = Int64(canonical), value >= 0, value <= Money.maximum else { return nil }
        return value
    }

    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func parsedDate(_ text: String) -> String? {
        let value: String?
        if let match = captures(#"\b(20[0-9]{2})-([01]?[0-9])-([0-3]?[0-9])\b"#, text), let month = Int(match[1]), let day = Int(match[2]) {
            value = String(format: "%@-%02d-%02d", match[0], month, day)
        } else if let match = captures(#"\b([0-3]?[0-9])[/.-]([01]?[0-9])[/.-](20[0-9]{2}|[0-9]{2})\b"#, text), let day = Int(match[0]), let month = Int(match[1]), let rawYear = Int(match[2]) {
            value = String(format: "%04d-%02d-%02d", rawYear < 100 ? 2000 + rawYear : rawYear, month, day)
        } else if let match = captures(#"\b([0-3]?[0-9])\s+(Januari|January|Jan|Februari|February|Feb|Maret|March|Mar|April|Apr|Mei|May|Juni|June|Jun|Juli|July|Jul|Agustus|August|Agu|Aug|September|Sep|Oktober|October|Okt|Oct|November|Nov|Desember|December|Des|Dec)\s+(20[0-9]{2})\b"#, text), let day = Int(match[0]) {
            let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "mei": 5, "may": 5, "jun": 6, "jul": 7, "agu": 8, "aug": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11, "des": 12, "dec": 12]
            value = months[String(match[1].lowercased().prefix(3))].map { String(format: "%@-%02d-%02d", match[2], $0, day) }
        } else { value = nil }
        guard let value else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return value
    }
}

public enum ItemSplitCalculator {
    private static func isValidRate(_ rate: Double) -> Bool {
        guard rate.isFinite, (0...100).contains(rate) else { return false }
        let basisPoints = rate * 100
        return abs(basisPoints - basisPoints.rounded()) < 0.00000001
    }

    public static func receipt(_ draft: ItemSplit, memberIDs: [String]) throws -> ReceiptCalculation {
        guard let settings = draft.settings, (1...20).contains(memberIDs.count), Set(memberIDs).count == memberIDs.count,
              [settings.serviceRate, settings.taxRate].allSatisfy(isValidRate) else { throw ContractError.validation }
        let denominator = Decimal(232792560)
        var bases = memberIDs.map { _ in Decimal(0) }
        var unassigned: [String] = []
        for item in draft.items {
            guard (0...999999).contains(item.quantity) else { throw ContractError.validation }
            let price = try Money.parse(item.unitPrice.isEmpty ? "0" : item.unitPrice, allowZero: true)
            let total = Decimal(price) * Decimal(item.quantity)
            let owners = memberIDs.filter { memberID in item.allocations.contains { $0.memberID == memberID && $0.quantity > 0 } }
            if owners.isEmpty { if total > 0 { unassigned.append(item.name.isEmpty ? "(tanpa nama)" : item.name) }; continue }
            for (index, memberID) in memberIDs.enumerated() where owners.contains(memberID) { bases[index] += total * (denominator / Decimal(owners.count)) }
        }
        func distribute(_ values: [Decimal], divisor: Decimal) -> [Int64] {
            func rounded(_ value: Decimal, mode: Decimal.RoundingMode) -> Int64 {
                var source = value; var output = Decimal()
                NSDecimalRound(&output, &source, 0, mode)
                return NSDecimalNumber(decimal: output).int64Value
            }
            var floors = values.map { rounded($0 / divisor, mode: .down) }
            let target = rounded(values.reduce(0, +) / divisor, mode: .plain)
            let order = values.indices.sorted {
                let first = values[$0] - Decimal(floors[$0]) * divisor
                let second = values[$1] - Decimal(floors[$1]) * divisor
                return first == second ? $0 < $1 : first > second
            }
            for index in order.prefix(Int(target - floors.reduce(0, +))) { floors[index] += 1 }
            return floors
        }
        let serviceRate = Decimal(Int64((settings.serviceRate * 100).rounded()))
        let taxRate = Decimal(Int64((settings.taxRate * 100).rounded()))
        let baseSum = bases.reduce(0, +)
        guard baseSum <= Decimal(Money.maximum) * denominator else { throw ContractError.validation }
        let discount = try Money.parse(draft.discount.isEmpty ? "0" : draft.discount, allowZero: true)
        let roundingText = draft.rounding ?? "0"
        let roundingMagnitude = try Money.parse(roundingText.hasPrefix("-") ? String(roundingText.dropFirst()) : roundingText, allowZero: true)
        let roundingSign: Int64 = roundingText.hasPrefix("-") ? -1 : 1
        guard baseSum == 0 || Decimal(discount) * denominator <= baseSum else { throw ContractError.validation }
        let ratioDivisor = baseSum == 0 ? denominator : baseSum
        let moneyBase = baseSum / denominator
        let adjustedDivisor = baseSum == 0 ? denominator : denominator * moneyBase
        let discounted = bases.map { $0 * (moneyBase == 0 ? 1 : moneyBase - Decimal(discount)) }
        let subtotals = distribute(bases, divisor: denominator)
        let discounts = distribute(bases.map { $0 * Decimal(discount) }, divisor: ratioDivisor)
        let roundings = distribute(bases.map { $0 * Decimal(roundingMagnitude) }, divisor: ratioDivisor).map { $0 * roundingSign }
        let services = distribute(discounted.map { settings.taxIncluded == true ? 0 : $0 * (serviceRate / 10000) }, divisor: adjustedDivisor)
        let taxes = distribute(discounted.map { settings.taxIncluded == true ? 0 : $0 * (settings.taxOnService ? 1 + serviceRate / 10000 : 1) * (taxRate / 10000) }, divisor: adjustedDivisor)
        let result = ReceiptCalculation(rows: memberIDs.indices.map { ReceiptShare(id: memberIDs[$0], subtotal: subtotals[$0], service: services[$0], tax: taxes[$0], discount: discounts[$0], rounding: roundings[$0]) }, unassigned: unassigned)
        guard result.total >= 0, result.total <= Money.maximum, result.rows.allSatisfy({ $0.total >= 0 }) else { throw ContractError.validation }
        return result
    }

    public static func calculate(_ draft: ItemSplit, memberIDs: [String]) throws -> ItemSplitResult {
        guard (2...20).contains(memberIDs.count), !memberIDs.contains(where: \.isEmpty), Set(memberIDs).count == memberIDs.count,
              (1...100).contains(draft.items.count), Set(draft.items.map(\.id)).count == draft.items.count else { throw ContractError.validation }
        if draft.settings != nil {
            guard draft.items.allSatisfy({ !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 160 && Set($0.allocations.map(\.memberID)).count == $0.allocations.count && $0.allocations.allSatisfy({ memberIDs.contains($0.memberID) && $0.quantity == 1 }) }) else { throw ContractError.validation }
            let calculation = try receipt(draft, memberIDs: memberIDs)
            guard calculation.unassigned.isEmpty, calculation.total > 0 else { throw ContractError.validation }
            return calculation.result
        }
        var subtotals = Dictionary(uniqueKeysWithValues: memberIDs.map { ($0, Int64(0)) })
        var subtotal: Int64 = 0
        for item in draft.items {
            guard !item.id.isEmpty, !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.name.count <= 160,
                  (1...999999).contains(item.quantity), Set(item.allocations.map(\.memberID)).count == item.allocations.count else { throw ContractError.validation }
            let price = try Money.parse(item.unitPrice)
            guard price <= Money.maximum / Int64(item.quantity) else { throw ContractError.validation }
            let lineTotal = price * Int64(item.quantity)
            guard subtotal <= Money.maximum - lineTotal else { throw ContractError.validation }
            subtotal += lineTotal
            var assigned = 0
            for allocation in item.allocations {
                guard subtotals[allocation.memberID] != nil, (0...999999).contains(allocation.quantity) else { throw ContractError.validation }
                assigned += allocation.quantity
                guard assigned <= item.quantity else { throw ContractError.validation }
                subtotals[allocation.memberID, default: 0] += price * Int64(allocation.quantity)
            }
            guard assigned == item.quantity else { throw ContractError.validation }
        }
        let tax = try Money.parse(draft.tax, allowZero: true)
        let service = try Money.parse(draft.service, allowZero: true)
        let discount = try Money.parse(draft.discount, allowZero: true)
        guard tax <= Money.maximum - subtotal, service <= Money.maximum - subtotal - tax else { throw ContractError.validation }
        let gross = subtotal + tax + service
        guard discount < gross else { throw ContractError.validation }
        let total = gross - discount
        var shares: [String: Int64] = [:]
        var remainders: [(id: String, value: Decimal, order: Int)] = []
        for (order, memberID) in memberIDs.enumerated() {
            let product = Decimal(subtotals[memberID]!) * Decimal(total)
            let quotient = product / Decimal(subtotal)
            var rounded = Decimal()
            var mutable = quotient
            NSDecimalRound(&rounded, &mutable, 0, .down)
            let amount = NSDecimalNumber(decimal: rounded).int64Value
            shares[memberID] = amount
            remainders.append((memberID, product - Decimal(amount) * Decimal(subtotal), order))
        }
        let remaining = total - shares.values.reduce(0, +)
        let ordered = remainders.sorted { $0.value == $1.value ? $0.order < $1.order : $0.value > $1.value }
        for index in 0..<Int(remaining) { shares[ordered[index].id, default: 0] += 1 }
        return ItemSplitResult(total: String(total), shares: shares.mapValues(String.init))
    }
}
