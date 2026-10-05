import Foundation
import UIKit
import XCTest
@testable import Danarapi

final class SharedInboxTests: XCTestCase {
    private func inbox() -> (SharedInbox, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (SharedInbox(root: root), root)
    }
    private let bankText = "BSI\nTransfer Berhasil\nNominal Transfer: Rp 150.000,00\nBiaya Admin: Rp 2.500,00\nSaldo: Rp 9.000.000,00\nNomor Rekening: 7123456789\nNama Penerima: KEDAI UJI\nTanggal: 05/10/2026 09:30:00"

    func testBankNominalExcludesFeeBalanceAndAccountNumber() throws {
        let result = BankReceiptParser.parse(bankText)
        XCTAssertEqual(result.amount, 150_000)
        XCTAssertEqual(result.merchant, "KEDAI UJI")
        XCTAssertNotNil(result.date)
        XCTAssertTrue(result.warning?.contains("biaya admin") == true)
    }
    func testBankMultilineLabelsAndForeignFormats() {
        XCTAssertEqual(BankReceiptParser.parse("Nominal Transaksi\nIDR 1,250,000.00\nNama Penerima\nTOKO TEST").amount, 1_250_000)
        XCTAssertEqual(BankReceiptParser.parse("Nominal: Rp500\nNominal: Rp500").amount, 500)
        XCTAssertNil(BankReceiptParser.rupiah("USD 100"))
        XCTAssertNil(BankReceiptParser.rupiah("150.000,50"))
        XCTAssertNil(BankReceiptParser.rupiah("15.00.000"))
        XCTAssertNil(BankReceiptParser.rupiah("0"))
    }
    func testAmbiguousFailedOrUnlabeledBankAmountRequiresManualReview() {
        for text in ["Saldo Rp9.000.000\nBiaya Admin Rp2.500", "Nominal: Rp150.000\nNominal: Rp175.000", "Nominal: Rp150.000\nNominal: USD150", "Transfer Gagal\nNominal: Rp150.000", "Status Pending\nNominal: Rp150.000", "Total Debit: Rp152.500", "Nomor Rekening: 7123456789"] {
            XCTAssertNil(BankReceiptParser.parse(text).amount, text)
        }
        XCTAssertNil(BankReceiptParser.parse("Tanggal: 30/02/2026").date)
    }
    func testAtomicBatchPersistsAcrossRestartAndDeduplicates() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = try SharedPayload.text(bankText)
        let records = try store.save([payload, payload])
        XCTAssertEqual(records[0].id, records[1].id)
        let restarted = SharedInbox(root: root)
        XCTAssertEqual(try restarted.records().count, 1)
        XCTAssertEqual(try restarted.save([payload]).first?.id, records.first?.id)
        XCTAssertEqual(try restarted.data(for: records[0].id, ownerID: nil), payload.data)
        XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }
    func testBatchWithUnsupportedOrOversizedProofWritesNothing() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let good = try SharedPayload.text(bankText)
        XCTAssertThrowsError(try store.save([good, SharedPayload(name: "bad.exe", data: Data([0, 1, 2]), context: "")]))
        XCTAssertThrowsError(try store.save([good, SharedPayload(name: "huge.pdf", data: Data(repeating: 65, count: SharedInbox.maximumFileBytes + 1), context: "")]))
        XCTAssertThrowsError(try store.save(Array(repeating: good, count: 6)))
        XCTAssertThrowsError(try SharedPayload.text("https://bank.example/receipt"))
        XCTAssertNoThrow(try SharedPayload.text("Nominal:Rp150000"))
        XCTAssertThrowsError(try SharedPayload.text(String(repeating: "x", count: SharedInbox.maximumTextBytes + 1)))
        XCTAssertTrue(try store.records().isEmpty)
    }
    func testBindingPreventsAccountSwitchFromImportingOrReadingPreviousProof() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try XCTUnwrap(store.save([try .text(bankText)], ownerID: "account-A").first)
        _ = try store.bind(record.id, to: "account-A")
        XCTAssertTrue(try store.records(ownerID: "account-B").isEmpty)
        XCTAssertTrue(try store.records(ownerID: nil).isEmpty)
        XCTAssertThrowsError(try store.data(for: record.id, ownerID: "account-B"))
        XCTAssertThrowsError(try store.bind(record.id, to: "account-B"))
        XCTAssertThrowsError(try store.markImported(record.id, ownerID: "account-B"))
        XCTAssertThrowsError(try store.remove(record.id, ownerID: "account-B"))
        try store.markImported(record.id, ownerID: "account-A")
        XCTAssertTrue(try XCTUnwrap(store.records(ownerID: "account-A").first).imported)
        XCTAssertEqual(try store.save([try .text(bankText)], ownerID: "account-A").first?.id, record.id)
    }
    func testPayloadTamperingDetectedAndMissingPayloadCanBeRemoved() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try XCTUnwrap(store.save([try .text("Nominal: Rp500")]).first)
        let batch = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { UUID(uuidString: $0.lastPathComponent) != nil })
        let file = batch.appendingPathComponent(record.id + ".payload")
        try Data("Nominal: Rp600".utf8).write(to: file)
        XCTAssertThrowsError(try store.data(for: record.id, ownerID: nil))
        try FileManager.default.removeItem(at: file)
        try store.remove(record.id, ownerID: nil)
        XCTAssertTrue(try store.records().isEmpty)
        XCTAssertThrowsError(try store.data(for: "../../outside", ownerID: nil))
    }
    func testNewAccountStartsEmptyAndDuplicateProofsAreIsolatedPerOwner() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = try SharedPayload.text(bankText)
        try store.setActiveAccount("account-A")
        let targetA = try store.activeAccount()
        let receiptA = try XCTUnwrap(store.save([payload], ownerID: "account-A", expectedAccount: targetA).first)
        XCTAssertEqual(receiptA.ownerID, "account-A")
        try store.setActiveAccount("account-B")
        XCTAssertTrue(try store.records(ownerID: "account-B").isEmpty)
        let receiptB = try XCTUnwrap(store.save([payload], ownerID: "account-B", expectedAccount: store.activeAccount()).first)
        XCTAssertNotEqual(receiptA.id, receiptB.id)
        XCTAssertEqual(try store.records(ownerID: "account-A").map(\.id), [receiptA.id])
        XCTAssertEqual(try store.records(ownerID: "account-B").map(\.id), [receiptB.id])
        XCTAssertThrowsError(try store.data(for: receiptA.id, ownerID: "account-B"))
        XCTAssertThrowsError(try store.remove(receiptA.id, ownerID: "account-B"))
        try store.setActiveAccount(nil)
        XCTAssertThrowsError(try store.activeAccount())
        XCTAssertTrue(try store.records().isEmpty)
        try store.setActiveAccount("account-A")
        XCTAssertEqual(try store.records(ownerID: "account-A").map(\.id), [receiptA.id])
    }
    func testAccountChangeAndLogoutInvalidateOpenShareSheetEvenAfterReturningToSameAccount() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = try SharedPayload.text(bankText)
        try store.setActiveAccount("account-A")
        let target = try store.activeAccount()
        try store.setActiveAccount("account-B")
        XCTAssertThrowsError(try store.save([payload], ownerID: "account-A", expectedAccount: target))
        try store.setActiveAccount("account-A")
        XCTAssertThrowsError(try store.save([payload], ownerID: "account-A", expectedAccount: target))
        let current = try store.activeAccount()
        try store.setActiveAccount(nil)
        XCTAssertThrowsError(try store.save([payload], ownerID: "account-A", expectedAccount: current))
        XCTAssertTrue(try store.records(ownerID: "account-A").isEmpty)
    }
    func testLegacyUnownedProofNeverAppearsOrBindsToNewAccount() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let receipt = try XCTUnwrap(store.save([try .text(bankText)]).first)
        for owner in ["account-A", "account-B"] {
            XCTAssertTrue(try store.records(ownerID: owner).isEmpty)
            XCTAssertThrowsError(try store.data(for: receipt.id, ownerID: owner))
            XCTAssertThrowsError(try store.bind(receipt.id, to: owner))
            XCTAssertThrowsError(try store.remove(receipt.id, ownerID: owner))
        }
        XCTAssertEqual(try store.records().first?.id, receipt.id)
    }
    func testCapacityStillAllowsRetryOfExistingReceipt() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<50 { try store.save([try .text("Nominal: Rp\(index + 1)")]) }
        XCTAssertEqual(try store.records().count, 50)
        XCTAssertNoThrow(try store.save([try .text("Nominal: Rp1")]))
        XCTAssertThrowsError(try store.save([try .text("Nominal: Rp51")]))
    }
    func testConcurrentWritersDoNotCreateDuplicateDrafts() async throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let payload = try SharedPayload.text(bankText)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try store.save([payload]) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(try store.records().count, 1)
    }
    @MainActor func testTransferAttemptSurvivesRestartWithSameFields() throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try XCTUnwrap(store.save([try .text(bankText)], ownerID: "owner-A").first)
        _ = try store.bind(record.id, to: "owner-A")
        try store.markImported(record.id, ownerID: "owner-A")
        let draft = TransferDraft(id: nil, fromAccountID: "from", toAccountID: "to", amount: 150_000, occurredAt: .now, note: "Share", expectedVersion: nil)
        let bytes = try JSONEncoder.danarapi.encode(draft)
        try store.rememberTransfer(record.id, ownerID: "owner-A", draft: bytes)
        let restarted = SharedInbox(root: root)
        let persisted = try XCTUnwrap(restarted.records(ownerID: "owner-A").first?.transferDraft)
        XCTAssertEqual(persisted, bytes)
        XCTAssertNoThrow(try restarted.rememberTransfer(record.id, ownerID: "owner-A", draft: persisted))
        XCTAssertThrowsError(try restarted.rememberTransfer(record.id, ownerID: "owner-A", draft: Data("changed".utf8)))
        XCTAssertThrowsError(try restarted.rememberTransfer(record.id, ownerID: "owner-B", draft: persisted))
        XCTAssertEqual(try JSONDecoder.danarapi.decode(TransferDraft.self, from: persisted).amount, draft.amount)
    }
    @MainActor func testSharedReaderKeepsStableIDOriginalEvidenceAndUnknownFields() async throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(bankText.utf8)
        let record = try XCTUnwrap(store.save([SharedPayload(name: "../../bank.txt", data: data, context: "Nominal: Rp999.000")]).first)
        XCTAssertEqual(record.name, "bank.txt")
        let review = await SharedReceiptReader.read(record, data: data)
        XCTAssertEqual(review.id, record.id)
        XCTAssertEqual(review.status, .pending)
        XCTAssertEqual(review.amount.value, "150000")
        XCTAssertEqual(review.amount.confidence, .low)
        XCTAssertTrue(review.rawReference?.contains("Nominal: Rp999.000") == true)
        XCTAssertNil(review.receipt)
    }
    @MainActor func testUnreadableImageStillBecomesEditableDraftWithOriginalAttachment() async throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([0xff, 0xd8, 0xff, 0x00])
        let record = try XCTUnwrap(store.save([SharedPayload(name: "bad.jpg", data: bytes, context: "")]).first)
        let review = await SharedReceiptReader.read(record, data: bytes)
        XCTAssertEqual(review.status, .pending)
        XCTAssertNil(review.amount.value)
        XCTAssertEqual(review.attachmentName, "bad.jpg")
        XCTAssertTrue(review.rawReference?.contains("Foto tidak dapat dibaca") == true)
    }
    @MainActor func testShareImportIsIdempotentAndDoesNotAffectLedger() async throws {
        let repository = DemoRepository()
        let initial = try await repository.dashboard()
        let review = ImportService.reviewFromText("Nominal: Rp150000")
        try await repository.addSharedReviewItem(review, attachment: nil)
        try await repository.addSharedReviewItem(review, attachment: nil)
        let result = try await repository.dashboard()
        XCTAssertEqual(result.reviewItems.filter { $0.id == review.id }.count, 1)
        XCTAssertEqual(result.transactions, initial.transactions)
        XCTAssertEqual(result.accounts, initial.accounts)
        XCTAssertEqual(result.transfers, initial.transfers)
    }
    @MainActor func testSignedOutAndDemoCannotUploadPersonalShareProof() async throws {
        let (store, root) = inbox(); defer { try? FileManager.default.removeItem(at: root) }
        let record = try XCTUnwrap(store.save([try .text(bankText)]).first)
        let app = AppModel(offlineStore: try OfflineStore(inMemory: true), sharedInbox: store)
        let review = await SharedReceiptReader.read(record, data: Data(bankText.utf8))
        let signedOut = await app.importSharedProof(record, review: review)
        XCTAssertFalse(signedOut)
        await app.startDemo()
        let demo = await app.importSharedProof(record, review: review)
        XCTAssertFalse(demo)
        XCTAssertNil(try store.records().first?.ownerID)
        XCTAssertFalse(try XCTUnwrap(store.records().first).imported)
    }
}

