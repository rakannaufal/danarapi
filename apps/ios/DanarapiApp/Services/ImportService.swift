import CryptoKit
import Foundation
import PDFKit
import UIKit
import ImageIO
import Security
@preconcurrency import Vision

enum ImportService {
    static func recoverLocalReview(_ item: ReviewItem) -> ReviewItem? {
        guard item.source == .image || item.source == .pdfText, item.amount.confidence == .low,
              let text = item.rawReference, !text.hasPrefix("Data hasil ekstraksi otomatis"),
              item.receipt?.items.isEmpty != false else { return nil }
        let recovered = ReceiptTextParser.parse(text)
        guard !recovered.items.isEmpty else { return nil }
        var updated = reviewFromReceipt(recovered, source: item.source, existing: item)
        updated.amount.confidence = .low; updated.merchant.confidence = .low
        updated.rawReference = text
        return updated
    }

    static func receiptDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    static func reviewFromReceipt(_ receipt: ScannedReceipt, source: ReviewSource, attachmentName: String? = nil, existing: ReviewItem? = nil) -> ReviewItem {
        let empty = ExtractedField(value: nil, confidence: .low, evidenceSpan: nil, sourceType: source)
        var item = existing ?? ReviewItem(id: UUID().uuidString, source: source, status: .pending, amount: empty, merchant: empty, date: empty, rawReference: nil, duplicateCandidateID: nil, attachmentName: attachmentName, createdAt: .now)
        let validation = receipt.validation
        item.receipt = receipt
        item.receiptLines = receipt.items.map { ReceiptLine(name: $0.name, quantity: $0.qty, unitPrice: $0.unitPrice.map(String.init) ?? "") }
        item.amount = ExtractedField(value: receipt.grandTotal.map(String.init), confidence: receipt.grandTotal == nil ? .low : validation.passed ? .high : .medium, evidenceSpan: "Total tercetak pada struk. Periksa dengan foto asli.", sourceType: source)
        item.merchant = ExtractedField(value: receipt.merchant, confidence: receipt.merchant == nil ? .low : .medium, evidenceSpan: receipt.merchant, sourceType: source)
        item.date = ExtractedField(value: receipt.date, confidence: receiptDate(receipt.date) == nil ? .low : .medium, evidenceSpan: receipt.date, sourceType: source)
        item.rawReference = "Data hasil ekstraksi otomatis (bukan transkripsi mentah):\n" + (receipt.items.map { "\($0.name) · \($0.qty) × \($0.unitPrice.map(String.init) ?? "?") = \($0.lineTotal.map(String.init) ?? "?")" }).joined(separator: "\n")
        return item
    }

