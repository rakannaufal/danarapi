import Foundation

struct QRISPayload: Equatable, Sendable {
    let merchant: String?
    let city: String?
    let amount: Int64?
    let reference: String?
}

enum QRISParser {
    static func parse(_ raw: String) throws -> QRISPayload {
        guard raw.hasPrefix("000201"), validateCRC(raw) else {
            throw AppError(code: "VALIDATION", message: raw.hasPrefix("000201") ? "CRC QRIS tidak valid." : "QR tidak didukung.", requestID: nil, details: [:])
        }
        let fields = try tlv(raw)
        guard fields["00"] == "01", fields.keys.contains(where: { (26...51).contains(Int($0) ?? -1) }) else {
            throw AppError(code: "VALIDATION", message: "QR bukan QRIS Merchant Presented Mode yang didukung.", requestID: nil, details: [:])
        }
        let amount: Int64?
        if let text = fields["54"] {
            let parts = text.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, let parsed = Int64(parts[0]), parsed > 0, parsed <= Money.maximum,
                  parts.count == 1 || parts[1].allSatisfy({ $0 == "0" })
            else { throw AppError.validation("Nominal QRIS bukan Rupiah bulat yang didukung.") }
            amount = parsed
        } else {
            amount = nil
        }
        let additional = fields["62"].flatMap { try? tlv($0) }
        return QRISPayload(
            merchant: fields["59"]?.trimmingCharacters(in: .whitespaces),
            city: fields["60"]?.trimmingCharacters(in: .whitespaces),
            amount: amount,
            reference: additional?["05"]
        )
    }

    static func validateCRC(_ raw: String) -> Bool {
        guard raw.count >= 8, raw.suffix(8).prefix(4) == "6304" else { return false }
        let expected = String(raw.suffix(4)).uppercased()
        let content = String(raw.dropLast(4))
        return String(format: "%04X", crc16(content.utf8)) == expected
    }

    private static func tlv(_ raw: String) throws -> [String: String] {
        let bytes = Array(raw.utf8)
        var index = 0
        var result: [String: String] = [:]
        while index < bytes.count {
            guard index + 4 <= bytes.count,
                  let tag = String(bytes: bytes[index..<(index + 2)], encoding: .utf8),
                  let lengthText = String(bytes: bytes[(index + 2)..<(index + 4)], encoding: .utf8),
                  let length = Int(lengthText), index + 4 + length <= bytes.count,
                  let value = String(bytes: bytes[(index + 4)..<(index + 4 + length)], encoding: .utf8)
            else { throw AppError.validation("Struktur QR tidak valid.") }
            result[tag] = value
            index += 4 + length
        }
        return result
    }

    private static func crc16<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }
}
