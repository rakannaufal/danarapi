import Foundation
import UIKit
import XCTest
@testable import Danarapi

final class DanarapiAppTests: XCTestCase {
    func testDevelopmentScannerRequiresPrivateIPv4TLSAndStrongPairingMaterial() {
        let token = String(repeating: "a", count: 64), hash = String(repeating: "b", count: 64)
        let configuration = DevelopmentReceiptScanConfiguration(host: "192.168.1.20", port: "5174", token: token, certificateHash: hash)
        XCTAssertEqual(configuration?.url.absoluteString, "https://192.168.1.20:5174/scan")
        for host in ["example.com", "8.8.8.8", "192.168.1.256", "172.32.1.1", "127.0.0.1", "192.168.1.20/path"] {
            XCTAssertNil(DevelopmentReceiptScanConfiguration(host: host, port: "5174", token: token, certificateHash: hash))
        }
        XCTAssertNil(DevelopmentReceiptScanConfiguration(host: "192.168.1.20", port: "5174", token: "short", certificateHash: hash))
        XCTAssertNil(DevelopmentReceiptScanConfiguration(host: "192.168.1.20", port: "0", token: token, certificateHash: hash))
    }

    func testLegacyLocalReviewCanBeRecoveredWithoutCreatingAnotherDraft() {
        var item = ImportService.reviewFromText("TOKO\n29 Juni 2025\nBag 1 11.000 11.000\nSubtotal 11.000\nTotal 11.000", source: .image)
        item.receipt?.items = []
        item.receiptLines = []
        let recovered = ImportService.recoverLocalReview(item)
        XCTAssertEqual(recovered?.id, item.id)
        XCTAssertEqual(recovered?.receipt?.items.count, 1)
        XCTAssertEqual(recovered?.date.value, "2025-06-29")
        XCTAssertEqual(recovered?.amount.confidence, .low)
        XCTAssertEqual(recovered?.rawReference, item.rawReference)
    }

