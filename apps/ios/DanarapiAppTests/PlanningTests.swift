import Foundation
import XCTest
import UIKit
import SwiftUI
@testable import Danarapi

final class PlanningTests: XCTestCase {
    func testSharedVisualTokensUseNeutralPalette() {
        XCTAssertEqual(DesignTokens.version, "1.2.0")
        XCTAssertEqual(DesignTokenCatalog.bundled?.hex("canvas", theme: "light"), 0xF5F5F7)
        XCTAssertEqual(DesignTokenCatalog.bundled?.hex("canvas", theme: "dark"), 0x111113)
        XCTAssertEqual(DesignTokens.cornerControl, 12)
        XCTAssertEqual(DesignTokens.minimumTouch, 44)
    }
    @MainActor
    func testRupiahFieldKeepsCanonicalValueAndCaret() {
        var raw = ""
        let view = RupiahTextField("0", text: Binding(get: { raw }, set: { raw = $0 }))
        let coordinator = view.makeCoordinator()
        let field = UITextField()
        field.text = ""
        XCTAssertFalse(coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 0, length: 0), replacementString: "5000"))
        XCTAssertEqual(field.text, "5.000")
        XCTAssertEqual(raw, "5000")
        XCTAssertFalse(coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 1, length: 0), replacementString: "1"))
        XCTAssertEqual(field.text, "51.000")
        XCTAssertEqual(raw, "51000")
        let position = field.position(from: field.beginningOfDocument, offset: 3)!
        field.selectedTextRange = field.textRange(from: position, to: position)
        XCTAssertFalse(coordinator.textField(field, shouldChangeCharactersIn: NSRange(location: 2, length: 1), replacementString: ""))
        XCTAssertEqual(field.text, "5.000")
        XCTAssertEqual(raw, "5000")
    }

    func testBudgetPresetsAndGoalCountdownUseCalendarDays() {
        XCTAssertEqual(BudgetCategoryPresets.names.count, 10)
        XCTAssertEqual(Set(BudgetCategoryPresets.names).count, 10)
        let now = MonthPeriod.calendar.date(from: DateComponents(year: 2026, month: 10, day: 1))!
        let deadline = MonthPeriod.calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        var goal = SavingsGoal(id: "countdown", name: "Dana darurat", targetAmount: 5_000_000, savedAmount: 1_000_000, targetDate: deadline, version: 1)
        XCTAssertEqual(goal.countdown(asOf: now), "30 hari lagi")
        XCTAssertEqual(goal.countdown(asOf: deadline), "Jatuh tempo hari ini")
        XCTAssertEqual(goal.countdown(asOf: MonthPeriod.calendar.date(byAdding: .day, value: 2, to: deadline)!), "Lewat 2 hari")
        goal.savedAmount = 5_000_000
        XCTAssertEqual(goal.countdown(asOf: now), "Tercapai")
        goal.savedAmount = 0; goal.targetDate = nil
        XCTAssertEqual(goal.countdown(asOf: now), "Tanpa tenggat")
    }
    func testBundledItemFixtureMatchesServer() throws {
        struct Fixture: Decodable {
            struct Example: Decodable { let name: String; let draft: ItemSplit; let memberIDs: [String]; let expected: ItemSplitResult }
            let cases: [Example]
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "item-split-v1", withExtension: "json"))
        for value in try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).cases {
            XCTAssertEqual(try ItemSplitCalculator.calculate(value.draft, memberIDs: value.memberIDs), value.expected, value.name)
        }
    }
    func testReceiptExtractionKeepsQuantitiesUnitPricesAndReviewDraft() {
        let item = ImportService.reviewFromText("WARUNG UJI\nNasi 4 x 25000 100000\nTeh 2 x 15000 30000\nTotal: Rp130.000")
        XCTAssertEqual(item.status, .pending)
        XCTAssertEqual(item.receiptLines?.map(\.quantity), [4, 2])
        XCTAssertEqual(item.receiptLines?.map(\.unitPrice), ["25000", "15000"])
        XCTAssertTrue(item.receiptLines?.allSatisfy { $0.allocations.isEmpty } ?? false)
        XCTAssertEqual(item.amount.value, "130000")
        XCTAssertTrue(ReceiptParser.lines(from: "Nasi 4 x 999999999999999999").isEmpty)
    }
    @MainActor
    func testVisionReadsSyntheticReceiptImageIntoDraft() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 700)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 700))
            let text = "WARUNG UJI\nNasi 4 x 25000 100000\nTeh 2 x 15000 30000\nTotal: Rp130.000"
            (text as NSString).draw(in: CGRect(x: 60, y: 60, width: 1050, height: 570), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 44, weight: .regular), .foregroundColor: UIColor.black])
        }
        let text = try await ImportService.recognizedText(in: image)
        XCTAssertTrue(text.contains("Nasi"))
        let draft = ImportService.reviewFromText(text, source: .image)
        XCTAssertEqual(draft.status, .pending)
        XCTAssertEqual(draft.receiptLines?.count, 2)
        XCTAssertEqual(draft.amount.confidence, .low)
    }
    @MainActor
    func testGoalDoesNotMoveLedgerAndVersionIsEnforced() async throws {
        let repo = DemoRepository()
        let before = try await repo.dashboard()
        var goal = SavingsGoal(id: UUID().uuidString, name: "Sepeda", targetAmount: 2_000_000, savedAmount: 0, targetDate: nil, version: 0)
        try await repo.saveGoal(goal)
        var after = try await repo.dashboard()
        XCTAssertEqual(after.overview, before.overview)
        XCTAssertEqual(after.transactions.count, before.transactions.count)
        goal.version = 1; goal.savedAmount = 700_000
        try await repo.saveGoal(goal)
        after = try await repo.dashboard()
        XCTAssertEqual(after.goals?.first { $0.id == goal.id }?.savedAmount, 0)
        do { try await repo.saveGoal(goal); XCTFail("Stale version accepted") } catch {}
        try await repo.deleteGoal(id: goal.id, expectedVersion: 2)
        after = try await repo.dashboard()
        XCTAssertFalse(after.goals?.contains { $0.id == goal.id } ?? true)
    }
    @MainActor
    func testMonthlyReportHasExclusiveEndBoundary() async throws {
        let repo = DemoRepository()
        let start = MonthPeriod.start(.now)
        let end = MonthPeriod.end(start)
        let baseline = try await repo.report(since: start, until: end)
        try await repo.saveTransaction(TransactionDraft(id: nil, kind: .expense, amount: 10_000, accountID: "cash", categoryID: "food", occurredAt: end, merchant: "Next month", note: nil, source: "manual", expectedVersion: nil))
        let same = try await repo.report(since: start, until: end)
        XCTAssertEqual(same.personalExpense, baseline.personalExpense)
        try await repo.saveTransaction(TransactionDraft(id: nil, kind: .expense, amount: 20_000, accountID: "cash", categoryID: "food", occurredAt: start, merchant: "Current month", note: nil, source: "manual", expectedVersion: nil))
        let included = try await repo.report(since: start, until: end)
        XCTAssertEqual(included.personalExpense, baseline.personalExpense + 20_000)
        XCTAssertEqual(MonthPeriod.key(start), MonthPeriod.key(MonthPeriod.calendar.date(byAdding: .hour, value: 1, to: start)!))
    }

    func testBudgetExactThresholds() {
        for (spent, status) in [(Int64(69), "safe"), (70, "warning"), (100, "warning"), (101, "over")] {
            XCTAssertEqual(Budget(id: "budget", categoryID: "food", month: .now, limitAmount: 100, spentAmount: spent).status, status)
        }
    }

    @MainActor
    func testGoalLedgerLifecycleAndReportReconcileBeyondFirstPage() async throws {
        let repo = DemoRepository(), goalID = UUID().uuidString
        let before = try await repo.dashboard()
        let goal = SavingsGoal(id: goalID, name: "Laptop test", targetAmount: 2_000_000, savedAmount: 0, targetDate: nil, version: 0)
        try await repo.saveGoal(goal)
        let start = MonthPeriod.start(.now), end = MonthPeriod.end(start)
        let baseline = try await repo.report(since: start, until: end)
        var draft = TransactionDraft(id: nil, kind: .expense, amount: 70_000, accountID: "cash", categoryID: "food", occurredAt: start, merchant: "Progres test", note: nil, source: "manual", expectedVersion: nil, goalID: goalID)
        try await repo.saveTransaction(draft)
        var after = try await repo.dashboard()
        XCTAssertEqual(after.goals?.first { $0.id == goalID }?.savedAmount, 70_000)
        XCTAssertEqual(after.overview.accountBalance, before.overview.accountBalance - 70_000)
        let same = try await repo.dashboard()
        XCTAssertEqual(same.goals?.first { $0.id == goalID }?.savedAmount, 70_000)
        let periodReport = try await repo.report(since: start, until: end)
        XCTAssertEqual(periodReport.personalExpense, baseline.personalExpense + 70_000)
        XCTAssertEqual(periodReport.allocations?.reduce(0) { $0 + $1.amount }, periodReport.personalExpense)
        XCTAssertEqual(periodReport.allocations?.first { $0.id == "goal:\(goalID)" }?.amount, 70_000)
        let firstPage = try await repo.transactionPage(after: TransactionCursor(occurredAt: .distantFuture, id: "zzzz"))
        var transaction = try XCTUnwrap(firstPage.items.first { $0.goalID == goalID })
        draft.id = transaction.id; draft.expectedVersion = 1; draft.amount = 100_000; draft.accountID = "bank"
        try await repo.saveTransaction(draft)
        after = try await repo.dashboard()
        XCTAssertEqual(after.goals?.first { $0.id == goalID }?.savedAmount, 100_000)
        XCTAssertEqual(after.accounts.first { $0.id == "cash" }?.balance, before.accounts.first { $0.id == "cash" }?.balance)
        try await repo.deleteTransaction(id: transaction.id, expectedVersion: 2)
        after = try await repo.dashboard()
        XCTAssertEqual(after.goals?.first { $0.id == goalID }?.savedAmount, 0)
        XCTAssertEqual(after.overview.accountBalance, before.overview.accountBalance)
        try await repo.restoreTransaction(id: transaction.id, expectedVersion: 3)
        after = try await repo.dashboard()
        XCTAssertEqual(after.goals?.first { $0.id == goalID }?.savedAmount, 100_000)
        try await repo.deleteGoal(id: goalID, expectedVersion: 1)
        let removed = try await repo.dashboard()
        XCTAssertEqual(removed.overview.accountBalance, after.overview.accountBalance)
        let removedPage = try await repo.transactionPage(after: TransactionCursor(occurredAt: .distantFuture, id: "zzzz"))
        transaction = try XCTUnwrap(removedPage.items.first { $0.id == transaction.id })
        XCTAssertNil(transaction.goalID)
    }

    @MainActor
    func testQRISForcesCategoryAndRejectsIncomeEdit() async throws {
        let repo = DemoRepository()
        let before = try await repo.dashboard()
        let draft = TransactionDraft(id: nil, kind: .expense, amount: 75_000, accountID: "cash", categoryID: "food", occurredAt: .now, merchant: "QRIS test", note: nil, source: "qris", expectedVersion: nil)
        try await repo.saveTransaction(draft)
        let after = try await repo.dashboard(), transaction = try XCTUnwrap(after.transactions.first { $0.merchant == "QRIS test" })
        XCTAssertEqual(transaction.categoryID, "feature-qris")
        XCTAssertEqual(after.overview.accountBalance, before.overview.accountBalance - 75_000)
        var invalid = draft; invalid.id = transaction.id; invalid.expectedVersion = 1; invalid.kind = .income; invalid.categoryID = "salary"; invalid.source = "manual"
        do { try await repo.saveTransaction(invalid); XCTFail("QRIS changed into income") } catch {}
        let unchanged = try await repo.dashboard()
        XCTAssertEqual(unchanged.overview, after.overview)
    }

    func testOAuthPKCEVerifierAndProviderURL() async throws {
        let verifier = try OAuthPKCE.verifier()
        XCTAssertEqual(verifier.count, 43)
        XCTAssertEqual(OAuthPKCE.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let service = AuthService(configuration: SupabaseConfiguration(url: URL(string: "https://backend.example.test")!, anonKey: "public-test"), sessionStore: KeychainSessionStore(service: "test.oauth.\(UUID().uuidString)"))
        let url = try await service.oauthURL(provider: "google", verifier: verifier)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "code_challenge_method" }?.value, "s256")
        XCTAssertEqual(query.first { $0.name == "redirect_to" }?.value, "id.danarapi.app://auth/callback")
        do { _ = try await service.oauthURL(provider: "email", verifier: verifier); XCTFail("Unsupported provider accepted") } catch {}
    }
}