final class SharedReceiptTransportTests: XCTestCase {
    @MainActor private func fixture() throws -> (RemoteRepository, KeychainSessionStore, URLSession) {
        let store = KeychainSessionStore(service: "id.danarapi.share.tests.\(UUID().uuidString)")
        try store.save(AuthSession(accessToken: "synthetic-A", refreshToken: "synthetic-refresh", userID: "owner-A", email: nil, expiresAt: .distantFuture))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SharedReceiptStub.self]
        let session = URLSession(configuration: config)
        SharedReceiptStub.state.reset()
        return (RemoteRepository(configuration: SupabaseConfiguration(url: URL(string: "https://example.invalid")!, anonKey: "sb_publishable_test"), sessionStore: store, session: session), store, session)
    }
    private var attachment: ReviewAttachment { ReviewAttachment(name: "synthetic.jpg", mimeType: "image/jpeg", data: Data([0xff, 0xd8, 0xff, 0x01])) }

    @MainActor func testAIRequestAndAutomaticConsentPinOwnerWithoutPostingLedger() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        try await repository.setSharedProofAIConsent(ownerID: "owner-A", policyVersion: ProductCatalog.policyVersion)
        let response = try await repository.scanBankProof(BankProofRequest(images: [], text: "Bukti sintetis"), ownerID: "owner-A")
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.proof?.amount, 45900)
        let requests = SharedReceiptStub.state.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-A" })
        XCTAssertFalse(requests.contains { $0.url?.path.contains("ledger") == true })
        let consent = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(consent["operation"] as? String, "set_ai_consent")
        XCTAssertEqual((consent["payload"] as? [String: Any])?["granted"] as? Bool, true)
        let scan = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(scan["purpose"] as? String, "bank_proof")
        XCTAssertEqual(scan["text"] as? String, "Bukti sintetis")
        XCTAssertEqual(requests[1].timeoutInterval, 110)
    }
    @MainActor func testAIAndAutomaticConsentRejectAnotherAccountBeforeSending() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        do { _ = try await repository.scanBankProof(BankProofRequest(images: [], text: "Bukti pribadi"), ownerID: "owner-B"); XCTFail("Wrong owner accepted") } catch { XCTAssertTrue(error is AppError) }
        do { try await repository.setSharedProofAIConsent(ownerID: "owner-B", policyVersion: ProductCatalog.policyVersion); XCTFail("Wrong owner accepted") } catch { XCTAssertTrue(error is AppError) }
        XCTAssertTrue(SharedReceiptStub.state.requests.isEmpty)
    }

    @MainActor func testUploadTimeoutRetainsDraftAndRetryFindsExistingAttachment() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        SharedReceiptStub.state.configure(timeoutUpload: true)
        let review = ImportService.reviewFromText("Nominal: Rp150000")
        do { try await repository.addSharedReviewItem(review, attachment: attachment, ownerID: "owner-A"); XCTFail("Expected upload timeout") }
        catch { XCTAssertTrue(error is URLError) }
        try await repository.addSharedReviewItem(review, attachment: attachment, ownerID: "owner-A")
        let requests = SharedReceiptStub.state.requests
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/attachment") == true }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path.hasSuffix("/ios-data") == true }.count, 2)
        for request in requests.filter({ $0.url?.path.hasSuffix("/ios-data") == true }) {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertEqual(body["operation"] as? String, "add_review_item")
            XCTAssertEqual((body["payload"] as? [String: Any])?["id"] as? String, review.id)
        }
        XCTAssertFalse(requests.contains { $0.url?.path.contains("ledger") == true || $0.url?.path.contains("rpc") == true })
        XCTAssertTrue(requests.filter { $0.url?.path.contains("/rest/") == true }.allSatisfy { $0.httpMethod == "GET" })
    }
    @MainActor func testOwnerMismatchRejectsBeforeSendingProof() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        do { try await repository.addSharedReviewItem(ImportService.reviewFromText("Nominal: Rp150000"), attachment: attachment, ownerID: "owner-B"); XCTFail("Owner mismatch accepted") }
        catch { XCTAssertTrue(error is AppError) }
        XCTAssertTrue(SharedReceiptStub.state.requests.isEmpty)
    }
    @MainActor func testAccountChangeDuringImportStopsRemainingRequests() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        SharedReceiptStub.state.configure(onCreate: {
            try? store.save(AuthSession(accessToken: "synthetic-B", refreshToken: "synthetic-refresh-B", userID: "owner-B", email: nil, expiresAt: .distantFuture))
        })
        do { try await repository.addSharedReviewItem(ImportService.reviewFromText("Nominal: Rp150000"), attachment: attachment, ownerID: "owner-A"); XCTFail("Changed account accepted") }
        catch { XCTAssertTrue(error is AppError) }
        XCTAssertEqual(SharedReceiptStub.state.requests.count, 1)
        XCTAssertEqual(SharedReceiptStub.state.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-A")
    }
    @MainActor func testAlreadyProcessedDraftCannotBeRecreatedAsPending() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        SharedReceiptStub.state.configure(status: "saved")
        do { try await repository.addSharedReviewItem(ImportService.reviewFromText("Nominal: Rp150000"), attachment: attachment, ownerID: "owner-A"); XCTFail("Processed draft accepted") }
        catch { XCTAssertTrue((error as? AppError)?.message.contains("sudah diproses") == true) }
        XCTAssertFalse(SharedReceiptStub.state.requests.contains { $0.url?.path.hasSuffix("/attachment") == true })
    }
    @MainActor func testIncomeConfirmationPinsAccountAndPreservesTransactionKind() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        let id = UUID().uuidString.lowercased()
        let transaction = TransactionDraft(id: nil, kind: .income, amount: 150_000, accountID: "bank", categoryID: "income", occurredAt: .now, merchant: "Synthetic", note: nil, source: "review", expectedVersion: nil)
        do { try await repository.confirmSharedReviewItem(id: id, transaction: transaction, ownerID: "owner-B"); XCTFail("Wrong account accepted") }
        catch { XCTAssertTrue(error is AppError) }
        XCTAssertTrue(SharedReceiptStub.state.requests.isEmpty)
        try await repository.confirmSharedReviewItem(id: id, transaction: transaction, ownerID: "owner-A")
        let request = try XCTUnwrap(SharedReceiptStub.state.requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let payload = try XCTUnwrap(body["payload"] as? [String: Any])
        XCTAssertEqual(body["operation"] as? String, "confirm_review_item")
        XCTAssertEqual(payload["id"] as? String, id)
        XCTAssertEqual((payload["transaction"] as? [String: Any])?["kind"] as? String, "income")
    }
    @MainActor func testTransferCompletionRetryUsesSameLedgerMutationID() async throws {
        let (repository, store, session) = try fixture()
        defer { store.clear(); session.invalidateAndCancel() }
        let reviewID = UUID().uuidString.lowercased()
        let transfer = TransferDraft(id: nil, fromAccountID: "from", toAccountID: "to", amount: 150_000, occurredAt: .now, note: "Share", expectedVersion: nil)
        SharedReceiptStub.state.configure(timeoutCompletion: true)
        do { try await repository.confirmSharedReviewTransfer(id: reviewID, transfer: transfer, ownerID: "owner-A"); XCTFail("Expected completion failure") }
        catch { XCTAssertTrue((error as? AppError)?.message.contains("Transfer telah tersimpan") == true) }
        SharedReceiptStub.state.configure()
        try await repository.confirmSharedReviewTransfer(id: reviewID, transfer: transfer, ownerID: "owner-A")
        let requests = SharedReceiptStub.state.requests.filter { $0.url?.path.hasSuffix("/ledger") == true }
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
            XCTAssertEqual(body["operation"] as? String, "create_transfer")
            XCTAssertEqual((body["payload"] as? [String: Any])?["p_client_mutation_id"] as? String, reviewID)
        }
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
    }
}

