import Foundation
import XCTest
@testable import DanarapiContracts

final class ItemSplitTests: XCTestCase {
    func testActualRetailOCRReadsTwoItemsDiscountSubtotalAndIndonesianDate() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appending(path: "tests/fixtures/receipt-retail-ocr.txt"), encoding: .utf8)
        let receipt = ReceiptTextParser.parse(text)
        XCTAssertEqual(receipt.items.map(\.name), ["PAPER BAG JH LARGE", "JENNIE BP D (BLACK)"])
        XCTAssertEqual(receipt.items.map(\.unitPrice), [11_000, 350_000])
        XCTAssertEqual(receipt.items.map(\.lineTotal), [11_000, 175_000])
        XCTAssertEqual(receipt.items.map(\.note), ["0%", "50%"])
        XCTAssertEqual(receipt.subtotal, 361_000)
        XCTAssertEqual(receipt.discount, 175_000)
        XCTAssertEqual(receipt.grandTotal, 186_000)
        XCTAssertEqual(receipt.date, "2025-06-29")
        XCTAssertEqual(receipt.merchant, "@Jims_honeypku")
        XCTAssertTrue(receipt.unreadableFields.contains("items[0].qty"))
        XCTAssertTrue(receipt.unreadableFields.contains("items[1].qty"))
        XCTAssertNil(receipt.serviceCharge)
        XCTAssertNil(receipt.tax)
    }

    func testRetailContinuationNeverTurnsPaidChangeOrSubtotalIntoProducts() {
        let receipt = ReceiptTextParser.parse("TOKO\n29 Juni 2025\nBag 1 11.000 11.000\n2 Item JUMLAH\n11.000\nTOTAL DISC\n0\nTOTAL\n11.000\nBAYAR 20.000\nKEMBALI 9.000")
        XCTAssertEqual(receipt.items.count, 1)
        XCTAssertEqual(receipt.subtotal, 11_000)
        XCTAssertEqual(receipt.grandTotal, 11_000)
        XCTAssertEqual(receipt.date, "2025-06-29")
        XCTAssertTrue(receipt.validation.passed)
    }

    func testStoredWebReceiptDecodesWithoutLosingDiscountOrPrintedTotals() throws {
        let json = #"{"merchant":"JIMS HONEY","date":"2025-06-29","items":[{"name":"Paper Bag Jh Large","qty":1,"unit_price":"11000","line_total":"11000","note":null},{"name":"Jennie Bp D (black)","qty":1,"unit_price":"350000","line_total":"175000","note":"50%"}],"subtotal":"361000","service_charge":"0","tax":"0","discount":"175000","rounding":"0","grand_total":"186000","tax_included_in_price":false,"unreadable_fields":[]}"#
        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))
        XCTAssertEqual(receipt.grandTotal, 186_000)
        XCTAssertEqual(receipt.subtotal, 361_000)
        XCTAssertEqual(receipt.discount, 175_000)
        XCTAssertEqual(receipt.items[1].unitPrice, 350_000)
        XCTAssertEqual(receipt.items[1].lineTotal, 175_000)
        XCTAssertEqual(receipt.items[1].note, "50%")
        XCTAssertEqual(receipt.date, "2025-06-29")
        XCTAssertEqual(receipt.validation.badRows, [1])
        XCTAssertEqual(receipt.validation.problems.count, 2)
        XCTAssertTrue(receipt.validation.problems[0].contains("Rp 350.000"))
        XCTAssertEqual(try JSONDecoder().decode(ScannedReceipt.self, from: JSONEncoder().encode(receipt)), receipt)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any])
        XCTAssertEqual(stored["grand_total"] as? String, "186000")
        XCTAssertEqual(stored["discount"] as? String, "175000")
        let storedItems = try XCTUnwrap(stored["items"] as? [[String: Any]])
        XCTAssertEqual(storedItems[1]["unit_price"] as? String, "350000")
    }

    func testLocalReceiptPreservesDiscountMismatchAndHistoricalDate() {
        let receipt = ReceiptTextParser.parse("JIMS HONEY\n29/06/25\nPaper Bag Jh Large 1 11.000 11.000\nJennie Bp D (black) 1 350.000 175.000\n50%\nSubtotal 361.000\nService 0\nPajak 0\nDiskon 175.000\nTotal 186.000")
        XCTAssertEqual(receipt.items.count, 2)
        XCTAssertEqual(receipt.date, "2025-06-29")
        XCTAssertEqual(receipt.grandTotal, 186_000)
        XCTAssertEqual(receipt.discount, 175_000)
        XCTAssertEqual(receipt.items[1].lineTotal, 175_000)
        XCTAssertEqual(receipt.items[1].unitPrice, 350_000)
        XCTAssertEqual(receipt.items[1].note, "50%")
        XCTAssertEqual(receipt.validation.badRows, [1])
        XCTAssertEqual(receipt.validation.problems.count, 2)
    }

    func testLocalReceiptNeverInventsMissingPricesOrTotal() {
        let receipt = ReceiptTextParser.parse("TOKO DEMO\n2025-06-29\nKopi 2 x 25.000\nSubtotal 50.000")
        XCTAssertEqual(receipt.items.count, 1)
        XCTAssertEqual(receipt.items[0].unitPrice, 25_000)
        XCTAssertNil(receipt.items[0].lineTotal)
        XCTAssertNil(receipt.grandTotal)
        XCTAssertEqual(receipt.date, "2025-06-29")
        XCTAssertFalse(receipt.validation.passed)
    }

    func testLocalMultilineReceiptQuantityAndSignedRounding() {
        let receipt = ReceiptTextParser.parse("TOKO\n29/06/2025\nBeras 10kg\n4000 14.000 56.000.000\nSubtotal 56.000.000\nPembulatan -50\nTotal 55.999.950")
        XCTAssertEqual(receipt.items.first?.qty, 4000)
        XCTAssertEqual(receipt.items.first?.unitPrice, 14_000)
        XCTAssertEqual(receipt.items.first?.lineTotal, 56_000_000)
        XCTAssertEqual(receipt.rounding, -50)
        XCTAssertTrue(receipt.validation.passed)
    }

    func testStoredUnknownValuesStayNilAndInvalidMoneyIsRejected() throws {
        let json = #"{"items":[{"name":"Kopi","qty":1,"unit_price":null,"line_total":"10000"}],"subtotal":null,"service_charge":null,"tax":null,"discount":"0","rounding":"-50","grand_total":null,"tax_included_in_price":false,"unreadable_fields":["items[0].unit_price"]}"#
        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))
        XCTAssertNil(receipt.items[0].unitPrice)
        XCTAssertNil(receipt.grandTotal)
        XCTAssertEqual(receipt.rounding, -50)
        XCTAssertFalse(receipt.validation.passed)
        XCTAssertThrowsError(try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.replacingOccurrences(of: "10000", with: "10.000").utf8)))
    }

    func testWholesaleReceiptPreservesQuantitiesAndPrintedMismatch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(contentsOf: root.appending(path: "tests/fixtures/receipt-wholesale.json")))
        XCTAssertEqual(receipt.items.map(\.qty), [4000, 1600, 1600, 800, 8000, 1600, 1600, 800])
        XCTAssertEqual(receipt.validation.badRows, [7])
        XCTAssertEqual(receipt.validation.problems.count, 2)
        XCTAssertEqual(receipt.items[7].lineTotal, 7800000)
        let draft = ItemSplit(items: receipt.items.map { ReceiptLine(name: $0.name, quantity: $0.qty, unitPrice: String($0.unitPrice!), allocations: [ItemAllocation(memberID: "a", quantity: 1), ItemAllocation(memberID: "b", quantity: 1)]) }, settings: ReceiptSettings(serviceRate: 0, taxRate: 0))
        XCTAssertEqual(try ItemSplitCalculator.receipt(draft, memberIDs: ["a", "b"]).total, 200000000)
        var boundary = receipt
        boundary.items[0].qty = 999999
        boundary.items[0].unitPrice = Money.maximum
        XCTAssertFalse(boundary.validation.passed)
        boundary.items[0].qty = 1000000
        XCTAssertFalse(boundary.validation.passed)
        let excessive = ItemSplit(items: [ReceiptLine(name: "Beras", quantity: 1, unitPrice: String(Money.maximum), allocations: [ItemAllocation(memberID: "a", quantity: 999999), ItemAllocation(memberID: "b", quantity: 999999)])])
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(excessive, memberIDs: ["a", "b"]))
    }
    func testDiscountInclusiveTaxAndSignedRounding() throws {
        var draft = ItemSplit(items: [ReceiptLine(name: "Bersama", quantity: 1, unitPrice: "10000", allocations: ["a", "b", "c"].map { ItemAllocation(memberID: $0, quantity: 1) })], discount: "1000", settings: ReceiptSettings(), rounding: "-1")
        var result = try ItemSplitCalculator.receipt(draft, memberIDs: ["a", "b", "c"])
        XCTAssertEqual(result.total, 10349)
        XCTAssertEqual(result.rows.reduce(0) { $0 + $1.discount }, 1000)
        XCTAssertEqual(result.rows.reduce(0) { $0 + $1.rounding }, -1)
        draft.settings?.taxIncluded = true
        result = try ItemSplitCalculator.receipt(draft, memberIDs: ["a", "b", "c"])
        XCTAssertEqual(result.total, 8999)
        XCTAssertEqual(result.rows.reduce(0) { $0 + $1.tax + $1.service }, 0)
        draft.rounding = "1"
        XCTAssertEqual(try ItemSplitCalculator.calculate(draft, memberIDs: ["a", "b", "c"]).total, "9001")
    }
    func testScanValidationUsesLocalNumbers() throws {
        let json = #"{"merchant":"ABC","date":"2026-10-01","items":[{"name":"Menu","qty":1,"unit_price":10000,"line_total":10000,"note":null}],"subtotal":10000,"service_charge":500,"tax":1000,"discount":0,"rounding":0,"grand_total":11500,"tax_included_in_price":false,"unreadable_fields":[]}"#
        var receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))
        XCTAssertTrue(receipt.validation.passed)
        receipt.items[0].lineTotal = 9000
        XCTAssertFalse(receipt.validation.passed)
        XCTAssertEqual(receipt.validation.badRows, [0])
        receipt.items[0].lineTotal = Int64.max
        XCTAssertFalse(receipt.validation.passed)
    }
    func testReceiptABCAndSharedRounding() throws {
        let ids = ["a", "b", "c", "d", "e"]
        let prices = ["38000", "85000", "50000", "70000", "55000"]
        let draft = ItemSplit(items: ids.indices.map { ReceiptLine(name: "Menu", quantity: 1, unitPrice: prices[$0], allocations: [ItemAllocation(memberID: ids[$0], quantity: 1)]) }, settings: ReceiptSettings())
        let result = try ItemSplitCalculator.receipt(draft, memberIDs: ids)
        XCTAssertEqual(result.rows.map(\.total), [43700, 97750, 57500, 80500, 63250])
        XCTAssertEqual(result.total, 342700)
        XCTAssertEqual(result.rows.reduce(0) { $0 + $1.subtotal }, 298000)
        XCTAssertEqual(result.rows.reduce(0) { $0 + $1.service }, 14900)
        XCTAssertEqual(result.rows.reduce(0) { $0 + $1.tax }, 29800)
        var shared = ItemSplit(items: [ReceiptLine(name: "Bersama", quantity: 1, unitPrice: "10000", allocations: ids.prefix(3).map { ItemAllocation(memberID: $0, quantity: 1) })], settings: ReceiptSettings(serviceRate: 0, taxRate: 0))
        XCTAssertEqual(try ItemSplitCalculator.receipt(shared, memberIDs: Array(ids.prefix(3))).rows.map(\.total), [3334, 3333, 3333])
        shared.settings = ReceiptSettings(taxOnService: true)
        XCTAssertEqual(try ItemSplitCalculator.calculate(shared, memberIDs: ids).total, "11550")
        shared.items[0].allocations = []
        XCTAssertEqual(try ItemSplitCalculator.receipt(shared, memberIDs: ids).unassigned, ["Bersama"])
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(shared, memberIDs: ids))
    }
    func testReceiptRateValidation() throws {
        let item = ReceiptLine(name: "Menu", quantity: 1, unitPrice: "10000", allocations: [ItemAllocation(memberID: "self", quantity: 1)])
        for rate in [-0.01, 100.01, 1.001, Double.nan, Double.infinity, -Double.infinity] {
            for settings in [ReceiptSettings(serviceRate: rate), ReceiptSettings(taxRate: rate)] {
                let draft = ItemSplit(items: [item], settings: settings)
                XCTAssertThrowsError(try ItemSplitCalculator.receipt(draft, memberIDs: ["self"])) { error in
                    XCTAssertEqual(error as? ContractError, .validation)
                }
            }
        }
        for rate in [0.0, 0.01, 12.34, 100.0] {
            let draft = ItemSplit(items: [item], settings: ReceiptSettings(serviceRate: rate, taxRate: rate))
            XCTAssertEqual(try ItemSplitCalculator.receipt(draft, memberIDs: ["self"]).rows.count, 1)
        }
    }

    struct Fixture: Decodable {
        struct Example: Decodable { let name: String; let draft: ItemSplit; let memberIDs: [String]; let expected: ItemSplitResult }
        let cases: [Example]
    }
    func testServerGoldenFixture() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "tests/fixtures/item-split-v1.json")))
        for example in fixture.cases { XCTAssertEqual(try ItemSplitCalculator.calculate(example.draft, memberIDs: example.memberIDs), example.expected, example.name) }
    }
    func testSharedReceiptFixtureWithLargeAmounts() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appending(path: "tests/fixtures/receipt-split-v2.json")))
        for example in fixture.cases { XCTAssertEqual(try ItemSplitCalculator.calculate(example.draft, memberIDs: example.memberIDs), example.expected, example.name) }
    }
    func testUnassignedDuplicateUnknownAndOverflowRejected() throws {
        let base = ItemSplit(items: [ReceiptLine(name: "Nasi", quantity: 2, unitPrice: "10000", allocations: [ItemAllocation(memberID: "a", quantity: 1), ItemAllocation(memberID: "b", quantity: 1)])])
        var changed = base; changed.items[0].allocations.removeLast()
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(changed, memberIDs: ["a", "b"]))
        changed = base; changed.items[0].allocations[1].memberID = "a"
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(changed, memberIDs: ["a", "b"]))
        changed = base; changed.items[0].allocations[1].memberID = "stranger"
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(changed, memberIDs: ["a", "b"]))
        changed = base; changed.items[0].unitPrice = String(Money.maximum)
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(changed, memberIDs: ["a", "b"]))
        changed = base; changed.discount = "20000"
        XCTAssertThrowsError(try ItemSplitCalculator.calculate(changed, memberIDs: ["a", "b"]))
    }
}