    @MainActor static func receiptImagesFromPDF(_ data: Data) throws -> [UIImage] {
        guard data.count <= 5 * 1_024 * 1_024, let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw AppError.validation("PDF tidak valid atau melebihi 5 MB.")
        }
        guard document.pageCount <= 3 else { throw AppError.validation("Scan PDF maksimal tiga halaman. Pisahkan halaman struk terlebih dahulu.") }
        return try (0..<document.pageCount).map { index in
            guard let page = document.page(at: index) else { throw AppError.validation("Halaman PDF tidak dapat dibaca.") }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { throw AppError.validation("Ukuran halaman PDF tidak valid.") }
            let scale = min(2, 1600 / max(bounds.width, bounds.height))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
                page.draw(with: .mediaBox, to: context.cgContext)
            }
        }
    }

    @MainActor static func readReceipt(images: [UIImage], source: ReviewSource, attachmentName: String?, cloudScan: (([ReceiptScanImage]) async throws -> ReceiptScanResponse)? = nil) async throws -> ReviewItem {
        if let cloudScan {
            let compressed = try images.map { try compressedReceipt($0) }
            let response = try await cloudScan(compressed.map(\.0))
            guard response.status == "ok", let receipt = response.data else { throw AppError.validation(response.message) }
            return reviewFromReceipt(receipt, source: source, attachmentName: attachmentName)
        }
        var texts: [String] = []
        for image in images { texts.append(try await recognizedText(in: image)) }
        let text = texts.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.validation("Struk belum terbaca. Foto ulang dengan cahaya cukup.") }
        return reviewFromText(text, source: source, attachmentName: attachmentName)
    }
    @MainActor static func receiptImage(from data: Data) throws -> UIImage {
        guard data.count <= 20 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw AppError.validation("Foto tidak dapat dibaca atau lebih dari 20 MB.") }
        return UIImage(cgImage: image)
    }
    @MainActor static func compressedReceipt(_ image: UIImage) throws -> (ReceiptScanImage, UIImage) {
        var scale = min(1, 1600 / max(image.size.width, image.size.height))
        for attempt in 0..<5 {
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let preview = UIGraphicsImageRenderer(size: size, format: format).image { context in UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size)) }
            if let data = preview.jpegData(compressionQuality: 0.8 - Double(attempt) * 0.08), data.count <= 1_300_000 { return (ReceiptScanImage(data: data.base64EncodedString()), preview) }
            scale *= 0.8
        }
        throw AppError.validation("Foto masih terlalu besar. Potong area di luar struk lalu coba lagi.")
    }
    static func reviewFromQR(_ raw: String, attachmentName: String? = nil) throws -> ReviewItem {
        let payload = try QRISParser.parse(raw)
        return ReviewItem(
            id: UUID().uuidString,
            source: .qris,
            status: .pending,
            amount: ExtractedField(value: payload.amount.map(String.init), confidence: payload.amount == nil ? .low : .high, evidenceSpan: payload.amount.map { "Tag 54: \($0)" }, sourceType: .qris),
            merchant: ExtractedField(value: payload.merchant, confidence: payload.merchant == nil ? .low : .medium, evidenceSpan: payload.merchant, sourceType: .qris),
            date: ExtractedField(value: nil, confidence: .low, evidenceSpan: nil, sourceType: .qris),
            rawReference: payload.reference.map(hashReference),
            duplicateCandidateID: nil,
            attachmentName: attachmentName,
            createdAt: .now
        )
    }

    static func reviewFromText(_ text: String, source: ReviewSource = .pastedText, attachmentName: String? = nil) -> ReviewItem {
        if source == .image || source == .pdfText {
            var item = reviewFromReceipt(ReceiptTextParser.parse(text), source: source, attachmentName: attachmentName)
            item.amount.confidence = .low; item.merchant.confidence = .low
            item.amount.evidenceSpan = "Pembacaan lokal. Periksa nominal dengan foto asli."
            item.rawReference = text
            return item
        }
        let amountCandidates = extractAmounts(text)
        let explicitTotal = explicitTotalAmount(text)
        let selected = explicitTotal ?? (amountCandidates.count == 1 ? amountCandidates.first : nil)
        let date = extractDate(text)
        let merchant = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReviewItem(
            id: UUID().uuidString,
            source: source,
            status: .pending,
            amount: ExtractedField(value: selected.map(String.init), confidence: source == .image ? .low : explicitTotal != nil ? .high : selected == nil ? .low : .medium, evidenceSpan: selected.map { "Nominal: \($0)" }, sourceType: source),
            merchant: ExtractedField(value: merchant?.isEmpty == false ? merchant : nil, confidence: .low, evidenceSpan: merchant, sourceType: source),
            date: ExtractedField(value: date.map { ISO8601DateFormatter().string(from: $0) }, confidence: date == nil ? .low : .medium, evidenceSpan: nil, sourceType: source),
            rawReference: nil,
            duplicateCandidateID: nil,
            attachmentName: attachmentName,
            createdAt: .now,
            receiptLines: ReceiptParser.lines(from: text)
        )
    }

    static func recognizedText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { throw AppError.validation("Gambar tidak dapat dibaca.") }
        let orientation: CGImagePropertyOrientation = switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    request.recognitionLanguages = ["en-US"]
                    try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
                    let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    var rows: [(y: CGFloat, fragments: [(x: CGFloat, text: String)])] = []
                    for observation in observations {
                        guard let text = observation.topCandidates(1).first?.string else { continue }
                        let fragment = (x: observation.boundingBox.minX, text: text)
                        if let last = rows.last, abs(last.y - observation.boundingBox.midY) < 0.012 { rows[rows.count - 1].fragments.append(fragment) }
                        else { rows.append((observation.boundingBox.midY, [fragment])) }
                    }
                    continuation.resume(returning: rows.map { $0.fragments.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }.joined(separator: "\n"))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func reviewFromPDF(data: Data, name: String) throws -> ReviewItem {
        guard data.count <= 5 * 1_024 * 1_024, let document = PDFDocument(data: data) else { throw AppError.validation("PDF tidak valid atau melebihi 5 MB.") }
        let text = (0..<min(document.pageCount, 30)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ReviewItem(id: UUID().uuidString, source: .pdfText, status: .pending,
                amount: ExtractedField(value: nil, confidence: .low, evidenceSpan: nil, sourceType: .pdfText),
                merchant: ExtractedField(value: nil, confidence: .low, evidenceSpan: nil, sourceType: .pdfText),
                date: ExtractedField(value: nil, confidence: .low, evidenceSpan: nil, sourceType: .pdfText),
                rawReference: hashData(data), duplicateCandidateID: nil, attachmentName: name, createdAt: .now)
        }
        var item = reviewFromText(text, source: .pdfText, attachmentName: name)
        item.rawReference = hashData(data)
        return item
    }

    static func qrStrings(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw AppError.validation("Gambar tidak dapat dibaca.") }
        let orientation: CGImagePropertyOrientation = switch image.imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (request.results as? [VNBarcodeObservation])?.filter { $0.symbology == .qr }.compactMap(\.payloadStringValue) ?? []
                continuation.resume(returning: values)
            }
            request.symbologies = [.qr]
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request]) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func duplicateCandidate(for item: ReviewItem, transactions: [FinanceTransaction]) -> String? {
        guard let amountText = item.amount.value, let amount = Int64(amountText) else { return nil }
        let merchant = normalize(item.merchant.value ?? "")
        let reviewDate = receiptDate(item.date.value ?? item.receipt?.date) ?? item.createdAt
        return transactions.first { transaction in
            guard transaction.amount == amount else { return false }
            let closeDate = abs(transaction.occurredAt.timeIntervalSince(reviewDate)) <= 2 * 86_400
            let candidateMerchant = normalize(transaction.merchant ?? "")
            let sameMerchant = merchant.isEmpty || (!candidateMerchant.isEmpty && (candidateMerchant.contains(merchant) || merchant.contains(candidateMerchant)))
            return closeDate && sameMerchant
        }?.id
    }

    private static func extractAmounts(_ text: String) -> [Int64] {
        let pattern = #"(?i)(?:rp\s*)?([0-9]{1,3}(?:[.][0-9]{3})+|[0-9]{4,12})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
            return Int64(text[swiftRange].replacingOccurrences(of: ".", with: ""))
        }.filter { $0 > 0 && $0 <= Money.maximum }
    }

    private static func explicitTotalAmount(_ text: String) -> Int64? {
        let pattern = #"(?im)^\s*(?:grand\s+)?total(?:\s+pembayaran)?\s*[: ]\s*(?:rp\s*)?([0-9.]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int64(text[range].replacingOccurrences(of: ".", with: ""))
    }

    private static func extractDate(_ text: String) -> Date? {
        let pattern = #"\b([0-3]?[0-9])[/.-]([01]?[0-9])[/.-](20[0-9]{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let dayRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let yearRange = Range(match.range(at: 3), in: text)
        else { return nil }
        var components = DateComponents()
        components.day = Int(text[dayRange]); components.month = Int(text[monthRange]); components.year = Int(text[yearRange])
        components.timeZone = TimeZone(identifier: "Asia/Jakarta")
        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func hashReference(_ value: String) -> String { hashData(Data(value.utf8)) }
    private static func hashData(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func normalize(_ value: String) -> String { value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "id_ID")).filter { $0.isLetter || $0.isNumber } }
}

