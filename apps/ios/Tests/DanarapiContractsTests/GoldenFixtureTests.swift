import Foundation
import XCTest
@testable import DanarapiContracts

final class GoldenFixtureTests: XCTestCase {
    private func loadFixture() throws -> [String: Any] {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appending(path: "tests/fixtures/ledger-v1.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testContractVersionAndMoneyStrings() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture["schema_version"] as? String, "1.0.0")
        let money = try XCTUnwrap(fixture["money"] as? [String: Any])
        for value in try XCTUnwrap(money["valid"] as? [String]) {
            XCTAssertNoThrow(try Money.parse(value, allowZero: value == "0"))
        }
        for value in try XCTUnwrap(money["invalid"] as? [Any]) {
            if let string = value as? String {
                XCTAssertThrowsError(try Money.parse(string, allowZero: true))
            } else {
                XCTAssertTrue(value is NSNumber)
            }
        }
    }

    func testSplitRoundingMatchesGoldenFixture() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["split_rounding"] as? [[String: Any]])
        for item in cases {
            let total = try XCTUnwrap(item["total"] as? String)
            let expected = try XCTUnwrap(item["expected"] as? [String: String])
            let participantRows = try XCTUnwrap(item["participants"] as? [[String: Any]])
            if item["method"] as? String == "equal" {
                let participants = try participantRows.map {
                    EqualParticipant(id: try XCTUnwrap($0["id"] as? String), included: try XCTUnwrap($0["included"] as? Bool))
                }
                XCTAssertEqual(try SplitCalculator.equal(total: total, participants: participants), expected)
            } else {
                let participants = try participantRows.map {
                    PercentageParticipant(id: try XCTUnwrap($0["id"] as? String), basisPoints: try XCTUnwrap($0["basis_points"] as? Int))
                }
                XCTAssertEqual(try SplitCalculator.percentage(total: total, participants: participants), expected)
            }
        }
    }
}
