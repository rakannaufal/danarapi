import Foundation

actor DemoRepository: FinanceRepository {
    nonisolated let isDemo = true

    private var accounts: [FinancialAccount] = []
    private var categories: [Category] = []
    private var transactions: [FinanceTransaction] = []
    private var transfers: [TransferRecord] = []
    private var splitBills: [SplitBill] = []
    private var reviewItems: [ReviewItem] = []
    private var merchantRules: [MerchantRule] = []
    private var budgets: [Budget] = []
    private var goals: [SavingsGoal] = [SavingsGoal(id: "demo-goal", name: "Laptop impian", targetAmount: 15_000_000, savedAmount: 4_500_000, targetDate: nil, version: 1)]

    init() {
        accounts = Self.makeAccounts()
        categories = Self.makeCategories()
        transactions = Self.makeTransactions()
        splitBills = Self.makeSplitBills()
        reviewItems = Self.makeReviewItems()
        merchantRules = Self.makeMerchantRules()
        budgets = Self.makeBudgets()
    }

    func dashboard() async throws -> DashboardSnapshot {
        refreshDerivedValues()
        let orderedTransactions = transactions.filter { !$0.deleted }.sorted { ($0.occurredAt, $0.id) > ($1.occurredAt, $1.id) }
        let visibleTransactions = Array(orderedTransactions.prefix(30))
        return DashboardSnapshot(
            accounts: accounts,
            categories: categories.sorted { $0.sortOrder < $1.sortOrder },
            transactions: visibleTransactions,
            transfers: transfers.filter { !$0.deleted }.sorted { $0.occurredAt > $1.occurredAt },
            splitBills: splitBills.filter { !$0.deleted }.sorted { $0.occurredAt > $1.occurredAt },
            reviewItems: reviewItems.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt },
            merchantRules: merchantRules.sorted { ($0.priority, $0.normalizedPattern) > ($1.priority, $1.normalizedPattern) },
            budgets: budgets,
            overview: overview(),
            nextTransactionCursor: orderedTransactions.count > visibleTransactions.count ? visibleTransactions.last.map { TransactionCursor(occurredAt: $0.occurredAt, id: $0.id) } : nil,
            syncedAt: nil,
            goals: goals.map { goal in
                var result = goal
                result.savedAmount += transactions.filter { !$0.deleted && $0.kind == .expense && $0.goalID == goal.id }.reduce(0) { $0 + $1.amount }
                return result
            }
        )
    }

    func transactionPage(after cursor: TransactionCursor) async throws -> TransactionPage {
        let ordered = transactions.filter { !$0.deleted }.sorted { ($0.occurredAt, $0.id) > ($1.occurredAt, $1.id) }
        let remaining = ordered.filter { ($0.occurredAt, $0.id) < (cursor.occurredAt, cursor.id) }
        let items = Array(remaining.prefix(30))
        let next = remaining.count > items.count ? items.last.map { TransactionCursor(occurredAt: $0.occurredAt, id: $0.id) } : nil
        return TransactionPage(items: items, nextCursor: next)
    }

    func report(since startDate: Date, until endDate: Date?) async throws -> ReportSummary {
        let end = endDate ?? .distantFuture
        guard end > startDate else { throw AppError.validation("Periode laporan tidak valid.") }
        let ordinaryIncome = transactions.filter { !$0.deleted && $0.kind == .income && $0.occurredAt >= startDate && $0.occurredAt < end }.reduce(Int64(0)) { $0 + $1.amount }
        let ordinaryExpenses = transactions.filter { !$0.deleted && $0.kind == .expense && $0.occurredAt >= startDate && $0.occurredAt < end }
        let forgiveness = splitBills.filter { !$0.deleted }.flatMap(\.resolutions).filter { !$0.reversed && $0.kind == .payableForgiveness && $0.occurredAt >= startDate && $0.occurredAt < end }.reduce(Int64(0)) { $0 + $1.amount }
        var categoryTotals = Dictionary(grouping: ordinaryExpenses, by: \.categoryID).mapValues { $0.reduce(Int64(0)) { $0 + $1.amount } }
        var personalExpense = ordinaryExpenses.reduce(Int64(0)) { $0 + $1.amount }
        for bill in splitBills where !bill.deleted {
            if bill.occurredAt >= startDate && bill.occurredAt < end { categoryTotals[bill.categoryID, default: 0] += bill.selfShare; personalExpense += bill.selfShare }
            for event in bill.resolutions where !event.reversed && event.kind == .receivableWriteoff && event.occurredAt >= startDate && event.occurredAt < end {
                categoryTotals[bill.categoryID, default: 0] += event.amount
                personalExpense += event.amount
            }
        }
        let budgetIDs = Set(budgets.filter { $0.month >= MonthPeriod.start(startDate) && $0.month < end }.map(\.categoryID))
        var remaining = categoryTotals
        var goalAmounts: [String: Int64] = [:]
        for transaction in ordinaryExpenses {
            if let goalID = transaction.goalID {
                goalAmounts[goalID, default: 0] += transaction.amount
                remaining[transaction.categoryID, default: 0] -= transaction.amount
            }
        }
        var allocations = goalAmounts.map { goalID, amount in ReportAllocation(id: "goal:\(goalID)", name: "Target · \(goals.first(where: { $0.id == goalID })?.name ?? "Target")", amount: amount) }
        allocations += remaining.filter { $0.value > 0 }.map { categoryID, amount in
            let name = categories.first(where: { $0.id == categoryID })?.name ?? "Kategori"
            return ReportAllocation(id: "category:\(categoryID)", name: budgetIDs.contains(categoryID) ? "Anggaran · \(name)" : name, amount: amount)
        }
        return ReportSummary(
            personalIncome: ordinaryIncome + forgiveness,
            personalExpense: personalExpense,
            categories: categoryTotals.map { ReportCategoryAmount(categoryID: $0.key, amount: $0.value) },
            allocations: allocations.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
        )
    }

    func resetDemo() async throws {
        loadSeed()
    }

    func createAccount(_ draft: AccountDraft) async throws {
        guard !accounts.contains(where: { $0.name.compare(draft.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame && !$0.archived }) else {
            throw AppError.validation("Nama akun sudah dipakai.")
        }
        accounts.append(FinancialAccount(
            id: UUID().uuidString, name: draft.name, kind: draft.kind,
            openingBalance: draft.openingBalance, balance: draft.openingBalance,
            openedAt: draft.openedAt, archived: false, version: 1
        ))
    }

    func updateAccount(_ account: FinancialAccount) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { throw AppError.validation("Akun tidak ditemukan.") }
        var value = account
        value.version += 1
        accounts[index] = value
    }

    func archiveAccount(id: String, expectedVersion: Int) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }), accounts[index].version == expectedVersion else { throw conflict() }
        guard accounts.filter({ !$0.archived }).count > 1 else { throw AppError.validation("Akun aktif terakhir tidak dapat diarsip.") }
        accounts[index].archived = true
        accounts[index].version += 1
    }

    func createCategory(name: String, kind: TransactionKind) async throws {
        categories.append(Category(id: UUID().uuidString, name: name, kind: kind, systemKey: nil, archived: false, sortOrder: categories.count, version: 1))
    }

    func updateCategory(_ category: Category) async throws {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { throw AppError.validation("Kategori tidak ditemukan.") }
        var value = category
        value.version += 1
        categories[index] = value
    }

    func archiveCategory(id: String, expectedVersion: Int) async throws {
        guard let index = categories.firstIndex(where: { $0.id == id }), categories[index].version == expectedVersion else { throw conflict() }
        categories[index].archived = true
        categories[index].version += 1
    }

    func saveTransaction(_ input: TransactionDraft) async throws {
        var draft = input
        if let transactionID = draft.id, let existing = transactions.first(where: { $0.id == transactionID }) { draft.source = existing.source }
        try validateMoney(draft.amount)
        if draft.source == "qris" {
            guard draft.kind == .expense, draft.goalID == nil else { throw AppError.validation("QRIS dicatat sebagai pengeluaran.") }
            draft.categoryID = categories.first(where: { $0.systemKey == "qris" })?.id ?? ""
        }
        if let goalID = draft.goalID {
            guard draft.kind == .expense, goals.contains(where: { $0.id == goalID }) else { throw AppError.validation("Pilih target aktif untuk pengeluaran ini.") }
            draft.categoryID = categories.first(where: { $0.systemKey == "goal" })?.id ?? ""
        } else if categories.contains(where: { $0.id == draft.categoryID && $0.systemKey == "goal" }) {
            throw AppError.validation("Pilih target untuk kategori Target.")
        }
        guard accounts.contains(where: { $0.id == draft.accountID && !$0.archived }),
              categories.contains(where: { $0.id == draft.categoryID && $0.kind == draft.kind && !$0.archived })
        else { throw AppError.validation("Akun atau kategori tidak valid.") }

        if let id = draft.id {
            guard let index = transactions.firstIndex(where: { $0.id == id }), transactions[index].version == draft.expectedVersion else { throw conflict() }
            transactions[index].kind = draft.kind
            transactions[index].amount = draft.amount
            transactions[index].accountID = draft.accountID
            transactions[index].categoryID = draft.categoryID
            transactions[index].occurredAt = draft.occurredAt
            transactions[index].merchant = draft.merchant
            transactions[index].note = draft.note
            transactions[index].goalID = draft.goalID
            transactions[index].version += 1
        } else {
            transactions.append(FinanceTransaction(
                id: UUID().uuidString, kind: draft.kind, amount: draft.amount,
                accountID: draft.accountID, categoryID: draft.categoryID,
                occurredAt: draft.occurredAt, merchant: draft.merchant, note: draft.note,
                source: draft.source, pendingSync: false, deleted: false, version: 1, goalID: draft.goalID
            ))
        }
    }

    func deleteTransaction(id: String, expectedVersion: Int) async throws {
        guard let index = transactions.firstIndex(where: { $0.id == id }), transactions[index].version == expectedVersion else { throw conflict() }
        transactions[index].deleted = true
        transactions[index].version += 1
    }

    func restoreTransaction(id: String, expectedVersion: Int) async throws {
        guard let index = transactions.firstIndex(where: { $0.id == id }), transactions[index].version == expectedVersion else { throw conflict() }
        transactions[index].deleted = false
        transactions[index].version += 1
    }

    func createTransfer(_ draft: TransferDraft) async throws {
        try validateMoney(draft.amount)
        guard draft.fromAccountID != draft.toAccountID else { throw AppError.validation("Akun asal dan tujuan harus berbeda.") }
        if let id = draft.id {
            guard let index = transfers.firstIndex(where: { $0.id == id }), transfers[index].version == draft.expectedVersion else { throw conflict() }
            transfers[index].fromAccountID = draft.fromAccountID
            transfers[index].toAccountID = draft.toAccountID
            transfers[index].amount = draft.amount
            transfers[index].occurredAt = draft.occurredAt
            transfers[index].note = draft.note
            transfers[index].version += 1
        } else {
            transfers.append(TransferRecord(id: UUID().uuidString, fromAccountID: draft.fromAccountID, toAccountID: draft.toAccountID, amount: draft.amount, occurredAt: draft.occurredAt, note: draft.note, pendingSync: false, deleted: false, version: 1))
        }
    }

    func deleteTransfer(id: String, expectedVersion: Int) async throws {
        guard let index = transfers.firstIndex(where: { $0.id == id }), transfers[index].version == expectedVersion else { throw conflict() }
        transfers[index].deleted = true
        transfers[index].version += 1
    }

    func calculateEqualSplit(total: Int64, participants: [EqualParticipant]) async throws -> [String: Int64] {
        let result = try SplitCalculator.equal(total: String(total), participants: participants)
        return try result.mapValues { try Money.parse($0, allowZero: true) }
    }

    func calculatePercentageSplit(total: Int64, participants: [PercentageParticipant]) async throws -> [String: Int64] {
        let result = try SplitCalculator.percentage(total: String(total), participants: participants)
        return try result.mapValues { try Money.parse($0, allowZero: true) }
    }

    func createSplitBill(_ draft: SplitBillDraft) async throws {
        try validateItemSplit(draft)
        try validateMoney(draft.total)
        guard draft.members.count >= 2, draft.members.count <= 20,
              draft.members.filter(\.isSelf).count == 1,
              draft.members.reduce(0, { $0 + $1.shareAmount }) == draft.total
        else { throw AppError.validation("Jumlah porsi harus tepat sama dengan total.") }
        let names = draft.members.map { normalize($0.displayName) }
        guard Set(names).count == names.count else { throw AppError.validation("Nama peserta harus unik.") }
        splitBills.append(SplitBill(
            id: UUID().uuidString, title: draft.title, total: draft.total,
            categoryID: draft.categoryID, payer: draft.payer, occurredAt: draft.occurredAt,
            note: draft.note, members: draft.members, settlements: [], resolutions: [], deleted: false, version: 1, itemSplit: draft.itemSplit
        ))
    }

    func createSplitBillFromReview(reviewItemID: String, draft: SplitBillDraft) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == reviewItemID && $0.status == .pending }) else { throw conflict() }
        try await createSplitBill(draft)
        reviewItems[index].status = .saved
    }

    func convertTransactionToSplitBill(transactionID: String, expectedVersion: Int, draft: SplitBillDraft) async throws {
        guard let index = transactions.firstIndex(where: { $0.id == transactionID && !$0.deleted }), transactions[index].version == expectedVersion else { throw conflict() }
        guard transactions[index].kind == .expense else { throw AppError.validation("Hanya pengeluaran dapat dijadikan split bill.") }
        try validateSplit(draft)
        try await createSplitBill(draft)
        transactions[index].deleted = true
        transactions[index].version += 1
    }

    func updateSplitBill(id: String, expectedVersion: Int, draft: SplitBillDraft) async throws {
        try validateItemSplit(draft)
        guard let index = splitBills.firstIndex(where: { $0.id == id }), splitBills[index].version == expectedVersion else { throw conflict() }
        let hasActiveEvents = splitBills[index].settlements.contains { !$0.reversed } || splitBills[index].resolutions.contains { !$0.reversed }
        if hasActiveEvents {
            let current = splitBills[index]
            guard draft.total == current.total, draft.categoryID == current.categoryID,
                  draft.payer == current.payer, draft.occurredAt == current.occurredAt,
                  splitStructure(draft.members) == splitStructure(current.members), draft.itemSplit == current.itemSplit
            else { throw AppError(code: "STRUCTURE_LOCKED", message: "Batalkan pelunasan atau penghapusan aktif sebelum mengubah struktur bill.", requestID: nil, details: [:]) }
        } else {
            try validateSplit(draft)
            splitBills[index].total = draft.total
            splitBills[index].categoryID = draft.categoryID
            splitBills[index].payer = draft.payer
            splitBills[index].occurredAt = draft.occurredAt
            splitBills[index].members = draft.members
        }
        splitBills[index].title = draft.title
        splitBills[index].note = draft.note
        splitBills[index].itemSplit = draft.itemSplit
        splitBills[index].version += 1
    }

    func deleteSplitBill(id: String, expectedVersion: Int) async throws {
        guard let index = splitBills.firstIndex(where: { $0.id == id }), splitBills[index].version == expectedVersion else { throw conflict() }
        guard splitBills[index].settlements.allSatisfy(\.reversed), splitBills[index].resolutions.allSatisfy(\.reversed) else {
            throw AppError(code: "STRUCTURE_LOCKED", message: "Batalkan kejadian aktif sebelum menghapus bill.", requestID: nil, details: [:])
        }
        splitBills[index].deleted = true
        splitBills[index].version += 1
    }

    func restoreSplitBill(id: String, expectedVersion: Int) async throws {
        guard let index = splitBills.firstIndex(where: { $0.id == id }), splitBills[index].version == expectedVersion else { throw conflict() }
        splitBills[index].deleted = false
        splitBills[index].version += 1
    }

    func recordSettlement(_ draft: SettlementDraft) async throws {
        try validateMoney(draft.amount)
        guard let billIndex = splitBills.firstIndex(where: { $0.id == draft.billID }),
              let memberIndex = splitBills[billIndex].members.firstIndex(where: { $0.id == draft.memberID })
        else { throw AppError.validation("Kewajiban tidak ditemukan.") }
        guard draft.amount <= splitBills[billIndex].members[memberIndex].remainingAmount else { throw obligationExceeded() }
        let direction: SettlementDirection
        switch splitBills[billIndex].payer {
        case .selfPaid: direction = .incoming
        case .other: direction = .outgoing
        }
        splitBills[billIndex].members[memberIndex].settledAmount += draft.amount
        splitBills[billIndex].settlements.append(SplitSettlement(id: UUID().uuidString, memberID: draft.memberID, direction: direction, accountID: draft.accountID, amount: draft.amount, occurredAt: draft.occurredAt, note: draft.note, reversed: false, version: 1))
        splitBills[billIndex].version += 1
    }

    func reverseSettlement(id: String, expectedVersion: Int, reason: String) async throws {
        for billIndex in splitBills.indices {
            if let eventIndex = splitBills[billIndex].settlements.firstIndex(where: { $0.id == id }) {
                guard splitBills[billIndex].settlements[eventIndex].version == expectedVersion else { throw conflict() }
                let event = splitBills[billIndex].settlements[eventIndex]
                guard let memberIndex = splitBills[billIndex].members.firstIndex(where: { $0.id == event.memberID }) else { throw AppError.validation("Peserta tidak ditemukan.") }
                splitBills[billIndex].members[memberIndex].settledAmount -= event.amount
                splitBills[billIndex].settlements[eventIndex].reversed = true
                splitBills[billIndex].settlements[eventIndex].version += 1
                return
            }
        }
        throw AppError.validation("Pelunasan tidak ditemukan.")
    }

    func recordResolution(_ draft: ResolutionDraft) async throws {
        try validateMoney(draft.amount)
        guard !draft.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.validation("Alasan wajib diisi.") }
        guard let billIndex = splitBills.firstIndex(where: { $0.id == draft.billID }),
              let memberIndex = splitBills[billIndex].members.firstIndex(where: { $0.id == draft.memberID })
        else { throw AppError.validation("Kewajiban tidak ditemukan.") }
        guard draft.amount <= splitBills[billIndex].members[memberIndex].remainingAmount else { throw obligationExceeded() }
        let kind: ResolutionKind
        switch splitBills[billIndex].payer {
        case .selfPaid: kind = .receivableWriteoff
        case .other: kind = .payableForgiveness
        }
        splitBills[billIndex].members[memberIndex].resolvedAmount += draft.amount
        splitBills[billIndex].resolutions.append(SplitResolution(id: UUID().uuidString, memberID: draft.memberID, kind: kind, amount: draft.amount, occurredAt: draft.occurredAt, reason: draft.reason, reversed: false, version: 1))
        splitBills[billIndex].version += 1
    }

    func reverseResolution(id: String, expectedVersion: Int, reason: String) async throws {
        for billIndex in splitBills.indices {
            if let eventIndex = splitBills[billIndex].resolutions.firstIndex(where: { $0.id == id }) {
                guard splitBills[billIndex].resolutions[eventIndex].version == expectedVersion else { throw conflict() }
                let event = splitBills[billIndex].resolutions[eventIndex]
                guard let memberIndex = splitBills[billIndex].members.firstIndex(where: { $0.id == event.memberID }) else { throw AppError.validation("Peserta tidak ditemukan.") }
                splitBills[billIndex].members[memberIndex].resolvedAmount -= event.amount
                splitBills[billIndex].resolutions[eventIndex].reversed = true
                splitBills[billIndex].resolutions[eventIndex].version += 1
                return
            }
        }
        throw AppError.validation("Penghapusan kewajiban tidak ditemukan.")
    }

    func addReviewItem(_ item: ReviewItem, attachment: ReviewAttachment?) async throws { reviewItems.append(item) }
    func updateReviewItem(_ item: ReviewItem) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == item.id && $0.status == .pending }) else { throw AppError.validation("Draft tidak lagi tersedia.") }
        reviewItems[index] = item
    }

    func rejectReviewItem(id: String) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == id }) else { return }
        reviewItems[index].status = .rejected
    }

    func restoreReviewItem(id: String) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == id && $0.status == .rejected }) else { throw conflict() }
        reviewItems[index].status = .pending
    }

    func confirmReviewItem(id: String, transaction: TransactionDraft) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == id && $0.status == .pending }) else { throw AppError.validation("Tinjauan sudah diproses.") }
        var draft = transaction
        if reviewItems[index].source == .qris {
            draft.kind = .expense
            draft.source = "qris"
            draft.goalID = nil
            draft.categoryID = categories.first(where: { $0.systemKey == "qris" })?.id ?? ""
        }
        try await saveTransaction(draft)
        reviewItems[index].status = .saved
    }

    func mergeReviewItem(id: String, into transactionID: String) async throws {
        guard transactions.contains(where: { $0.id == transactionID }), let index = reviewItems.firstIndex(where: { $0.id == id }) else { throw AppError.validation("Transaksi target tidak ditemukan.") }
        reviewItems[index].status = .merged
    }

    func clearReviewDuplicate(id: String) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == id && $0.status == .pending }) else { throw conflict() }
        reviewItems[index].duplicateCandidateID = nil
    }

    func completeReviewItem(id: String) async throws {
        guard let index = reviewItems.firstIndex(where: { $0.id == id }) else { return }
        reviewItems[index].status = .saved
    }

    func saveMerchantRule(_ rule: MerchantRule) async throws {
        guard !rule.normalizedPattern.isEmpty, categories.contains(where: { $0.id == rule.categoryID && $0.kind == .expense }) else {
            throw AppError.validation("Pola dan kategori aturan merchant wajib valid.")
        }
        if let index = merchantRules.firstIndex(where: { $0.id == rule.id }) {
            guard merchantRules[index].version == rule.version else { throw conflict() }
            var value = rule
            value.version += 1
            merchantRules[index] = value
        } else {
            merchantRules.append(rule)
        }
    }

    func deleteMerchantRule(id: String, expectedVersion: Int) async throws {
        guard let index = merchantRules.firstIndex(where: { $0.id == id }), merchantRules[index].version == expectedVersion else { throw conflict() }
        merchantRules.remove(at: index)
    }

    func upsertBudget(categoryID: String, month: Date, limit: Int64) async throws {
        try validateMoney(limit)
        if let index = budgets.firstIndex(where: { $0.categoryID == categoryID && Calendar.current.isDate($0.month, equalTo: month, toGranularity: .month) }) {
            budgets[index].limitAmount = limit
        } else {
            budgets.append(Budget(id: UUID().uuidString, categoryID: categoryID, month: month, limitAmount: limit, spentAmount: 0))
        }
    }

    func exportArchive() async throws -> URL {
        var snapshot = try await dashboard()
        snapshot.transactions = transactions.filter { !$0.deleted }.sorted { ($0.occurredAt, $0.id) > ($1.occurredAt, $1.id) }
        snapshot.nextTransactionCursor = nil
        return try ExportService.createDemoArchive(snapshot: snapshot)
    }

    func calculateItemSplit(_ draft: ItemSplit, memberIDs: [String]) async throws -> ItemSplitResult {
        try ItemSplitCalculator.calculate(draft, memberIDs: memberIDs)
    }

    private func validateItemSplit(_ draft: SplitBillDraft) throws {
        guard let items = draft.itemSplit else { return }
        let result = try ItemSplitCalculator.calculate(items, memberIDs: draft.members.map(\.id))
        guard result.total == String(draft.total), draft.members.allSatisfy({ result.shares[$0.id] == String($0.shareAmount) }) else { throw AppError.validation("Porsi menu tidak sesuai hasil perhitungan.") }
    }

    func saveGoal(_ goal: SavingsGoal) async throws {
        try validateMoney(goal.targetAmount)
        guard goal.savedAmount >= 0, goal.savedAmount <= Money.maximum, (1...100).contains(goal.name.trimmingCharacters(in: .whitespacesAndNewlines).count) else { throw AppError.validation("Nama atau nominal goal tidak valid.") }
        if let index = goals.firstIndex(where: { $0.id == goal.id }) {
            guard goals[index].version == goal.version else { throw conflict() }
            let opening = goals[index].savedAmount
            goals[index] = goal; goals[index].savedAmount = opening; goals[index].version += 1
        } else {
            guard goal.version == 0 else { throw conflict() }
            guard goal.savedAmount == 0 else { throw AppError.validation("Progres target dicatat melalui transaksi.") }
            var value = goal; value.version = 1; goals.append(value)
        }
    }

    func deleteGoal(id: String, expectedVersion: Int) async throws {
        guard let index = goals.firstIndex(where: { $0.id == id }), goals[index].version == expectedVersion else { throw conflict() }
        goals.remove(at: index)
        for transactionIndex in transactions.indices where transactions[transactionIndex].goalID == id { transactions[transactionIndex].goalID = nil }
    }

    func requestAccountDeletion(password: String) async throws {
        throw AppError(code: "VALIDATION", message: "Mode Demo tidak memiliki akun server. Gunakan Reset data contoh.", requestID: nil, details: [:])
    }

    func replayOutbox(operation: String, mutationID: String, payload: Data) async throws {}

    private func loadSeed() {
        accounts = Self.makeAccounts()
        categories = Self.makeCategories()
        transactions = Self.makeTransactions()
        transfers = []
        splitBills = Self.makeSplitBills()
        reviewItems = Self.makeReviewItems()
        merchantRules = Self.makeMerchantRules()
        budgets = Self.makeBudgets()
        goals = [SavingsGoal(id: "demo-goal", name: "Laptop impian", targetAmount: 15_000_000, savedAmount: 4_500_000, targetDate: nil, version: 1)]
        refreshDerivedValues()
    }

    private static func makeAccounts() -> [FinancialAccount] {
        if let rows = fixtureObject()?["accounts"] as? [[String: Any]] {
            let openedAt = fixtureStartDate()
            let values = rows.compactMap { row -> FinancialAccount? in
                guard let id = row["id"] as? String, let name = row["name"] as? String,
                      let kindRaw = row["kind"] as? String, let kind = AccountKind(rawValue: kindRaw),
                      let amount = (row["opening_balance"] as? String).flatMap(Int64.init)
                else { return nil }
                return FinancialAccount(id: id, name: name, kind: kind, openingBalance: amount, balance: amount, openedAt: openedAt, archived: false, version: 1)
            }
            if !values.isEmpty { return values }
        }
        return [
            FinancialAccount(id: "cash", name: "Tunai", kind: .cash, openingBalance: 500_000, balance: 500_000, openedAt: Date.demoNow.addingTimeInterval(-92 * 86_400), archived: false, version: 1),
            FinancialAccount(id: "bank", name: "Bank Demo", kind: .bank, openingBalance: 2_500_000, balance: 2_500_000, openedAt: Date.demoNow.addingTimeInterval(-92 * 86_400), archived: false, version: 1)
        ]
    }

    private static func makeCategories() -> [Category] {
        if let rows = fixtureObject()?["categories"] as? [[String: Any]] {
            var values = rows.enumerated().compactMap { index, row -> Category? in
                guard let id = row["id"] as? String, let name = row["name"] as? String,
                      let kindRaw = row["kind"] as? String, let kind = TransactionKind(rawValue: kindRaw)
                else { return nil }
                return Category(id: id, name: name, kind: kind, systemKey: nil, archived: false, sortOrder: index, version: 1)
            }
            values.append(Category(id: "gift", name: "Hadiah/Pembebasan utang", kind: .income, systemKey: "debt_forgiveness", archived: false, sortOrder: values.count, version: 1))
            values.append(Category(id: "feature-goal", name: "Target", kind: .expense, systemKey: "goal", archived: false, sortOrder: values.count, version: 1))
            values.append(Category(id: "feature-qris", name: "QRIS", kind: .expense, systemKey: "qris", archived: false, sortOrder: values.count, version: 1))
            if values.count > 1 { return values }
        }
        return [
            Category(id: "feature-goal", name: "Target", kind: .expense, systemKey: "goal", archived: false, sortOrder: 920, version: 1),
            Category(id: "feature-qris", name: "QRIS", kind: .expense, systemKey: "qris", archived: false, sortOrder: 921, version: 1),
            Category(id: "food", name: "Makan", kind: .expense, systemKey: nil, archived: false, sortOrder: 0, version: 1),
            Category(id: "transport", name: "Transportasi", kind: .expense, systemKey: nil, archived: false, sortOrder: 1, version: 1),
            Category(id: "household", name: "Rumah", kind: .expense, systemKey: nil, archived: false, sortOrder: 2, version: 1),
            Category(id: "salary", name: "Gaji", kind: .income, systemKey: nil, archived: false, sortOrder: 3, version: 1),
            Category(id: "gift", name: "Hadiah/Pembebasan utang", kind: .income, systemKey: "debt_forgiveness", archived: false, sortOrder: 4, version: 1)
        ]
    }

    private static func makeBudgets() -> [Budget] {
        if let rows = fixtureObject()?["budgets"] as? [[String: Any]] {
            let values = rows.enumerated().compactMap { index, row -> Budget? in
                guard let categoryID = row["category_id"] as? String,
                      let monthText = row["month"] as? String,
                      let limit = (row["limit_amount"] as? String).flatMap(Int64.init),
                      let month = monthFormatter.date(from: monthText)
                else { return nil }
                return Budget(id: "fixture-budget-\(index)", categoryID: categoryID, month: month, limitAmount: limit, spentAmount: 0)
            }
            if !values.isEmpty { return values }
        }
        return [
            Budget(id: "budget-food", categoryID: "food", month: Date.demoNow, limitAmount: 1_800_000, spentAmount: 0),
            Budget(id: "budget-transport", categoryID: "transport", month: Date.demoNow, limitAmount: 700_000, spentAmount: 0)
        ]
    }

    private static func makeTransactions() -> [FinanceTransaction] {
        if let rows = fixtureObject()?["transactions"] as? [[String: Any]] {
            let formatter = fixtureISO
            let values = rows.compactMap { row -> FinanceTransaction? in
                guard let id = row["id"] as? String, let typeRaw = row["type"] as? String,
                      let kind = TransactionKind(rawValue: typeRaw),
                      let amount = (row["amount"] as? String).flatMap(Int64.init),
                      let accountID = row["account_id"] as? String, let categoryID = row["category_id"] as? String,
                      let occurredText = row["occurred_at"] as? String, let occurredAt = formatter.date(from: occurredText)
                else { return nil }
                return FinanceTransaction(id: id, kind: kind, amount: amount, accountID: accountID, categoryID: categoryID, occurredAt: occurredAt, merchant: row["merchant"] as? String, note: nil, source: "demo", pendingSync: false, deleted: false, version: 1)
            }
            if values.count == 200 { return values }
        }
        return (1...200).map { index in
            let income = index % 47 == 0
            return FinanceTransaction(
                id: "demo-transaction-\(index)", kind: income ? .income : .expense,
                amount: income ? 4_500_000 : Int64(8_000 + ((index * 7_919) % 142_000)),
                accountID: index % 4 == 0 ? "cash" : "bank",
                categoryID: income ? "salary" : ["food", "transport", "household"][index % 3],
                occurredAt: Date.demoNow.addingTimeInterval(TimeInterval(-(index % 92) * 86_400)),
                merchant: income ? "Pemberi kerja sintetis" : ["Warung Pagi", "Pasar Lokal", "Bus Kota", "Toko Buku", "Kedai Sore", "Apotek Demo"][index % 6],
                note: nil, source: "demo", pendingSync: false, deleted: false, version: 1
            )
        }
    }

    private static func makeSplitBills() -> [SplitBill] {
        let selfMember = SplitMember(id: "bill1-self", displayName: "Saya", isSelf: true, shareAmount: 40_000, settledAmount: 0, resolvedAmount: 0, sortOrder: 0)
        let ani = SplitMember(id: "bill1-ani", displayName: "Ani", isSelf: false, shareAmount: 40_000, settledAmount: 15_000, resolvedAmount: 0, sortOrder: 1)
        let budi = SplitMember(id: "bill1-budi", displayName: "Budi", isSelf: false, shareAmount: 40_000, settledAmount: 0, resolvedAmount: 0, sortOrder: 2)
        let settlement = SplitSettlement(id: "bill1-settlement", memberID: ani.id, direction: .incoming, accountID: "cash", amount: 15_000, occurredAt: Date.demoNow.addingTimeInterval(-3 * 86_400), note: nil, reversed: false, version: 1)
        let first = SplitBill(id: "demo-bill-self", title: "Makan bersama", total: 120_000, categoryID: "food", payer: .selfPaid(accountID: "cash"), occurredAt: Date.demoNow.addingTimeInterval(-5 * 86_400), note: nil, members: [selfMember, ani, budi], settlements: [settlement], resolutions: [], deleted: false, version: 1)

        let second = SplitBill(id: "demo-bill-other", title: "Tiket konser", total: 90_000, categoryID: "household", payer: .other(memberID: "bill2-ani"), occurredAt: Date.demoNow.addingTimeInterval(-10 * 86_400), note: "Ani membayar", members: [
            SplitMember(id: "bill2-self", displayName: "Saya", isSelf: true, shareAmount: 30_000, settledAmount: 0, resolvedAmount: 0, sortOrder: 0),
            SplitMember(id: "bill2-ani", displayName: "Ani", isSelf: false, shareAmount: 30_000, settledAmount: 0, resolvedAmount: 0, sortOrder: 1),
            SplitMember(id: "bill2-budi", displayName: "Budi", isSelf: false, shareAmount: 30_000, settledAmount: 0, resolvedAmount: 0, sortOrder: 2)
        ], settlements: [], resolutions: [], deleted: false, version: 1)
        return [first, second]
    }

    private static func makeReviewItems() -> [ReviewItem] {
        [
            ReviewItem(id: "review-qris", source: .qris, status: .pending,
                amount: ExtractedField(value: "75000", confidence: .high, evidenceSpan: "54 05 75000", sourceType: .qris),
                merchant: ExtractedField(value: "TOKO DEMO", confidence: .medium, evidenceSpan: "59 09 TOKO DEMO", sourceType: .qris),
                date: ExtractedField(value: nil, confidence: .low, evidenceSpan: nil, sourceType: .qris),
                rawReference: nil, duplicateCandidateID: nil, attachmentName: "qris-sintetis.png", createdAt: Date.demoNow),
            ReviewItem(id: "review-text", source: .pastedText, status: .pending,
                amount: ExtractedField(value: nil, confidence: .low, evidenceSpan: "Subtotal 50.000; Total 58.000", sourceType: .pastedText),
                merchant: ExtractedField(value: "Kedai Sore", confidence: .medium, evidenceSpan: "Kedai Sore", sourceType: .pastedText),
                date: ExtractedField(value: "2026-09-29", confidence: .medium, evidenceSpan: "29/09/2026", sourceType: .pastedText),
                rawReference: nil, duplicateCandidateID: "demo-transaction-1", attachmentName: nil, createdAt: Date.demoNow.addingTimeInterval(-3_600))
        ]
    }

    private static func makeMerchantRules() -> [MerchantRule] {
        [MerchantRule(id: "demo-rule-warung", matchType: .contains, normalizedPattern: "warung", categoryID: "food", priority: 10, version: 1)]
    }

    private static var fixtureISO: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static func fixtureStartDate() -> Date {
        guard let period = fixtureObject()?["period"] as? [String: Any],
              let value = period["from"] as? String,
              let date = fixtureISO.date(from: value)
        else { return Date.demoNow.addingTimeInterval(-92 * 86_400) }
        return date
    }

    private static func fixtureObject() -> [String: Any]? {
        let bundled = Bundle.main.url(forResource: "demo-seed-v1", withExtension: "json")
        var source = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { source.deleteLastPathComponent() }
        let repository = source.appending(path: "tests/fixtures/demo-seed-v1.json")
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: repository.path) ? repository : nil),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func refreshDerivedValues() {
        let currentOverview = overview()
        for index in accounts.indices {
            accounts[index].balance = balance(for: accounts[index].id)
        }
        for index in budgets.indices {
            budgets[index].spentAmount = spent(categoryID: budgets[index].categoryID, month: budgets[index].month)
        }
        _ = currentOverview
    }

    private func validateSplit(_ draft: SplitBillDraft) throws {
        try validateMoney(draft.total)
        guard draft.members.count >= 2, draft.members.count <= 20,
              draft.members.filter(\.isSelf).count == 1,
              draft.members.reduce(0, { $0 + $1.shareAmount }) == draft.total
        else { throw AppError.validation("Jumlah porsi harus tepat sama dengan total.") }
        let names = draft.members.map { normalize($0.displayName) }
        guard Set(names).count == names.count else { throw AppError.validation("Nama peserta harus unik.") }
    }

    private func splitStructure(_ members: [SplitMember]) -> [String] {
        members.sorted { $0.sortOrder < $1.sortOrder }.map {
            "\($0.id)|\($0.displayName)|\($0.isSelf)|\($0.shareAmount)|\($0.sortOrder)"
        }
    }

    private func balance(for accountID: String) -> Int64 {
        let opening = accounts.first(where: { $0.id == accountID })?.openingBalance ?? 0
        let transactionCash = transactions.filter { !$0.deleted && $0.accountID == accountID }.reduce(Int64(0)) { sum, item in sum + (item.kind == .income ? item.amount : -item.amount) }
        let transferCash = transfers.filter { !$0.deleted }.reduce(Int64(0)) { sum, item in
            sum + (item.toAccountID == accountID ? item.amount : 0) - (item.fromAccountID == accountID ? item.amount : 0)
        }
        let splitCash = splitBills.filter { !$0.deleted }.reduce(Int64(0)) { sum, bill in
            var value = sum
            if case let .selfPaid(payerAccountID) = bill.payer, payerAccountID == accountID { value -= bill.total }
            for event in bill.settlements where !event.reversed && event.accountID == accountID {
                value += event.direction == .incoming ? event.amount : -event.amount
            }
            return value
        }
        return opening + transactionCash + transferCash + splitCash
    }

    private func overview() -> FinancialOverview {
        let accountBalance = accounts.reduce(Int64(0)) { $0 + balance(for: $1.id) }
        var receivables: Int64 = 0
        var payables: Int64 = 0
        var splitExpense: Int64 = 0
        var nonCashIncome: Int64 = 0
        var nonCashExpense: Int64 = 0
        for bill in splitBills where !bill.deleted {
            splitExpense += bill.selfShare
            switch bill.payer {
            case .selfPaid:
                receivables += bill.obligationMembers.reduce(0) { $0 + $1.remainingAmount }
            case .other:
                payables += bill.remainingAmount
            }
            for resolution in bill.resolutions where !resolution.reversed {
                if resolution.kind == .receivableWriteoff { nonCashExpense += resolution.amount }
                else { nonCashIncome += resolution.amount }
            }
        }
        let income = transactions.filter { !$0.deleted && $0.kind == .income }.reduce(0) { $0 + $1.amount } + nonCashIncome
        let expense = transactions.filter { !$0.deleted && $0.kind == .expense }.reduce(0) { $0 + $1.amount } + splitExpense + nonCashExpense
        return FinancialOverview(accountBalance: accountBalance, receivables: receivables, payables: payables, netPosition: accountBalance + receivables - payables, personalIncome: income, personalExpense: expense)
    }

    private func spent(categoryID: String, month: Date) -> Int64 {
        let calendar = Calendar(identifier: .gregorian)
        let transactionSpend = transactions.filter { !$0.deleted && $0.kind == .expense && $0.categoryID == categoryID && calendar.isDate($0.occurredAt, equalTo: month, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        let splitSpend = splitBills.filter { !$0.deleted && $0.categoryID == categoryID && calendar.isDate($0.occurredAt, equalTo: month, toGranularity: .month) }.reduce(0) { $0 + $1.selfShare }
        let writeoffs = splitBills.filter { !$0.deleted && $0.categoryID == categoryID }.flatMap(\.resolutions).filter { !$0.reversed && $0.kind == .receivableWriteoff && calendar.isDate($0.occurredAt, equalTo: month, toGranularity: .month) }.reduce(0) { $0 + $1.amount }
        return transactionSpend + splitSpend + writeoffs
    }

    private func validateMoney(_ value: Int64) throws {
        guard value > 0, value <= Money.maximum else { throw AppError.validation("Nominal tidak valid.") }
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: " ").joined(separator: " ")
    }

    private func conflict() -> AppError {
        AppError(code: "CONFLICT_VERSION", message: "Data telah berubah. Muat ulang sebelum mencoba lagi.", requestID: nil, details: [:])
    }

    private func obligationExceeded() -> AppError {
        AppError(code: "OBLIGATION_EXCEEDED", message: "Jumlah melebihi sisa kewajiban.", requestID: nil, details: [:])
    }
}
