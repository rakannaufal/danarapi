import Foundation
import PDFKit

enum BankReceiptParser {
    struct Result: Sendable {
        var amount: Int64?
        var merchant: String?
        var date: Date?
        var warning: String?
    }

    static func parse(_ text: String) -> Result {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var amounts: Set<Int64> = []
        var merchants: Set<String> = []
        var dates: Set<Date> = []
        var blocked = false
        var unreadableAmount = false
        for (index, line) in lines.enumerated() {
            if line.range(of: #"(?i)\b(gagal|dibatalkan|failed|cancelled|pending|diproses|menunggu)\b"#, options: .regularExpression) != nil { blocked = true }
            // Only transaction labels count: balances, account numbers and fees never do.
            if let tail = capture(#"(?i)^(?:nominal(?:\s+(?:transfer|transaksi|pembayaran))?|jumlah\s+(?:transfer|transaksi|pembayaran)|transfer\s+amount|transaction\s+amount|amount)\s*[:\-]?\s*(.*)$"#, in: line) {
                let value = tail.isEmpty && index + 1 < lines.count ? lines[index + 1] : tail
                if let amount = rupiah(value) { amounts.insert(amount) }
                else { unreadableAmount = true }
            }
            if let tail = capture(#"(?i)^(?:nama\s+(?:penerima|merchant|toko)|penerima|merchant|recipient|beneficiary)\s*[:\-]?\s*(.*)$"#, in: line) {
                let value = tail.isEmpty && index + 1 < lines.count ? lines[index + 1] : tail
                if !value.isEmpty, value.count <= 160, value.contains(where: \.isLetter), value.range(of: #"(?i)^(nominal|jumlah|tanggal|rekening|bank|status|biaya)\b"#, options: .regularExpression) == nil { merchants.insert(value) }
            }
            if let dateText = capture(#"(?i)^(?:tanggal(?:\s+transaksi)?|waktu(?:\s+transaksi)?|date)\s*[:\-]?\s*(.*)$"#, in: line) {
                let value = dateText.isEmpty && index + 1 < lines.count ? lines[index + 1] : dateText
                if let date = date(value) { dates.insert(date) }
            }
        }
        let warning = blocked ? "Bukti menyebut gagal, dibatalkan, atau belum selesai. Pastikan transaksi berhasil sebelum mencatat." : amounts.count != 1 || unreadableAmount ? "Nominal belum pasti. Saldo, nomor rekening, total debit, dan biaya admin tidak dipilih otomatis." : "Periksa penerima, nominal, tanggal, serta biaya admin. Transfer antar akun sendiri dicatat melalui Transfer."
        return Result(amount: !blocked && !unreadableAmount && amounts.count == 1 ? amounts.first : nil, merchant: merchants.count == 1 ? merchants.first : nil, date: dates.count == 1 ? dates.first : nil, warning: warning)
    }

    static func rupiah(_ value: String) -> Int64? {
        let text = value.replacingOccurrences(of: #"(?i)^(?:rp\.?|idr)\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let integer: String
        if text.range(of: #"^[0-9]{1,3}(?:\.[0-9]{3})+(?:,00)?$"#, options: .regularExpression) != nil {
            integer = text.replacingOccurrences(of: ",00", with: "").replacingOccurrences(of: ".", with: "")
        } else if text.range(of: #"^[0-9]{1,3}(?:,[0-9]{3})+(?:\.00)?$"#, options: .regularExpression) != nil {
            integer = text.replacingOccurrences(of: ".00", with: "").replacingOccurrences(of: ",", with: "")
        } else if text.range(of: #"^[0-9]{1,12}(?:[,.]00)?$"#, options: .regularExpression) != nil {
            integer = text.replacingOccurrences(of: #"[,.]00$"#, with: "", options: .regularExpression)
        } else { return nil }
        guard let amount = Int64(integer), amount > 0, amount <= Money.maximum else { return nil }
        return amount
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }
    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.isLenient = false
        for format in ["dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy HH:mm", "dd/MM/yyyy", "dd-MM-yyyy HH:mm:ss", "dd-MM-yyyy", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "dd MMM yyyy HH:mm:ss", "dd MMM yyyy HH:mm", "dd MMM yyyy", "dd MMMM yyyy HH:mm:ss", "dd MMMM yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text), formatter.string(from: date).lowercased() == text.lowercased() { return date }
        }
        return nil
    }
}

enum SharedReceiptReader {
    @MainActor static func aiRequest(_ record: SharedInboxRecord, data: Data) throws -> BankProofRequest {
        if record.mime == "text/plain" {
            guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SharedInboxError.invalid }
            return BankProofRequest(images: [], text: text)
        }
        let images = record.mime == "application/pdf" ? try ImportService.receiptImagesFromPDF(data) : [try ImportService.receiptImage(from: data)]
        return BankProofRequest(images: try images.map { try ImportService.compressedReceipt($0).0 }, text: nil)
    }

    @MainActor static func read(_ record: SharedInboxRecord, data: Data) async -> ReviewItem {
        let source: ReviewSource = record.mime == "application/pdf" ? .pdfText : record.mime == "text/plain" ? .pastedText : .image
        var text = ""
        var issue: String?
        do {
            if source == .pastedText { text = String(data: data, encoding: .utf8) ?? "" }
            else if source == .pdfText {
                guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount > 0, pdf.pageCount <= 3 else { throw AppError.validation("PDF harus terbuka dan maksimal tiga halaman. Isi nominal secara manual bila tidak terbaca.") }
                text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    for image in try ImportService.receiptImagesFromPDF(data) { text += try await ImportService.recognizedText(in: image) + "\n" }
                }
            } else { text = try await ImportService.recognizedText(in: ImportService.receiptImage(from: data)) }
        } catch { issue = (error as? AppError)?.message ?? error.localizedDescription }
        // Context is preserved as evidence; never let a caption override the receipt amount.
        let parsed = BankReceiptParser.parse(text)
        let field: (String?) -> ExtractedField = { value in ExtractedField(value: value, confidence: .low, evidenceSpan: "Pembacaan lokal bukti Share. Periksa dengan bukti asli.", sourceType: source) }
        let evidence = ["Bukti dari Share · pembacaan lokal", issue, parsed.warning, text.isEmpty ? nil : String(text.prefix(40_000)), record.context.isEmpty ? nil : "Teks pendamping:\n" + record.context].compactMap { $0 }.joined(separator: "\n\n")
        return ReviewItem(id: record.id, source: source, status: .pending, amount: field(parsed.amount.map(String.init)), merchant: field(parsed.merchant), date: field(parsed.date.map { ISO8601DateFormatter().string(from: $0) }), rawReference: evidence, duplicateCandidateID: nil, attachmentName: source == .pastedText ? nil : record.name, createdAt: record.createdAt)
    }
}
