import XCTest
@testable import DanarapiContracts

final class MoneyInputTests: XCTestCase {
    func testGroupingAndCanonicalValues() {
        for (raw, display) in [("", ""), ("0", "0"), ("5000", "5.000"), ("500000", "500.000"), ("999999999999", "999.999.999.999")] {
            XCTAssertEqual(MoneyInputFormat.display(raw), display)
            XCTAssertEqual(MoneyInputFormat.raw(display), raw)
        }
        XCTAssertEqual(MoneyInputFormat.raw("Rp 005.000"), "5000")
        XCTAssertEqual(MoneyInputFormat.raw("000"), "0")
        XCTAssertEqual(MoneyInputFormat.raw("1234567890123"), "123456789012")
    }

    func testSignedRounding() {
        XCTAssertEqual(MoneyInputFormat.display("-5000", signed: true), "-5.000")
        XCTAssertEqual(MoneyInputFormat.raw("-5.000", signed: true), "-5000")
        XCTAssertEqual(MoneyInputFormat.display("-", signed: true), "-")
        XCTAssertEqual(MoneyInputFormat.display("-0", signed: true), "0")
    }

    func testCaret() {
        XCTAssertEqual(MoneyInputFormat.caret("5000", position: 4, formatted: "5.000"), 5)
        XCTAssertEqual(MoneyInputFormat.caret("51.000", position: 2, formatted: "51.000"), 2)
        XCTAssertEqual(MoneyInputFormat.caret("-5000", position: 2, formatted: "-5.000"), 2)
    }
}
