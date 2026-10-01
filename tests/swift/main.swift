import Foundation

let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appending(path: "tests/fixtures/ledger-v1.json")
let data = try Data(contentsOf: fixtureURL)
guard let fixture = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      fixture["schema_version"] as? String == "1.0.0",
      let money = fixture["money"] as? [String: Any],
      let validMoney = money["valid"] as? [String],
      let invalidMoney = money["invalid"] as? [Any],
      let splitCases = fixture["split_rounding"] as? [[String: Any]]
else {
    fatalError("Golden fixture structure is invalid")
}

for value in validMoney {
    _ = try Money.parse(value, allowZero: value == "0")
}
for case let value as String in invalidMoney {
    do {
        _ = try Money.parse(value, allowZero: true)
        fatalError("Invalid money accepted: \(value)")
    } catch ContractError.validation {
        // Expected.
    }
}

for item in splitCases {
    guard let total = item["total"] as? String,
          let expected = item["expected"] as? [String: String],
          let rows = item["participants"] as? [[String: Any]]
    else { fatalError("Split fixture is invalid") }

    if item["method"] as? String == "equal" {
        let participants = rows.map {
            EqualParticipant(id: $0["id"] as! String, included: $0["included"] as! Bool)
        }
        guard try SplitCalculator.equal(total: total, participants: participants) == expected else {
            fatalError("Equal split mismatch")
        }
    } else {
        let participants = rows.map {
            PercentageParticipant(id: $0["id"] as! String, basisPoints: $0["basis_points"] as! Int)
        }
        guard try SplitCalculator.percentage(total: total, participants: participants) == expected else {
            fatalError("Percentage split mismatch")
        }
    }
}

print("Swift golden fixture passed: money, equal split, percentage split.")
