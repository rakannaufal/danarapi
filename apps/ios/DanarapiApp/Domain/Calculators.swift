import CryptoKit
import Foundation
import JavaScriptCore

struct CalculatorCatalog: Decodable, Sendable {
    let version: String
    let categories: [CalculatorCategory]
    let sources: [String: CalculatorSource]
    let calculators: [CalculatorDefinition]

    static let bundled: CalculatorCatalog? = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalculatorCatalog.self, from: data)
    }()
}

struct CalculatorCategory: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let icon: String
    var symbol: String {
        switch icon { case "tag": "tag"; case "house": "house"; case "wallet": "wallet.bifold"; case "bank": "building.columns"; case "chart": "chart.xyaxis.line"; case "moon": "moon.stars"; case "people": "person.2"; default: "calculator" }
    }
}

struct CalculatorDefinition: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let category: String
    let description: String
    let method: String
    let fields: [CalculatorField]
    let notes: [String]
    let references: [String]
    var isIslamic: Bool { !references.isEmpty }

    func defaults() -> [String: String] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: .now)
        return Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.defaultValue == "today" ? today : $0.defaultValue) })
    }
}

struct CalculatorField: Decodable, Identifiable, Sendable {
    struct Option: Decodable, Identifiable, Sendable { let value: String; let label: String; var id: String { value } }
    enum Visibility: Decodable, Sendable {
        case single(String), multiple([String])
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .single(value) }
            else { self = .multiple(try container.decode([String].self)) }
        }
        func matches(_ value: String?) -> Bool { switch self { case let .single(expected): value == expected; case let .multiple(values): value.map(values.contains) ?? false } }
    }
    let key: String
    let label: String
    let kind: String
    let defaultValue: String
    let unit: String?
    let options: [Option]?
    let visible: [String: Visibility]?
    var id: String { key }
    enum CodingKeys: String, CodingKey { case key, label, kind, defaultValue = "default", unit, options, visible }
    func isVisible(_ inputs: [String: String]) -> Bool { visible?.allSatisfy { $0.value.matches(inputs[$0.key]) } ?? true }
}

struct CalculatorSource: Decodable, Sendable {
    let title: String
    let status: String
    let url: String
    let meaning: String
}

struct CalculatorResult: Decodable, Sendable {
    struct Row: Decodable, Sendable {
        let label: String
        let value: String
        let kind: String
        let unit: String
        var formatted: String {
            if kind == "text" { return value }
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "id_ID")
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = kind == "money" ? 0 : 6
            let number = NSDecimalNumber(string: value, locale: Locale(identifier: "en_US_POSIX"))
            let formatted = formatter.string(from: number) ?? value
            if kind == "money" { return "Rp" + formatted }
            if kind == "percent" { return formatted + "%" }
            return formatted + (unit.isEmpty ? "" : " " + unit)
        }
    }
    struct Period: Decodable, Sendable { let period: String; let amount: String; let detail: String }
    let calculatorID: String
    let headline: String
    let status: String
    let rows: [Row]
    let warnings: [String]
    let steps: [String]
    let schedule: [Period]
    let primaryAmount: String?
    let primaryLabel: String?
    func summary(_ definition: CalculatorDefinition) -> String {
        ([definition.title, headline] + rows.map { "\($0.label): \($0.formatted)" } + ["", "Metode: " + definition.method] + warnings).joined(separator: "\n")
    }
}

@MainActor
final class CalculatorEngine {
    static let shared = CalculatorEngine()
    private let context: JSContext?
    private let catalogJSON: String?
    struct Response: Decodable { let result: CalculatorResult?; let error: String? }

    private init() {
        context = JSContext()
        catalogJSON = Bundle.main.url(forResource: "catalog", withExtension: "json").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        if let url = Bundle.main.url(forResource: "engine", withExtension: "js"), let script = try? String(contentsOf: url, encoding: .utf8) { context?.evaluateScript(script) }
    }

    func calculate(_ definition: CalculatorDefinition, inputs: [String: String]) throws -> CalculatorResult {
        guard let context, let catalogJSON,
              let function = context.objectForKeyedSubscript("DanarapiCalculatorEngine")?.objectForKeyedSubscript("calculateJSON"), !function.isUndefined else {
            throw AppError.validation("Mesin kalkulator belum tersedia. Buka ulang aplikasi.")
        }
        context.exception = nil
        let data = try JSONEncoder().encode(inputs)
        guard let json = String(data: data, encoding: .utf8), let responseJSON = function.call(withArguments: [catalogJSON, definition.id, json])?.toString(),
              context.exception == nil, let responseData = responseJSON.data(using: .utf8) else { throw AppError.validation("Perhitungan belum dapat diselesaikan.") }
        let response = try JSONDecoder().decode(Response.self, from: responseData)
        if let error = response.error { throw AppError.validation(error) }
        guard let result = response.result else { throw AppError.validation("Hasil belum tersedia.") }
        return result
    }
}

struct CalculatorHistoryRecord: Codable, Identifiable, Sendable {
    let id: String
    let calculatorID: String
    let title: String
    let inputs: [String: String]
    let createdAt: Date
}

@MainActor
enum CalculatorPreferences {
    private static func ownerKey(_ owner: String) -> String { SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func favorites(owner: String) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: "calculator.favorites." + ownerKey(owner)) ?? []) }
    static func saveFavorites(_ favorites: Set<String>, owner: String) { UserDefaults.standard.set(Array(favorites).sorted(), forKey: "calculator.favorites." + ownerKey(owner)) }
    private static func historyURL(owner: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Calculators", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var folder = base
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return base.appendingPathComponent(ownerKey(owner) + ".json")
    }
    static func history(owner: String) -> [CalculatorHistoryRecord] {
        guard let url = try? historyURL(owner: owner), let data = try? Data(contentsOf: url), let records = try? JSONDecoder().decode([CalculatorHistoryRecord].self, from: data) else { return [] }
        return Array(records.prefix(20))
    }
    static func saveHistory(_ records: [CalculatorHistoryRecord], owner: String) throws {
        try JSONEncoder().encode(Array(records.prefix(20))).write(to: historyURL(owner: owner), options: [.atomic, .completeFileProtection])
    }
}