    @MainActor
    func testCloudScanAndRenderedPDFUseFullReceiptResult() async throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 500))
        let pdf = renderer.pdfData { context in context.beginPage(); ("TOKO DEMO" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil) }
        let images = try ImportService.receiptImagesFromPDF(pdf)
        XCTAssertEqual(images.count, 1)
        let response = try JSONDecoder().decode(ReceiptScanResponse.self, from: Data(#"{"status":"ok","data":{"merchant":"TOKO DEMO","date":"2025-06-29","items":[{"name":"Kopi","qty":2,"unit_price":25000,"line_total":50000}],"subtotal":50000,"service_charge":0,"tax":0,"discount":0,"rounding":0,"grand_total":50000,"tax_included_in_price":false,"unreadable_fields":[]}}"#.utf8))
        var calls = 0
        let item = try await ImportService.readReceipt(images: images, source: .pdfText, attachmentName: "struk.pdf") { payload in
            calls += 1
            XCTAssertEqual(payload.count, 1)
            XCTAssertEqual(payload.first?.mimeType, "image/jpeg")
            return response
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(item.amount.value, "50000")
        XCTAssertEqual(item.amount.confidence, .high)
        XCTAssertEqual(item.receipt, response.data)
        XCTAssertEqual(item.attachmentName, "struk.pdf")
        let tooMany = renderer.pdfData { context in for _ in 0..<4 { context.beginPage() } }
        XCTAssertThrowsError(try ImportService.receiptImagesFromPDF(tooMany))
    }

    @MainActor
    func testFailedCloudScanDoesNotSilentlyCreateLocalDraft() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100)) }
        let failure = try JSONDecoder().decode(ReceiptScanResponse.self, from: Data(#"{"status":"no_result"}"#.utf8))
        do {
            _ = try await ImportService.readReceipt(images: [image], source: .image, attachmentName: "struk.jpg") { _ in failure }
            XCTFail("Scan gagal tidak boleh menghasilkan draft sukses.")
        } catch {
            XCTAssertEqual((error as? AppError)?.message, failure.message)
        }
    }

    func testReceiptReviewRetainsFullDetailsAndDateAcrossStorage() throws {
        let json = #"{"merchant":"JIMS HONEY","date":"2025-06-29","items":[{"name":"Bag","qty":1,"unit_price":350000,"line_total":175000,"note":"50%"}],"subtotal":350000,"service_charge":0,"tax":0,"discount":175000,"rounding":0,"grand_total":175000,"tax_included_in_price":false,"unreadable_fields":[]}"#
        let receipt = try JSONDecoder().decode(ScannedReceipt.self, from: Data(json.utf8))
        let item = ImportService.reviewFromReceipt(receipt, source: .image, attachmentName: "struk.jpg")
        XCTAssertEqual(item.amount.value, "175000")
        XCTAssertEqual(item.amount.confidence, .medium)
        XCTAssertEqual(item.receipt, receipt)
        XCTAssertEqual(item.date.value, "2025-06-29")
        XCTAssertEqual(item.receiptLines?.first?.unitPrice, "350000")
        let restored = try JSONDecoder().decode(ReviewItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored, item)
        let parsedDate = try XCTUnwrap(ImportService.receiptDate(item.date.value))
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Asia/Jakarta"); formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(formatter.string(from: parsedDate), "2025-06-29")
        XCTAssertNil(ImportService.receiptDate("2025-02-30"))
    }

    func testLocalImageReviewHasDetailedReceiptInsteadOfOnlyAmount() {
        let item = ImportService.reviewFromText("TOKO\n29/06/2025\nKopi 2 25.000 50.000\nSubtotal 50.000\nTotal 50.000", source: .image)
        XCTAssertEqual(item.receipt?.items.count, 1)
        XCTAssertEqual(item.amount.value, "50000")
        XCTAssertEqual(item.amount.confidence, .low)
        XCTAssertEqual(item.date.value, "2025-06-29")
    }

    func testLegacyReviewWithoutReceiptStillDecodes() throws {
        let item = ImportService.reviewFromText("TOKO\nTotal: Rp75.000")
        var dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        dictionary.removeValue(forKey: "receipt")
        let restored = try JSONDecoder().decode(ReviewItem.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertNil(restored.receipt)
        XCTAssertEqual(restored.amount.value, "75000")
    }

    func testReceiptCorrectionUpdatesSameDraftWithoutPostingTransaction() async throws {
        let repository = DemoRepository()
        var item = ImportService.reviewFromText("TOKO\n29/06/2025\nKopi 1 25.000 25.000\nSubtotal 25.000\nTotal 25.000", source: .image)
        try await repository.addReviewItem(item, attachment: nil)
        let before = try await repository.dashboard()
        item.receipt?.items[0].name = "Kopi susu"
        try await repository.updateReviewItem(item)
        let after = try await repository.dashboard()
        XCTAssertEqual(after.reviewItems.filter { $0.id == item.id }.count, 1)
        XCTAssertEqual(after.reviewItems.first { $0.id == item.id }?.receipt?.items[0].name, "Kopi susu")
        XCTAssertEqual(after.transactions.count, before.transactions.count)
    }

    func testSharedDesignTokenVersion() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "design-tokens", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? String, DesignTokens.version)
    }

    func testGoldenSplitRounding() throws {
        let result = try SplitCalculator.equal(total: "100000", participants: [
            EqualParticipant(id: "self", included: true),
            EqualParticipant(id: "ani", included: true),
            EqualParticipant(id: "budi", included: true)
        ])
        XCTAssertEqual(result, ["self": "33334", "ani": "33333", "budi": "33333"])
    }

    func testPercentageLargestRemainder() throws {
        let result = try SplitCalculator.percentage(total: "100001", participants: [
            PercentageParticipant(id: "self", basisPoints: 3334),
            PercentageParticipant(id: "ani", basisPoints: 3333),
            PercentageParticipant(id: "budi", basisPoints: 3333)
        ])
        XCTAssertEqual(result, ["self": "33341", "ani": "33330", "budi": "33330"])
    }

    func testQRISValidAndInvalidCRC() throws {
        let fixture = try importFixture()
        let cases = try XCTUnwrap(fixture["qris"] as? [[String: Any]])
        let payload = try XCTUnwrap(cases.first?["raw"] as? String)
        let parsed = try QRISParser.parse(payload)
        XCTAssertEqual(parsed.merchant, "TOKO DEMO")
        XCTAssertEqual(parsed.city, "JAKARTA")
        XCTAssertEqual(parsed.amount, 75_000)
        XCTAssertThrowsError(try QRISParser.parse(try XCTUnwrap(cases.dropFirst().first?["raw"] as? String)))
    }

    func testAmbiguousTextStaysDraftWithoutAmount() {
        let item = ImportService.reviewFromText("Kedai Sore\nSubtotal 50.000\nPajak 5.000")
        XCTAssertNil(item.amount.value)
        XCTAssertEqual(item.amount.confidence, .low)
        XCTAssertEqual(item.status, .pending)
    }

    func testMerchantRuleNormalizesAndSuggestsOnly() {
        let rule = MerchantRule(id: "r", matchType: .contains, normalizedPattern: MerchantRule.normalize("Warung Pagi"), categoryID: "food", priority: 10, version: 1)
        XCTAssertTrue(rule.matches("WARUNG   PAGI cabang 2"))
        XCTAssertFalse(rule.matches("Pasar Pagi"))
    }

    @MainActor
    func testDemoLedgerSettlementAndOverpay() async throws {
        let repository = DemoRepository()
        var snapshot = try await repository.dashboard()
        var transactionCount = snapshot.transactions.count
        var cursor = snapshot.nextTransactionCursor
        while let current = cursor {
            let page = try await repository.transactionPage(after: current)
            transactionCount += page.items.count
            cursor = page.nextCursor
        }
        XCTAssertEqual(transactionCount, 200)
        let bill = try XCTUnwrap(snapshot.splitBills.first(where: { $0.id == "demo-bill-self" }))
        let budi = try XCTUnwrap(bill.members.first(where: { $0.displayName == "Budi" }))
        try await repository.recordSettlement(SettlementDraft(billID: bill.id, memberID: budi.id, accountID: "cash", amount: 25_000, occurredAt: .now, note: nil))
        snapshot = try await repository.dashboard()
        XCTAssertEqual(snapshot.splitBills.first(where: { $0.id == bill.id })?.remainingAmount, 40_000)
        await XCTAssertThrowsErrorAsync {
            try await repository.recordSettlement(SettlementDraft(billID: bill.id, memberID: budi.id, accountID: "cash", amount: 15_001, occurredAt: .now, note: nil))
        }
    }

    @MainActor
    func testDemoSplitUpdateAndStructureLock() async throws {
        let repository = DemoRepository()
        var snapshot = try await repository.dashboard()
        var bill = try XCTUnwrap(snapshot.splitBills.first(where: { $0.id == "demo-bill-other" }))
        var draft = SplitBillDraft(title: "Tiket diperbarui", total: bill.total, categoryID: bill.categoryID, payer: bill.payer, occurredAt: bill.occurredAt, note: "metadata", members: bill.members)
        try await repository.updateSplitBill(id: bill.id, expectedVersion: bill.version, draft: draft)
        snapshot = try await repository.dashboard()
        bill = try XCTUnwrap(snapshot.splitBills.first(where: { $0.id == bill.id }))
        XCTAssertEqual(bill.title, "Tiket diperbarui")
        let payer = try XCTUnwrap(bill.obligationMembers.first)
        try await repository.recordSettlement(SettlementDraft(billID: bill.id, memberID: payer.id, accountID: "cash", amount: 1_000, occurredAt: .now, note: nil))
        snapshot = try await repository.dashboard()
        bill = try XCTUnwrap(snapshot.splitBills.first(where: { $0.id == bill.id }))
        draft.total += 1
        draft.members[0].shareAmount += 1
        await XCTAssertThrowsErrorAsync { try await repository.updateSplitBill(id: bill.id, expectedVersion: bill.version, draft: draft) }
    }

    @MainActor
    func testDemoReportUsesAllPages() async throws {
        let repository = DemoRepository()
        let report = try await repository.report(since: .distantPast)
        XCTAssertGreaterThan(report.personalExpense, 0)
        XCTAssertFalse(report.categories.isEmpty)
        let snapshot = try await repository.dashboard()
        XCTAssertEqual(snapshot.transactions.count, 30)
    }

    @MainActor
    func testDemoTransactionConversionDoesNotDoubleCount() async throws {
        let repository = DemoRepository()
        let beforeReport = try await repository.report(since: .distantPast)
        let before = try await repository.dashboard()
        let transaction = try XCTUnwrap(before.transactions.first(where: { $0.kind == .expense }))
        let selfID = UUID().uuidString
        let friendID = UUID().uuidString
        let selfShare = transaction.amount / 2
        let draft = SplitBillDraft(
            title: "Konversi uji", total: transaction.amount, categoryID: transaction.categoryID,
            payer: .selfPaid(accountID: transaction.accountID), occurredAt: transaction.occurredAt, note: nil,
            members: [
                SplitMember(id: selfID, displayName: "Saya", isSelf: true, shareAmount: selfShare, settledAmount: 0, resolvedAmount: 0, sortOrder: 0),
                SplitMember(id: friendID, displayName: "Teman", isSelf: false, shareAmount: transaction.amount - selfShare, settledAmount: 0, resolvedAmount: 0, sortOrder: 1)
            ]
        )
        try await repository.convertTransactionToSplitBill(transactionID: transaction.id, expectedVersion: transaction.version, draft: draft)
        let after = try await repository.dashboard()
        let afterReport = try await repository.report(since: .distantPast)
        XCTAssertFalse(after.transactions.contains(where: { $0.id == transaction.id }))
        XCTAssertTrue(after.splitBills.contains(where: { $0.title == "Konversi uji" }))
        XCTAssertEqual(afterReport.personalExpense, beforeReport.personalExpense - transaction.amount + selfShare)
    }

    @MainActor
    func testOfflineOutboxIsIsolatedByOwner() throws {
        let store = try OfflineStore(inMemory: true)
        let draft = TransactionDraft(id: nil, kind: .expense, amount: 10_000, accountID: "a", categoryID: "c", occurredAt: .now, merchant: nil, note: nil, source: "manual", expectedVersion: nil)
        try store.enqueue(ownerID: "user-a", operation: "create_transaction", payload: draft, baseVersion: nil)
        XCTAssertEqual(try store.count(ownerID: "user-a"), 1)
        XCTAssertEqual(try store.count(ownerID: "user-b"), 0)
    }

    @MainActor
    func testOfflineProjectionSurvivesCacheReloadWithoutChangingServerBalances() async throws {
        let store = try OfflineStore(inMemory: true)
        let server = try await DemoRepository().dashboard()
        try store.cache(server, ownerID: "owner-a")
        let draft = TransactionDraft(id: nil, kind: .expense, amount: 25_000, accountID: "cash", categoryID: "food", occurredAt: .now, merchant: nil, note: nil, source: "manual", expectedVersion: nil)
        let mutationID = try store.enqueue(ownerID: "owner-a", operation: "create_transaction", payload: draft, baseVersion: nil)
        let cached = try XCTUnwrap(store.cachedSnapshot(ownerID: "owner-a"))
        let projected = try store.overlay(cached, ownerID: "owner-a")
        XCTAssertEqual(projected.transactions.first?.id, "local-\(mutationID)")
        XCTAssertEqual(projected.transactions.first?.amount, 25_000)
        XCTAssertTrue(projected.transactions.first?.pendingSync == true)
        XCTAssertEqual(projected.overview, server.overview)
        XCTAssertEqual(try store.overlay(projected, ownerID: "owner-a").transactions.count, projected.transactions.count)
        XCTAssertEqual(try store.overlay(cached, ownerID: "owner-b").transactions.count, server.transactions.count)
        XCTAssertNil(try store.cachedSnapshot(ownerID: "owner-b"))
    }

    @MainActor
    func testOfflineTransferDeleteAndConflictRemainVisibleUntilExplicitDiscard() async throws {
        let store = try OfflineStore(inMemory: true)
        let server = try await DemoRepository().dashboard()
        let transaction = try XCTUnwrap(server.transactions.first)
        let draft = TransferDraft(id: nil, fromAccountID: "cash", toAccountID: "bank", amount: 5_000, occurredAt: .now, note: nil, expectedVersion: nil)
        let transferID = try store.enqueue(ownerID: "owner-a", operation: "create_transfer", payload: draft, baseVersion: nil)
        try store.enqueue(ownerID: "owner-a", operation: "delete_transaction", payload: VersionedID(id: transaction.id, version: transaction.version), baseVersion: transaction.version)
        let projected = try store.overlay(server, ownerID: "owner-a")
        XCTAssertEqual(projected.transfers.first?.id, "local-\(transferID)")
        XCTAssertFalse(projected.transactions.contains { $0.id == transaction.id })
        XCTAssertEqual(projected.overview, server.overview)
        let record = try XCTUnwrap(store.allChanges(ownerID: "owner-a").first)
        try store.markFailed(record, code: "CONFLICT_VERSION")
        XCTAssertEqual(try store.count(ownerID: "owner-a"), 2)
        XCTAssertEqual(try store.pending(ownerID: "owner-a").count, 1)
        XCTAssertEqual(try store.overlay(server, ownerID: "owner-a").transfers.first?.id, "local-\(transferID)")
        try store.discard(mutationID: transferID, ownerID: "owner-b")
        XCTAssertEqual(try store.count(ownerID: "owner-a"), 2)
        try store.discard(mutationID: transferID, ownerID: "owner-a")
        XCTAssertEqual(try store.count(ownerID: "owner-a"), 1)
        try store.clear(ownerID: "owner-a")
        XCTAssertEqual(try store.count(ownerID: "owner-a"), 0)
    }

    @MainActor
    func testOutboxRetriesKeepMutationIDAndBackOff() throws {
        let store = try OfflineStore(inMemory: true)
        let draft = TransactionDraft(id: nil, kind: .expense, amount: 10_000, accountID: "cash", categoryID: "food", occurredAt: .now, merchant: nil, note: nil, source: "manual", expectedVersion: nil)
        let id = try store.enqueue(ownerID: "owner-a", operation: "create_transaction", payload: draft, baseVersion: nil)
        let record = try XCTUnwrap(store.pending(ownerID: "owner-a").first)
        try store.markFailed(record, code: "NETWORK")
        XCTAssertTrue(try store.pending(ownerID: "owner-a").isEmpty)
        XCTAssertEqual(try store.pending(ownerID: "owner-a", forceRetry: true).first?.mutationID, id)
        XCTAssertEqual(record.retryCount, 1)
        XCTAssertGreaterThan(try XCTUnwrap(record.nextRetryAt).timeIntervalSinceNow, 0)
        XCTAssertEqual(try store.count(ownerID: "owner-a"), 1)
    }

    @MainActor
    func testConflictSaveAsNewRequiresExpenseAndChangesMutationID() throws {
        let store = try OfflineStore(inMemory: true)
        let draft = TransactionDraft(id: "server-id", kind: .expense, amount: 10_000, accountID: "cash", categoryID: "food", occurredAt: .now, merchant: nil, note: nil, source: "manual", expectedVersion: 1)
        let id = try store.enqueue(ownerID: "owner-a", operation: "update_transaction", payload: draft, baseVersion: 1)
        let record = try XCTUnwrap(store.pending(ownerID: "owner-a").first)
        XCTAssertThrowsError(try store.saveConflictAsNew(mutationID: id, ownerID: "owner-a"))
        try store.markFailed(record, code: "CONFLICT_VERSION")
        XCTAssertThrowsError(try store.saveConflictAsNew(mutationID: id, ownerID: "owner-b"))
        try store.saveConflictAsNew(mutationID: id, ownerID: "owner-a")
        XCTAssertNotEqual(record.mutationID, id)
        XCTAssertEqual(record.operation, "create_transaction")
        let copied = try JSONDecoder.danarapi.decode(TransactionDraft.self, from: record.payload)
        XCTAssertNil(copied.id)
        XCTAssertNil(copied.expectedVersion)
        XCTAssertEqual(copied.amount, draft.amount)
    }

    @MainActor
    func testDemoExportCreatesZipWithRequiredFiles() async throws {
        let repository = DemoRepository()
        let url = try await repository.exportArchive()
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        let raw = String(decoding: data, as: UTF8.self)
        for name in ["data-v1.json", "personal_expenses.csv", "cash_flow.csv", "split_bills.csv", "split_members.csv", "split_settlements.csv", "split_resolutions.csv", "manifest.json"] {
            XCTAssertTrue(raw.contains(name), "ZIP harus memuat \(name)")
        }
    }

    private func importFixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "import-v1", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