private final class SharedReceiptStub: URLProtocol, @unchecked Sendable {
    static let state = State()
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [URLRequest] = []
        private var uploaded = false
        private var timeoutUpload = false
        private var timeoutCompletion = false
        private var status = "pending"
        private var onCreate: (@Sendable () -> Void)?
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return values }
        func reset() { lock.lock(); defer { lock.unlock() }; values = []; uploaded = false; timeoutUpload = false; timeoutCompletion = false; status = "pending"; onCreate = nil }
        func configure(timeoutUpload: Bool = false, timeoutCompletion: Bool = false, status: String = "pending", onCreate: (@Sendable () -> Void)? = nil) {
            lock.lock(); defer { lock.unlock() }; self.timeoutUpload = timeoutUpload; self.timeoutCompletion = timeoutCompletion; self.status = status; self.onCreate = onCreate
        }
        func response(_ request: URLRequest) -> (String, Bool, (@Sendable () -> Void)?) {
            lock.lock(); defer { lock.unlock() }; values.append(request)
            if timeoutCompletion, let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any], json["operation"] as? String == "complete_review_item" { return ("{}", true, nil) }
            switch request.url?.path {
            case "/functions/v1/receipt-scan": return (#"{"status":"ok","proof":{"amount":45900,"merchant":"Tokopedia","recipient":null,"date":"2026-10-05","time":"10:23:50","utc_offset":null,"fee":0,"total":45900,"currency":"IDR","provider":"BSI","reference":null,"transaction_type":"payment","transaction_status":"success","unreadable_fields":[],"warnings":[]}}"#, false, nil)
            case "/rest/v1/review_items": return ("[{\"status\":\"\(status)\"}]", false, nil)
            case "/rest/v1/attachments": return (uploaded ? "[{\"id\":\"existing\"}]" : "[]", false, nil)
            case "/functions/v1/ios-data/attachment": uploaded = true; return ("{}", timeoutUpload, nil)
            default: return ("{}", false, onCreate)
            }
        }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = bytes
        }
        let (body, timeout, callback) = Self.state.response(captured)
        callback?()
        if timeout { client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
