import Foundation

public enum ContractError: Error, Equatable {
    case validation
}

public enum Money {
    public static let maximum: Int64 = 999_999_999_999

    public static func parse(_ value: String, allowZero: Bool = false) throws -> Int64 {
        guard !value.isEmpty,
              value.allSatisfy(\.isNumber),
              value == "0" || !value.hasPrefix("0"),
              value.count <= 12,
              let parsed = Int64(value),
              parsed <= maximum,
              allowZero || parsed > 0
        else {
            throw ContractError.validation
        }
        return parsed
    }

    public static func encode(_ value: Int64) throws -> String {
        guard value >= 0, value <= maximum else { throw ContractError.validation }
        return String(value)
    }
}

public enum MoneyInputFormat {
    public static func raw(_ text: String, signed: Bool = false) -> String {
        let negative = signed && text.trimmingCharacters(in: .whitespaces).hasPrefix("-")
        let digits = text.filter { $0 >= "0" && $0 <= "9" }
        let trimmed = digits.drop(while: { $0 == "0" })
        let canonical = String((trimmed.isEmpty && !digits.isEmpty ? "0" : String(trimmed)).prefix(12))
        return (negative && canonical != "0" ? "-" : "") + canonical
    }

    public static func display(_ text: String, signed: Bool = false) -> String {
        let canonical = raw(text, signed: signed)
        let digits = canonical.filter { $0 != "-" }
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index).isMultiple(of: 3) { grouped += "." }
            grouped.append(digit)
        }
        return (canonical.hasPrefix("-") ? "-" : "") + grouped
    }

    public static func caret(_ text: String, position: Int, formatted: String) -> Int {
        let count = text.prefix(position).filter { $0.isNumber || $0 == "-" }.count
        guard count > 0 else { return 0 }
        var seen = 0
        for (index, character) in formatted.enumerated() {
            if character.isNumber || character == "-" {
                seen += 1
                if seen == count { return index + 1 }
            }
        }
        return formatted.count
    }
}
