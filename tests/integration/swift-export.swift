import Foundation

extension JSONEncoder {
    static var danarapi: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

@main struct ExportParityRunner {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: text) { return value }
            formatter.formatOptions = [.withInternetDateTime]
            guard let value = formatter.date(from: text) else { throw AppError.validation("Invalid parity timestamp") }
            return value
        }
        let snapshot = try decoder.decode(DashboardSnapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let values = ExportService.exportCSVs(snapshot: snapshot)
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]))
    }
}
