import Foundation

protocol FinanceRepository: Sendable {
    var isDemo: Bool { get }

    func dashboard() async throws -> DashboardSnapshot
    func transactionPage(after cursor: TransactionCursor) async throws -> TransactionPage
    func transaction(id: String) async throws -> FinanceTransaction
    func planningHistory(_ request: PlanningHistoryRequest) async throws -> PlanningHistoryPage
    func copyBudgets(from: Date, to: Date) async throws
    func report(since startDate: Date, until endDate: Date?) async throws -> ReportSummary
    func resetDemo() async throws

    func createAccount(_ draft: AccountDraft) async throws
    func updateAccount(_ account: FinancialAccount) async throws
    func editAccount(_ account: FinancialAccount, expectedBalance: Int64, reason: String) async throws
    func deleteAccount(id: String, expectedVersion: Int) async throws
    func archiveAccount(id: String, expectedVersion: Int) async throws
    func createCategory(name: String, kind: TransactionKind) async throws
    func updateCategory(_ category: Category) async throws
    func archiveCategory(id: String, expectedVersion: Int) async throws
    func deleteCategory(id: String, expectedVersion: Int) async throws

    func saveTransaction(_ draft: TransactionDraft) async throws
    func deleteTransaction(id: String, expectedVersion: Int) async throws
    func restoreTransaction(id: String, expectedVersion: Int) async throws
    func createTransfer(_ draft: TransferDraft) async throws
    func deleteTransfer(id: String, expectedVersion: Int) async throws

    func calculateEqualSplit(total: Int64, participants: [EqualParticipant]) async throws -> [String: Int64]
    func calculatePercentageSplit(total: Int64, participants: [PercentageParticipant]) async throws -> [String: Int64]
    func calculateItemSplit(_ draft: ItemSplit, memberIDs: [String]) async throws -> ItemSplitResult
    func scanReceipt(images: [ReceiptScanImage]) async throws -> ReceiptScanResponse
    func scanBankProof(_ request: BankProofRequest, ownerID: String) async throws -> BankProofResponse
    func setSharedProofAIConsent(ownerID: String, policyVersion: String) async throws
    func createSplitBill(_ draft: SplitBillDraft) async throws
    func createSplitBillFromReview(reviewItemID: String, draft: SplitBillDraft) async throws
    func convertTransactionToSplitBill(transactionID: String, expectedVersion: Int, draft: SplitBillDraft) async throws
    func updateSplitBill(id: String, expectedVersion: Int, draft: SplitBillDraft) async throws
    func deleteSplitBill(id: String, expectedVersion: Int) async throws
    func restoreSplitBill(id: String, expectedVersion: Int) async throws
    func recordSettlement(_ draft: SettlementDraft) async throws
    func reverseSettlement(id: String, expectedVersion: Int, reason: String) async throws
    func recordResolution(_ draft: ResolutionDraft) async throws
    func reverseResolution(id: String, expectedVersion: Int, reason: String) async throws

    func addReviewItem(_ item: ReviewItem, attachment: ReviewAttachment?) async throws
    func addSharedReviewItem(_ item: ReviewItem, attachment: ReviewAttachment?, ownerID: String) async throws
    func updateReviewItem(_ item: ReviewItem) async throws
    func rejectReviewItem(id: String) async throws
    func deleteReviewItem(id: String) async throws
    func restoreReviewItem(id: String) async throws
    func confirmReviewItem(id: String, transaction: TransactionDraft) async throws
    func confirmSharedReviewItem(id: String, transaction: TransactionDraft, ownerID: String) async throws
    func confirmSharedReviewTransfer(id: String, transfer: TransferDraft, ownerID: String) async throws
    func mergeReviewItem(id: String, into transactionID: String) async throws
    func clearReviewDuplicate(id: String) async throws
    func completeReviewItem(id: String) async throws

    func saveMerchantRule(_ rule: MerchantRule) async throws
    func deleteMerchantRule(id: String, expectedVersion: Int) async throws

    func upsertBudget(categoryID: String, month: Date, limit: Int64) async throws
    func deleteBudget(id: String, expectedLimit: Int64) async throws
    func saveGoal(_ goal: SavingsGoal) async throws
    func deleteGoal(id: String, expectedVersion: Int) async throws
    func exportArchive() async throws -> URL
    func requestAccountDeletion(password: String) async throws
    func replayOutbox(operation: String, mutationID: String, payload: Data) async throws
    func aiConsentState() async throws -> AIConsentState
    func setAIConsent(granted: Bool, policyVersion: String) async throws
    func setTimezone(_ timezone: String) async throws
    func acknowledgeRetention() async throws
    func supportTickets() async throws -> [SupportTicket]
    func sendSupportTicket(id: String, topic: String, description: String, requestID: String?) async throws
}

