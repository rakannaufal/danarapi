import Foundation
import CryptoKit

actor RemoteRepository: FinanceRepository {
    nonisolated let isDemo = false
    private let client: SupabaseHTTPClient
    private var pendingMutationIDs: [String: String] = [:]

    init(configuration: SupabaseConfiguration, sessionStore: KeychainSessionStore, session: URLSession = .shared) {
        client = SupabaseHTTPClient(configuration: configuration, sessionStore: sessionStore, session: session)
    }

    func dashboard() async throws -> DashboardSnapshot {
        try await client.request(path: "/functions/v1/ios-data/dashboard", body: Optional<NoPayload>.none)
    }

    func transactionPage(after cursor: TransactionCursor) async throws -> TransactionPage {
        try await client.request(path: "/functions/v1/ios-data/transactions", body: TransactionPageRequest(cursor: cursor))
    }

    func report(since startDate: Date, until endDate: Date?) async throws -> ReportSummary {
        try await client.request(path: "/functions/v1/ios-data/report", body: ReportRequest(startDate: startDate, endDate: endDate))
    }

    func resetDemo() async throws {}
    func scanReceipt(images: [ReceiptScanImage]) async throws -> ReceiptScanResponse {
        try await client.request(path: "/functions/v1/receipt-scan", body: ReceiptScanRequest(images: images), timeout: 110)
    }

    func createAccount(_ draft: AccountDraft) async throws {
        try await ledger("create_account", payload: [
            "p_client_mutation_id": UUID().uuidString,
            "p_name": draft.name,
            "p_kind": draft.kind.rawValue,
            "p_opening_balance": String(draft.openingBalance),
            "p_opened_at": ISO8601DateFormatter().string(from: draft.openedAt)
        ])
    }

    func updateAccount(_ account: FinancialAccount) async throws {
        try await dataAction("update_account", payload: try dictionary(account))
    }

    func archiveAccount(id: String, expectedVersion: Int) async throws {
        try await dataAction("archive_account", payload: ["id": id, "expected_version": expectedVersion])
    }

    func createCategory(name: String, kind: TransactionKind) async throws {
        try await ledger("create_category", payload: ["p_client_mutation_id": UUID().uuidString, "p_name": name, "p_kind": kind.rawValue, "p_sort_order": 0])
    }

    func updateCategory(_ category: Category) async throws { try await dataAction("update_category", payload: try dictionary(category)) }
    func archiveCategory(id: String, expectedVersion: Int) async throws { try await dataAction("archive_category", payload: ["id": id, "expected_version": expectedVersion]) }

    func saveTransaction(_ draft: TransactionDraft) async throws {
        var payload: [String: Any] = [
            "p_client_mutation_id": UUID().uuidString,
            "p_type": draft.kind.rawValue,
            "p_amount": String(draft.amount),
            "p_account_id": draft.accountID,
            "p_category_id": draft.categoryID,
            "p_goal_id": jsonValue(draft.goalID),
            "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt),
            "p_merchant": jsonValue(draft.merchant),
            "p_note": jsonValue(draft.note)
        ]
        if let id = draft.id, let version = draft.expectedVersion {
            payload["p_transaction_id"] = id
            payload["p_expected_version"] = version
            try await ledger("update_transaction", payload: payload)
        } else {
            payload["p_source"] = draft.source
            try await ledger("create_transaction", payload: payload)
        }
    }

    func deleteTransaction(id: String, expectedVersion: Int) async throws {
        try await ledger("delete_transaction", payload: ["p_client_mutation_id": UUID().uuidString, "p_transaction_id": id, "p_expected_version": expectedVersion])
    }

    func restoreTransaction(id: String, expectedVersion: Int) async throws {
        try await ledger("restore_transaction", payload: ["p_client_mutation_id": UUID().uuidString, "p_transaction_id": id, "p_expected_version": expectedVersion])
    }

    func createTransfer(_ draft: TransferDraft) async throws {
        var payload: [String: Any] = [
            "p_client_mutation_id": UUID().uuidString,
            "p_from_account_id": draft.fromAccountID,
            "p_to_account_id": draft.toAccountID,
            "p_amount": String(draft.amount),
            "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt),
            "p_note": jsonValue(draft.note)
        ]
        if let id = draft.id, let version = draft.expectedVersion {
            payload["p_transfer_id"] = id
            payload["p_expected_version"] = version
            try await ledger("update_transfer", payload: payload)
        } else {
            try await ledger("create_transfer", payload: payload)
        }
    }

    func deleteTransfer(id: String, expectedVersion: Int) async throws {
        try await ledger("delete_transfer", payload: ["p_client_mutation_id": UUID().uuidString, "p_transfer_id": id, "p_expected_version": expectedVersion])
    }

    func calculateEqualSplit(total: Int64, participants: [EqualParticipant]) async throws -> [String: Int64] {
        let rows = participants.map { ["id": $0.id, "included": $0.included] as [String: Any] }
        return try await calculateSplit(total: total, method: "equal", participants: rows)
    }

    func calculatePercentageSplit(total: Int64, participants: [PercentageParticipant]) async throws -> [String: Int64] {
        let rows = participants.map { ["id": $0.id, "basis_points": $0.basisPoints] as [String: Any] }
        return try await calculateSplit(total: total, method: "percentage", participants: rows)
    }

    func createSplitBill(_ draft: SplitBillDraft) async throws {
        var payload = splitPayload(draft)
        payload["p_client_mutation_id"] = UUID().uuidString
        try await ledger(draft.itemSplit == nil ? "create_split_bill" : "save_item_split_bill", payload: payload)
    }

    func createSplitBillFromReview(reviewItemID: String, draft: SplitBillDraft) async throws {
        var payload = splitPayload(draft)
        payload["p_client_mutation_id"] = reviewItemID
        payload["p_review_item_id"] = reviewItemID
        try await ledger(draft.itemSplit == nil ? "create_split_bill_from_review" : "save_item_split_bill", payload: payload)
    }

    func convertTransactionToSplitBill(transactionID: String, expectedVersion: Int, draft: SplitBillDraft) async throws {
        var payload = splitPayload(draft)
        payload["p_client_mutation_id"] = UUID().uuidString
        payload["p_transaction_id"] = transactionID
        payload["p_expected_version"] = expectedVersion
        try await ledger(draft.itemSplit == nil ? "convert_transaction_to_split_bill" : "save_item_split_bill", payload: payload)
    }

    func updateSplitBill(id: String, expectedVersion: Int, draft: SplitBillDraft) async throws {
        var payload = splitPayload(draft)
        payload["p_client_mutation_id"] = UUID().uuidString
        payload["p_split_bill_id"] = id
        payload["p_expected_version"] = expectedVersion
        try await ledger(draft.itemSplit == nil ? "update_split_bill" : "save_item_split_bill", payload: payload)
    }

    func deleteSplitBill(id: String, expectedVersion: Int) async throws {
        try await ledger("delete_split_bill", payload: ["p_client_mutation_id": UUID().uuidString, "p_split_bill_id": id, "p_expected_version": expectedVersion])
    }

    func restoreSplitBill(id: String, expectedVersion: Int) async throws {
        try await ledger("restore_split_bill", payload: ["p_client_mutation_id": UUID().uuidString, "p_split_bill_id": id, "p_expected_version": expectedVersion])
    }

    func recordSettlement(_ draft: SettlementDraft) async throws {
        try await ledger("record_split_settlement", payload: [
            "p_client_mutation_id": UUID().uuidString, "p_split_bill_id": draft.billID, "p_member_id": draft.memberID,
            "p_account_id": draft.accountID, "p_amount": String(draft.amount),
            "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt), "p_note": jsonValue(draft.note)
        ])
    }

    func reverseSettlement(id: String, expectedVersion: Int, reason: String) async throws {
        try await ledger("reverse_split_settlement", payload: ["p_client_mutation_id": UUID().uuidString, "p_settlement_id": id, "p_expected_version": expectedVersion, "p_reason": reason])
    }

    func recordResolution(_ draft: ResolutionDraft) async throws {
        try await ledger("record_split_resolution", payload: [
            "p_client_mutation_id": UUID().uuidString, "p_split_bill_id": draft.billID, "p_member_id": draft.memberID,
            "p_amount": String(draft.amount), "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt), "p_reason": draft.reason
        ])
    }

    func reverseResolution(id: String, expectedVersion: Int, reason: String) async throws {
        try await ledger("reverse_split_resolution", payload: ["p_client_mutation_id": UUID().uuidString, "p_resolution_id": id, "p_expected_version": expectedVersion, "p_reason": reason])
    }

    func addReviewItem(_ item: ReviewItem, attachment: ReviewAttachment?) async throws {
        try await dataAction("add_review_item", payload: try dictionary(item))
        guard let attachment else { return }
        do {
            _ = try await client.data(
                path: "/functions/v1/ios-data/attachment",
                body: attachment.data,
                contentType: attachment.mimeType,
                headers: ["x-review-item-id": item.id, "x-file-name": attachment.name]
            )
        } catch {
            try? await dataAction("delete_review_item", payload: ["id": item.id])
            throw error
        }
    }
    func rejectReviewItem(id: String) async throws { try await dataAction("reject_review_item", payload: ["id": id]) }
    func updateReviewItem(_ item: ReviewItem) async throws { try await dataAction("update_review_item", payload: try dictionary(item)) }
    func restoreReviewItem(id: String) async throws { try await dataAction("restore_review_item", payload: ["id": id]) }

    func confirmReviewItem(id: String, transaction: TransactionDraft) async throws {
        try await dataAction("confirm_review_item", payload: ["id": id, "transaction": try dictionary(transaction)])
    }

    func mergeReviewItem(id: String, into transactionID: String) async throws { try await dataAction("merge_review_item", payload: ["id": id, "transaction_id": transactionID]) }
    func clearReviewDuplicate(id: String) async throws { try await dataAction("clear_review_duplicate", payload: ["id": id]) }
    func completeReviewItem(id: String) async throws { try await dataAction("complete_review_item", payload: ["id": id]) }
    func saveMerchantRule(_ rule: MerchantRule) async throws { try await dataAction("save_merchant_rule", payload: try dictionary(rule)) }
    func deleteMerchantRule(id: String, expectedVersion: Int) async throws { try await dataAction("delete_merchant_rule", payload: ["id": id, "expected_version": expectedVersion]) }
    func upsertBudget(categoryID: String, month: Date, limit: Int64) async throws { try await dataAction("upsert_budget", payload: ["category_id": categoryID, "month": MonthPeriod.key(month), "limit_amount": String(limit)]) }

    func saveGoal(_ goal: SavingsGoal) async throws {
        let date = goal.targetDate.map(MonthPeriod.dateKey)
        try await ledger("save_goal", payload: ["p_client_mutation_id": UUID().uuidString, "p_id": goal.id, "p_name": goal.name, "p_target": String(goal.targetAmount), "p_saved": String(goal.savedAmount), "p_target_date": date as Any? ?? NSNull(), "p_expected_version": goal.version])
    }

    func deleteGoal(id: String, expectedVersion: Int) async throws {
        try await ledger("delete_goal", payload: ["p_client_mutation_id": UUID().uuidString, "p_id": id, "p_expected_version": expectedVersion])
    }

    func calculateItemSplit(_ draft: ItemSplit, memberIDs: [String]) async throws -> ItemSplitResult {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder.danarapi.encode(draft))
        let body = try JSONSerialization.data(withJSONObject: ["operation": "calculate_item_split", "payload": ["p_item_split": object, "p_member_ids": memberIDs]])
        let data = try await client.data(path: "/functions/v1/ledger", body: body)
        return try JSONDecoder.danarapi.decode(ItemSplitResult.self, from: data)
    }

    func exportArchive() async throws -> URL {
        let data = try await client.data(path: "/functions/v1/export-data")
        let url = FileManager.default.temporaryDirectory.appending(path: "danarapi-export-\(UUID().uuidString).zip")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    func requestAccountDeletion(password: String) async throws {
        try await dataAction("request_account_deletion", payload: ["password": password])
    }

    func replayOutbox(operation: String, mutationID: String, payload: Data) async throws {
        switch operation {
        case "create_transaction", "update_transaction":
            let draft = try JSONDecoder.danarapi.decode(TransactionDraft.self, from: payload)
            var body: [String: Any] = [
                "p_client_mutation_id": mutationID, "p_type": draft.kind.rawValue,
                "p_amount": String(draft.amount), "p_account_id": draft.accountID,
                "p_category_id": draft.categoryID, "p_goal_id": jsonValue(draft.goalID), "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt),
                "p_merchant": jsonValue(draft.merchant), "p_note": jsonValue(draft.note)
            ]
            if operation == "update_transaction", let id = draft.id, let version = draft.expectedVersion {
                body["p_transaction_id"] = id; body["p_expected_version"] = version
            } else { body["p_source"] = draft.source }
            try await ledger(operation, payload: body)
        case "create_transfer", "update_transfer":
            let draft = try JSONDecoder.danarapi.decode(TransferDraft.self, from: payload)
            var body: [String: Any] = [
                "p_client_mutation_id": mutationID, "p_from_account_id": draft.fromAccountID, "p_to_account_id": draft.toAccountID,
                "p_amount": String(draft.amount), "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt), "p_note": jsonValue(draft.note)
            ]
            if operation == "update_transfer", let id = draft.id, let version = draft.expectedVersion { body["p_transfer_id"] = id; body["p_expected_version"] = version }
            try await ledger(operation, payload: body)
        case "delete_transaction", "delete_transfer":
            let value = try JSONDecoder.danarapi.decode(VersionedID.self, from: payload)
            let idKey = operation == "delete_transaction" ? "p_transaction_id" : "p_transfer_id"
            try await ledger(operation, payload: ["p_client_mutation_id": mutationID, idKey: value.id, "p_expected_version": value.version])
        default:
            throw AppError(code: "VALIDATION", message: "Operasi outbox tidak didukung.", requestID: nil, details: [:])
        }
    }

    private func ledger(_ operation: String, payload: [String: Any]) async throws {
        var requestPayload = payload
        var retryKey: String?
        let durableOperations: Set<String> = ["create_transaction", "update_transaction", "delete_transaction", "create_transfer", "update_transfer", "delete_transfer"]
        if let mutationID = payload["p_client_mutation_id"] as? String, !durableOperations.contains(operation) {
            var canonical = payload
            canonical.removeValue(forKey: "p_client_mutation_id")
            let data = try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])
            let key = operation + ":" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            requestPayload["p_client_mutation_id"] = pendingMutationIDs[key] ?? mutationID
            pendingMutationIDs[key] = requestPayload["p_client_mutation_id"] as? String
            retryKey = key
        }
        let body = try JSONSerialization.data(withJSONObject: ["operation": operation, "payload": requestPayload])
        _ = try await client.data(path: "/functions/v1/ledger", body: body)
        if let retryKey { pendingMutationIDs.removeValue(forKey: retryKey) }
    }

    private func dataAction(_ operation: String, payload: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["operation": operation, "payload": payload])
        _ = try await client.data(path: "/functions/v1/ios-data", body: body)
    }

    private func calculateSplit(total: Int64, method: String, participants: [[String: Any]]) async throws -> [String: Int64] {
        let body = try JSONSerialization.data(withJSONObject: ["operation": "calculate_split", "payload": ["p_total": String(total), "p_method": method, "p_participants": participants]])
        let data = try await client.data(path: "/functions/v1/ledger", body: body)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = object?["data"] as? [String: Any]
        let rows = payload?["participants"] as? [[String: Any]] ?? []
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let id = row["id"] as? String, let amount = row["share_amount"] as? String, let parsed = Int64(amount) else { return nil }
            return (id, parsed)
        })
    }

    private func splitPayload(_ draft: SplitBillDraft) -> [String: Any] {
        let payerKind: String
        let payerMemberID: Any
        let payerAccountID: Any
        switch draft.payer {
        case let .selfPaid(accountID):
            payerKind = "self"; payerMemberID = NSNull(); payerAccountID = accountID
        case let .other(memberID):
            payerKind = "other"; payerMemberID = memberID; payerAccountID = NSNull()
        }
        let members = draft.members.map { [
            "id": $0.id,
            "display_name": $0.displayName,
            "is_self": $0.isSelf,
            "share_amount": String($0.shareAmount),
            "sort_order": $0.sortOrder
        ] as [String: Any] }
        var payload: [String: Any] = [
            "p_total": String(draft.total), "p_title": draft.title,
            "p_payer_kind": payerKind, "p_payer_member_id": payerMemberID, "p_payer_account_id": payerAccountID,
            "p_category_id": draft.categoryID, "p_occurred_at": ISO8601DateFormatter().string(from: draft.occurredAt),
            "p_members": members, "p_note": jsonValue(draft.note)
        ]
        if let itemSplit = draft.itemSplit { payload["p_item_split"] = try? JSONSerialization.jsonObject(with: JSONEncoder.danarapi.encode(itemSplit)) }
        return payload
    }

    private func dictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder.danarapi.encode(value)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func jsonValue(_ value: String?) -> Any { value ?? NSNull() as Any }
}

private struct NoPayload: Encodable {}
private struct TransactionPageRequest: Encodable { let cursor: TransactionCursor }
private struct ReportRequest: Encodable { let startDate: Date; let endDate: Date? }
struct VersionedID: Codable, Sendable { let id: String; let version: Int }
