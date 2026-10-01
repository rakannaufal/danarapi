import Foundation

protocol FinanceRepository: Sendable {
    var isDemo: Bool { get }

    func dashboard() async throws -> DashboardSnapshot
    func transactionPage(after cursor: TransactionCursor) async throws -> TransactionPage
    func report(since startDate: Date, until endDate: Date?) async throws -> ReportSummary
    func resetDemo() async throws

    func createAccount(_ draft: AccountDraft) async throws
    func updateAccount(_ account: FinancialAccount) async throws
    func archiveAccount(id: String, expectedVersion: Int) async throws
    func createCategory(name: String, kind: TransactionKind) async throws
    func updateCategory(_ category: Category) async throws
    func archiveCategory(id: String, expectedVersion: Int) async throws

    func saveTransaction(_ draft: TransactionDraft) async throws
    func deleteTransaction(id: String, expectedVersion: Int) async throws
    func restoreTransaction(id: String, expectedVersion: Int) async throws
    func createTransfer(_ draft: TransferDraft) async throws
    func deleteTransfer(id: String, expectedVersion: Int) async throws

    func calculateEqualSplit(total: Int64, participants: [EqualParticipant]) async throws -> [String: Int64]
    func calculatePercentageSplit(total: Int64, participants: [PercentageParticipant]) async throws -> [String: Int64]
    func calculateItemSplit(_ draft: ItemSplit, memberIDs: [String]) async throws -> ItemSplitResult
    func scanReceipt(images: [ReceiptScanImage]) async throws -> ReceiptScanResponse
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
    func updateReviewItem(_ item: ReviewItem) async throws
    func rejectReviewItem(id: String) async throws
    func restoreReviewItem(id: String) async throws
    func confirmReviewItem(id: String, transaction: TransactionDraft) async throws
    func mergeReviewItem(id: String, into transactionID: String) async throws
    func clearReviewDuplicate(id: String) async throws
    func completeReviewItem(id: String) async throws

    func saveMerchantRule(_ rule: MerchantRule) async throws
    func deleteMerchantRule(id: String, expectedVersion: Int) async throws

    func upsertBudget(categoryID: String, month: Date, limit: Int64) async throws
    func saveGoal(_ goal: SavingsGoal) async throws
    func deleteGoal(id: String, expectedVersion: Int) async throws
    func exportArchive() async throws -> URL
    func requestAccountDeletion(password: String) async throws
    func replayOutbox(operation: String, mutationID: String, payload: Data) async throws
}

extension FinanceRepository {
    func scanReceipt(images: [ReceiptScanImage]) async throws -> ReceiptScanResponse { ReceiptScanResponse(status: "config_error", data: nil) }
    func report(since startDate: Date) async throws -> ReportSummary { try await report(since: startDate, until: nil) }
}

enum RepositoryFactory {
    static func demo() -> any FinanceRepository {
        DemoRepository()
    }

    static func remote(configuration: SupabaseConfiguration, sessionStore: KeychainSessionStore) -> any FinanceRepository {
        RemoteRepository(configuration: configuration, sessionStore: sessionStore)
    }
}