extension FinanceRepository {
    func editAccount(_ account: FinancialAccount, expectedBalance: Int64, reason: String) async throws { throw AppError.validation("Penyesuaian saldo tidak tersedia.") }
    func deleteAccount(id: String, expectedVersion: Int) async throws { throw AppError.validation("Penghapusan akun tidak tersedia.") }
    func deleteCategory(id: String, expectedVersion: Int) async throws { throw AppError.validation("Penghapusan kategori tidak tersedia.") }
    func deleteReviewItem(id: String) async throws { throw AppError.validation("Penghapusan draft tidak tersedia.") }
    func deleteBudget(id: String, expectedLimit: Int64) async throws { throw AppError.validation("Penghapusan anggaran tidak tersedia.") }
    func confirmSharedReviewItem(id: String, transaction: TransactionDraft, ownerID: String) async throws {
        try await confirmReviewItem(id: id, transaction: transaction)
    }
    func confirmSharedReviewTransfer(id: String, transfer: TransferDraft, ownerID: String) async throws {
        throw AppError.validation("Transfer bukti Share memerlukan akun nyata.")
    }
    func addSharedReviewItem(_ item: ReviewItem, attachment: ReviewAttachment?, ownerID: String = "demo") async throws {
        if try await dashboard().reviewItems.contains(where: { $0.matchesID(item.id) }) { return }
        try await addReviewItem(item, attachment: attachment)
    }
    func transaction(id: String) async throws -> FinanceTransaction {
        guard let value = try await dashboard().transactions.first(where: { $0.id == id }) else { throw AppError.validation("Transaksi tidak tersedia.") }
        return value
    }
    func planningHistory(_ request: PlanningHistoryRequest) async throws -> PlanningHistoryPage {
        let data = try await dashboard()
        var items = data.transactions.filter { !$0.deleted && $0.kind == .expense && (request.goalID == nil || $0.goalID == request.goalID) && (request.categoryID == nil || $0.categoryID == request.categoryID) }.map { PlanningEntry(id: $0.id, sourceID: $0.id, kind: "transaction", amount: $0.amount, occurredAt: $0.occurredAt, merchant: $0.merchant, note: $0.note) }
        if let category = request.categoryID {
            items += data.splitBills.filter { !$0.deleted && $0.categoryID == category && $0.selfShare > 0 }.map { PlanningEntry(id: $0.id, sourceID: $0.id, kind: "split_bill", amount: $0.selfShare, occurredAt: $0.occurredAt, merchant: $0.title, note: nil) }
        }
        items = items.filter { (request.startDate == nil || $0.occurredAt >= request.startDate!) && (request.endDate == nil || $0.occurredAt < request.endDate!) }.sorted { $0.occurredAt == $1.occurredAt ? $0.id > $1.id : $0.occurredAt > $1.occurredAt }
        let start = request.cursor.flatMap { cursor in items.firstIndex(where: { $0.id == cursor.id }).map { $0 + 1 } } ?? 0
        let page = Array(items.dropFirst(start).prefix(30))
        return PlanningHistoryPage(items: page, nextCursor: start + 30 < items.count ? page.last.map { TransactionCursor(occurredAt: $0.occurredAt, id: $0.id) } : nil)
    }
    func copyBudgets(from: Date, to: Date) async throws {
        let data = try await dashboard()
        for budget in data.budgets where MonthPeriod.key(budget.month) == MonthPeriod.key(from) && !data.budgets.contains(where: { $0.categoryID == budget.categoryID && MonthPeriod.key($0.month) == MonthPeriod.key(to) }) {
            try await upsertBudget(categoryID: budget.categoryID, month: to, limit: budget.limitAmount)
        }
    }
    func aiConsentState() async throws -> AIConsentState { AIConsentState(granted: false, policyVersion: nil, updatedAt: nil) }
    func setAIConsent(granted: Bool, policyVersion: String) async throws { throw AppError.validation("Masuk untuk mengubah persetujuan AI.") }
    func setTimezone(_ timezone: String) async throws {}
    func acknowledgeRetention() async throws { throw AppError.validation("Masuk untuk mencatat penerimaan kebijakan.") }
    func supportTickets() async throws -> [SupportTicket] { [] }
    func sendSupportTicket(id: String, topic: String, description: String, requestID: String?) async throws { throw AppError.validation("Masuk untuk mengirim laporan privat.") }
    func scanReceipt(images: [ReceiptScanImage]) async throws -> ReceiptScanResponse { ReceiptScanResponse(status: "config_error", data: nil) }
    func scanBankProof(_ request: BankProofRequest, ownerID: String) async throws -> BankProofResponse { throw AppError.validation("Masuk akun untuk membaca bukti dengan AI.") }
    func setSharedProofAIConsent(ownerID: String, policyVersion: String) async throws { throw AppError.validation("Persetujuan AI memerlukan akun nyata.") }
    func report(since startDate: Date) async throws -> ReportSummary { try await report(since: startDate, until: nil) }
}

enum RepositoryFactory {
    static func demo() -> any FinanceRepository {
        DemoRepository(showcaseDate: .now)
    }

    static func remote(configuration: SupabaseConfiguration, sessionStore: KeychainSessionStore) -> any FinanceRepository {
        RemoteRepository(configuration: configuration, sessionStore: sessionStore)
    }
}
