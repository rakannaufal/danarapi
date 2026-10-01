import Foundation
import XCTest
@testable import Danarapi

final class LedgerFixtureTests: XCTestCase {
    @MainActor
    func testDemoSplitLedgerMatchesSharedServerScenarios() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ledger-v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let scenarios = try XCTUnwrap(fixture["ledger_scenarios"] as? [[String: Any]])
        for scenario in scenarios where scenario["bill"] != nil {
            let repository = DemoRepository()
            let name = try XCTUnwrap(scenario["id"] as? String)
            let opening = try XCTUnwrap(scenario["opening"] as? [String: Any])
            let startingCash = try amount(opening["cash"])
            try await repository.createAccount(AccountDraft(name: name, kind: .cash, openingBalance: startingCash, openedAt: .distantPast))
            let baseline = try await repository.dashboard()
            let accountID = try XCTUnwrap(baseline.accounts.first { $0.name == name }?.id)
            let billData = try XCTUnwrap(scenario["bill"] as? [String: Any])
            let total = try amount(billData["total"])
            let share = try amount(billData["self_share"])
            let selfPays = billData["payer"] as? String == "self"
            let members = ["self", "ani", "budi"].enumerated().map { index, id in
                SplitMember(id: id, displayName: id == "self" ? "Saya" : id.capitalized, isSelf: id == "self", shareAmount: share, settledAmount: 0, resolvedAmount: 0, sortOrder: index)
            }
            try await repository.createSplitBill(SplitBillDraft(title: name, total: total, categoryID: "food", payer: selfPays ? .selfPaid(accountID: accountID) : .other(memberID: "ani"), occurredAt: .now, note: nil, members: members))
            var snapshot = try await repository.dashboard()
            var bill = try XCTUnwrap(snapshot.splitBills.first { $0.title == name })
            for event in scenario["settlements"] as? [[String: Any]] ?? [] {
                try await repository.recordSettlement(SettlementDraft(billID: bill.id, memberID: try XCTUnwrap(event["member"] as? String), accountID: accountID, amount: try amount(event["amount"]), occurredAt: .now, note: nil))
            }
            for event in scenario["resolutions"] as? [[String: Any]] ?? [] {
                try await repository.recordResolution(ResolutionDraft(billID: bill.id, memberID: try XCTUnwrap(event["member"] as? String), amount: try amount(event["amount"]), occurredAt: .now, reason: "Fixture bersama"))
            }
            snapshot = try await repository.dashboard()
            let expected = try XCTUnwrap(scenario["expected"] as? [String: Any])
            try assertSnapshot(snapshot, baseline: baseline, accountID: accountID, startingCash: startingCash, expected: expected)
            if let reversal = scenario["after_reversal"] as? [String: Any] {
                bill = try XCTUnwrap(snapshot.splitBills.first { $0.id == bill.id })
                let event = try XCTUnwrap(bill.resolutions.first)
                try await repository.reverseResolution(id: event.id, expectedVersion: event.version, reason: "Reversal fixture")
                snapshot = try await repository.dashboard()
                try assertSnapshot(snapshot, baseline: baseline, accountID: accountID, startingCash: startingCash, expected: reversal)
            }
        }
    }

    @MainActor
    func testImportedDraftDoesNotAffectLedgerBeforeReview() async throws {
        let repository = DemoRepository()
        let before = try await repository.dashboard()
        let item = ImportService.reviewFromText("BUKTI DEMO\nTotal: Rp75.000\n30/09/2026")
        try await repository.addReviewItem(item, attachment: nil)
        let after = try await repository.dashboard()
        XCTAssertEqual(after.overview, before.overview)
        XCTAssertEqual(after.transactions.count, before.transactions.count)
        XCTAssertEqual(after.reviewItems.first { $0.id == item.id }?.status, .pending)
    }

    private func amount(_ value: Any?) throws -> Int64 { try XCTUnwrap((value as? String).flatMap(Int64.init)) }

    private func assertSnapshot(_ value: DashboardSnapshot, baseline: DashboardSnapshot, accountID: String, startingCash: Int64, expected: [String: Any]) throws {
        XCTAssertEqual(value.accounts.first { $0.id == accountID }?.balance, try amount(expected["cash"]))
        XCTAssertEqual(value.overview.receivables - baseline.overview.receivables, try amount(expected["receivables"]))
        XCTAssertEqual(value.overview.payables - baseline.overview.payables, try amount(expected["payables"] ?? "0"))
        XCTAssertEqual(value.overview.netPosition - baseline.overview.netPosition + startingCash, try amount(expected["net_position"]))
        XCTAssertEqual(value.overview.personalExpense - baseline.overview.personalExpense, try amount(expected["personal_expense"]))
    }
}
