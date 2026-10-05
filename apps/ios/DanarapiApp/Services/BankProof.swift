import Foundation

struct BankProofRequest: Encodable, Sendable {
    let purpose = "bank_proof"
    let images: [ReceiptScanImage]
    let text: String?
    var retryID: String? = nil
}

struct BankProofResponse: Decodable, Sendable {
    let status: String
    let proof: BankProof?
    let message: String?
}

struct BankProof: Codable, Sendable {
    let amount: Int64?
    let merchant: String?
    let recipient: String?
    let date: String?
    let time: String?
    let utcOffset: String?
    let fee: Int64?
    let total: Int64?
    let currency: String?
    let provider: String?
    let reference: String?
    let transactionType: String
    let transactionStatus: String
    let unreadableFields: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case amount, merchant, recipient, date, time, fee, total, currency, provider, reference, warnings
        case utcOffset = "utc_offset", transactionType = "transaction_type", transactionStatus = "transaction_status", unreadableFields = "unreadable_fields"
    }

    var eligibleAmount: Int64? {
        guard transactionStatus == "success", currency == "IDR", let amount, amount > 0, amount <= Money.maximum,
              !unreadableFields.contains("amount") else { return nil }
        if let fee, fee < 0 || fee > Money.maximum { return nil }
        if let total, total < 1 || total > Money.maximum { return nil }
        if let fee, let total, total != amount + fee { return nil }
        return amount
    }

    func occurredAt(timezone: String) -> Date? {
        guard let date, !unreadableFields.contains("date") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "Asia/Jakarta")
        if let utcOffset {
            guard utcOffset.range(of: #"^[+-](?:0[0-9]|1[0-3]):[0-5][0-9]$|^[+-]14:00$"#, options: .regularExpression) != nil else { return nil }
            let parts = utcOffset.dropFirst().split(separator: ":")
            guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
            formatter.timeZone = TimeZone(secondsFromGMT: (utcOffset.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60))
        }
        let clock = time ?? "00:00:00"
        let value = date + "T" + clock + (utcOffset ?? "")
        formatter.dateFormat = utcOffset == nil ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd'T'HH:mm:ssXXX"
        guard let result = formatter.date(from: value) else { return nil }
        let rendered = formatter.string(from: result)
        guard rendered == value || (utcOffset == "+00:00" && rendered == date + "T" + clock + "Z") else { return nil }
        return result
    }

    func review(_ record: SharedInboxRecord, timezone: String) -> ReviewItem {
        let source: ReviewSource = record.mime == "application/pdf" ? .pdfText : record.mime == "text/plain" ? .pastedText : .image
        let field: (String?) -> ExtractedField = { value in ExtractedField(value: value, confidence: .low, evidenceSpan: "Dibaca AI dari bukti asli; periksa sebelum mencatat.", sourceType: source) }
        var lines = ["Bukti dari Share · pembacaan AI", "Nominal dan biaya admin dipisahkan. Hasil belum menjadi transaksi."]
        if let provider { lines.append("Penyedia: " + provider) }
        if let recipient { lines.append("Penerima: " + recipient) }
        if let fee { lines.append("Biaya admin: " + fee.idr) }
        if let total { lines.append("Total debit: " + total.idr) }
        if let currency { lines.append("Mata uang: " + currency) }
        lines.append("Status: " + statusLabel)
        lines.append("Jenis pada bukti: " + typeLabel)
        if let reference { lines.append("Referensi: " + reference) }
        if let date { lines.append("Tanggal tercetak: " + date + " " + (time ?? "(jam belum terbaca)")) }
        lines.append(utcOffset.map { "Zona waktu: " + $0 } ?? "Zona waktu tidak tercetak; menggunakan \(timezone).")
        lines.append(contentsOf: warnings)
        if !unreadableFields.isEmpty { lines.append("Bagian belum pasti: " + unreadableFields.joined(separator: ", ")) }
        let details = lines.joined(separator: "\n\n")
        return ReviewItem(id: record.id, source: source, status: .pending,
                          amount: field(eligibleAmount.map(String.init)), merchant: field(merchant ?? recipient),
                          date: field(occurredAt(timezone: timezone).map { ISO8601DateFormatter().string(from: $0) }),
                          rawReference: details, duplicateCandidateID: nil,
                          attachmentName: source == .pastedText ? nil : record.name, createdAt: record.createdAt)
    }

    var statusLabel: String { switch transactionStatus { case "success": "Berhasil"; case "failed": "Gagal / dibatalkan"; case "pending": "Masih diproses"; default: "Belum pasti" } }
    var typeLabel: String { switch transactionType { case "payment": "Pembayaran"; case "transfer": "Transfer"; case "income": "Penerimaan"; default: "Belum pasti" } }
}