struct DevelopmentReceiptScanConfiguration: Sendable {
    let url: URL
    let token: String
    let certificateHash: String

    init?(host: String, port: String, token: String, certificateHash: String) {
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, host.split(separator: ".").count == 4,
              octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])),
              let portNumber = Int(port), (1024...65535).contains(portNumber),
              token.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              certificateHash.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              let url = URL(string: "https://\(host):\(portNumber)/scan") else { return nil }
        self.url = url; self.token = token; self.certificateHash = certificateHash
    }

    static var bundled: DevelopmentReceiptScanConfiguration? {
        #if DEBUG
        let bundle = Bundle.main
        return DevelopmentReceiptScanConfiguration(host: bundle.object(forInfoDictionaryKey: "NATIVE_SCAN_HOST") as? String ?? "", port: bundle.object(forInfoDictionaryKey: "NATIVE_SCAN_PORT") as? String ?? "", token: bundle.object(forInfoDictionaryKey: "NATIVE_SCAN_TOKEN") as? String ?? "", certificateHash: bundle.object(forInfoDictionaryKey: "NATIVE_SCAN_CERT_SHA256") as? String ?? "")
        #else
        return nil
        #endif
    }

    func scan(_ images: [ReceiptScanImage]) async throws -> ReceiptScanResponse {
        let delegate = DevelopmentReceiptScanDelegate(configuration: self)
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 110; options.timeoutIntervalForResource = 115
        options.urlCache = nil
        let session = URLSession(configuration: options, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-danarapi-native-scan")
        request.httpBody = try JSONEncoder().encode(ReceiptScanRequest(images: images))
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, [200, 400, 429].contains(http.statusCode), data.count <= 1_000_000 else {
                throw AppError.validation("Pembaca struk belum tersambung. Jalankan scanner pada Mac, lalu build ulang iOS Debug.")
            }
            return try JSONDecoder().decode(ReceiptScanResponse.self, from: data)
        } catch let error as AppError { throw error }
        catch {
            throw AppError.validation("Pembaca struk pada Mac tidak dapat dijangkau. Pastikan server aktif, Wi-Fi sama, dan izin Jaringan Lokal tersedia. Foto tetap tersedia untuk dicoba lagi.")
        }
    }
}

private final class DevelopmentReceiptScanDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let configuration: DevelopmentReceiptScanConfiguration
    init(configuration: DevelopmentReceiptScanConfiguration) { self.configuration = configuration }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == configuration.url.host,
              challenge.protectionSpace.port == configuration.url.port,
              let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let bytes = SecCertificateCopyData(certificate) as Data
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard hash == configuration.certificateHash else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
