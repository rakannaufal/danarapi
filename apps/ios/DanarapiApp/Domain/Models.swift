import Foundation

@propertyWrapper
struct DecimalString: Codable, Hashable, Sendable {
    var wrappedValue: Int64

    init(wrappedValue: Int64) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard Self.isDecimal(value), let parsed = Int64(value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nominal harus string desimal Int64.")
        }
        wrappedValue = parsed
    }

    static func isDecimal(_ value: String) -> Bool {
        let digits = value.hasPrefix("-") ? value.dropFirst() : value[...]
        return value == "0" || (!digits.isEmpty && digits.first != "0" && digits.allSatisfy { $0 >= "0" && $0 <= "9" })
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(wrappedValue))
    }
}

@propertyWrapper
struct OptionalDecimalString: Codable, Hashable, Sendable {
    var wrappedValue: Int64?
    init(wrappedValue: Int64?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { wrappedValue = nil }
        else {
            let value = try container.decode(String.self)
            guard DecimalString.isDecimal(value), let parsed = Int64(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Nominal harus string desimal Int64.")
            }
            wrappedValue = parsed
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(String(wrappedValue)) } else { try container.encodeNil() }
    }
}

enum AppMode: String, Codable, Sendable {
    case signedOut
    case demo
    case authenticated
}

enum ThemePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Sistem"
        case .light: "Terang"
        case .dark: "Gelap"
        }
    }
}

enum AccountKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cash
    case bank
    case ewallet
    case other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cash: "Tunai"
        case .bank: "Bank"
        case .ewallet: "E-wallet"
        case .other: "Lainnya"
        }
    }
}

enum TransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case income
    case expense

    var id: String { rawValue }
    var title: String { self == .income ? "Pemasukan" : "Pengeluaran" }
}

enum ReviewSource: String, Codable, Sendable {
    case qris
    case image
    case pdfText = "pdf_text"
    case pastedText = "pasted_text"

    var title: String {
        switch self {
        case .qris: "QRIS"
        case .image: "Gambar"
        case .pdfText: "PDF"
        case .pastedText: "Teks"
        }
    }
}

enum ReviewStatus: String, Codable, Sendable {
    case pending
    case saved
    case rejected
    case merged
}

enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: "Tinggi"
        case .medium: "Sedang"
        case .low: "Rendah"
        }
    }
}

enum SplitPayer: Codable, Equatable, Hashable, Sendable {
    case selfPaid(accountID: String)
    case other(memberID: String)
}

enum SplitStatus: String, Codable, Sendable {
    case unsettled
    case partiallySettled = "partially_settled"
    case settled

    var title: String {
        switch self {
        case .unsettled: "Belum lunas"
        case .partiallySettled: "Lunas sebagian"
        case .settled: "Lunas"
        }
    }
}

enum SettlementDirection: String, Codable, Sendable {
    case incoming = "in"
    case outgoing = "out"
}

enum ResolutionKind: String, Codable, Sendable {
    case receivableWriteoff = "receivable_writeoff"
    case payableForgiveness = "payable_forgiveness"
}

enum MerchantMatchType: String, Codable, CaseIterable, Identifiable, Sendable {
    case exact
    case contains
    case prefix

    var id: String { rawValue }
    var title: String {
        switch self {
        case .exact: "Sama persis"
        case .contains: "Mengandung"
        case .prefix: "Diawali"
        }
    }
}

struct FinancialAccount: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: AccountKind
    @DecimalString var openingBalance: Int64
    @DecimalString var balance: Int64
    var openedAt: Date
    var archived: Bool
    var version: Int
}

struct Category: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var kind: TransactionKind
    var systemKey: String?
    var archived: Bool
    var sortOrder: Int
    var version: Int
}

struct FinanceTransaction: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var kind: TransactionKind
    @DecimalString var amount: Int64
    var accountID: String
    var categoryID: String
    var occurredAt: Date
    var merchant: String?
    var note: String?
    var source: String
    var pendingSync: Bool
    var deleted: Bool
    var version: Int
    var goalID: String? = nil
}

struct TransferRecord: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var fromAccountID: String
    var toAccountID: String
    @DecimalString var amount: Int64
    var occurredAt: Date
    var note: String?
    var pendingSync: Bool
    var deleted: Bool
    var version: Int
}

struct SplitMember: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var displayName: String
    var isSelf: Bool
    @DecimalString var shareAmount: Int64
    @DecimalString var settledAmount: Int64
    @DecimalString var resolvedAmount: Int64
    @OptionalDecimalString var obligationAmount: Int64? = nil
    var sortOrder: Int

    var remainingAmount: Int64 { max((obligationAmount ?? shareAmount) - settledAmount - resolvedAmount, 0) }
}

struct SplitSettlement: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let memberID: String
    let direction: SettlementDirection
    let accountID: String
    @DecimalString var amount: Int64
    let occurredAt: Date
    let note: String?
    var reversed: Bool
    var version: Int
}

struct SplitResolution: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let memberID: String
    let kind: ResolutionKind
    @DecimalString var amount: Int64
    let occurredAt: Date
    let reason: String
    var reversed: Bool
    var version: Int
}

struct SplitBill: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var title: String
    @DecimalString var total: Int64
    var categoryID: String
    var payer: SplitPayer
    var occurredAt: Date
    var note: String?
    var members: [SplitMember]
    var settlements: [SplitSettlement]
    var resolutions: [SplitResolution]
    var deleted: Bool
    var version: Int

    var itemSplit: ItemSplit? = nil

    var selfShare: Int64 { members.first(where: \.isSelf)?.shareAmount ?? 0 }
    var obligationMembers: [SplitMember] {
        switch payer {
        case .selfPaid:
            members.filter { !$0.isSelf }
        case let .other(memberID):
            members.filter { $0.id == memberID }
        }
    }
    var remainingAmount: Int64 { obligationMembers.reduce(0) { $0 + $1.remainingAmount } }
    var status: SplitStatus {
        if remainingAmount == 0 { return .settled }
        let handled = obligationMembers.reduce(0) { $0 + $1.settledAmount + $1.resolvedAmount }
        return handled > 0 ? .partiallySettled : .unsettled
    }
}

struct ExtractedField: Codable, Hashable, Sendable {
    var value: String?
    var confidence: Confidence
    var evidenceSpan: String?
    var sourceType: ReviewSource
}

struct ReviewItem: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var source: ReviewSource
    var status: ReviewStatus
    var amount: ExtractedField
    var merchant: ExtractedField
    var date: ExtractedField
    var rawReference: String?
    var duplicateCandidateID: String?
    var attachmentName: String?
    var createdAt: Date
    var receiptLines: [ReceiptLine]? = nil
    var receipt: ScannedReceipt? = nil

    func matchesID(_ candidate: String) -> Bool {
        if id == candidate { return true }
        guard let storedUUID = UUID(uuidString: id), let candidateUUID = UUID(uuidString: candidate) else { return false }
        return storedUUID == candidateUUID
    }
}

struct Budget: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let categoryID: String
    var month: Date
    @DecimalString var limitAmount: Int64
    @DecimalString var spentAmount: Int64

    var ratio: Double { limitAmount == 0 ? 0 : Double(spentAmount) / Double(limitAmount) }
    var status: String { spentAmount > limitAmount ? "over" : limitAmount > 0 && spentAmount * 10 >= limitAmount * 7 ? "warning" : "safe" }
}

struct MerchantRule: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var matchType: MerchantMatchType
    var normalizedPattern: String
    var categoryID: String
    var priority: Int
    var version: Int

    func matches(_ merchant: String) -> Bool {
        let candidate = Self.normalize(merchant)
        return switch matchType {
        case .exact: candidate == normalizedPattern
        case .contains: candidate.contains(normalizedPattern)
        case .prefix: candidate.hasPrefix(normalizedPattern)
        }
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "id_ID"))
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

struct FinancialOverview: Codable, Equatable, Sendable {
    @DecimalString var accountBalance: Int64
    @DecimalString var receivables: Int64
    @DecimalString var payables: Int64
    @DecimalString var netPosition: Int64
    @DecimalString var personalIncome: Int64
    @DecimalString var personalExpense: Int64

    static let zero = FinancialOverview(accountBalance: 0, receivables: 0, payables: 0, netPosition: 0, personalIncome: 0, personalExpense: 0)
}

struct BalanceAdjustment: Codable, Sendable {
    var id: String
    var accountID: String
    @DecimalString var signedAmount: Int64
    var reason: String
    var occurredAt: Date
}

struct DashboardSnapshot: Codable, Sendable {
    var accounts: [FinancialAccount]
    var categories: [Category]
    var transactions: [FinanceTransaction]
    var transfers: [TransferRecord]
    var splitBills: [SplitBill]
    var reviewItems: [ReviewItem]
    var merchantRules: [MerchantRule]
    var budgets: [Budget]
    var overview: FinancialOverview
    var nextTransactionCursor: TransactionCursor?
    var syncedAt: Date?
    var goals: [SavingsGoal]? = nil
    var monthlyReport: ReportSummary? = nil
    var reportMonth: String? = nil
    var timezone: String? = nil
    var adjustments: [BalanceAdjustment]? = nil

    @discardableResult
    mutating func reconcileAcknowledgedReview(_ item: ReviewItem, replacingExisting: Bool = false) -> Bool {
        if let index = reviewItems.firstIndex(where: { $0.matchesID(item.id) }) {
            guard replacingExisting else { return false }
            reviewItems[index] = item
        } else {
            reviewItems.insert(item, at: 0)
        }
        return true
    }
}

struct SavingsGoal: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    @DecimalString var targetAmount: Int64
    @DecimalString var savedAmount: Int64
    var targetDate: Date?
    var version: Int
    var progress: Double { min(1, Double(savedAmount) / Double(max(1, targetAmount))) }
    func countdown(asOf now: Date = .now) -> String {
        if savedAmount >= targetAmount { return "Tercapai" }
        guard let targetDate else { return "Tanpa tenggat" }
        let calendar = MonthPeriod.calendar
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: targetDate)).day ?? 0
        if days > 0 { return "\(days) hari lagi" }
        return days == 0 ? "Jatuh tempo hari ini" : "Lewat \(abs(days)) hari"
    }
}

enum BudgetCategoryPresets {
    static let names = ["Makan", "Transportasi", "Rumah", "Belanja", "Tagihan", "Kesehatan", "Pendidikan", "Hiburan", "Keluarga", "Lainnya"]
}

struct TransactionCursor: Codable, Hashable, Sendable {
    let occurredAt: Date
    let id: String
}

struct PlanningEntry: Codable, Identifiable, Sendable {
    let id: String
    let sourceID: String
    let kind: String
    @DecimalString var amount: Int64
    let occurredAt: Date
    let merchant: String?
    let note: String?
}
struct PlanningHistoryPage: Codable, Sendable {
    let items: [PlanningEntry]
    let nextCursor: TransactionCursor?
}
struct PlanningHistoryRequest: Codable, Sendable {
    var goalID: String? = nil
    var categoryID: String? = nil
    var startDate: Date? = nil
    var endDate: Date? = nil
    var cursor: TransactionCursor? = nil
}

struct TransactionPage: Codable, Sendable {
    let items: [FinanceTransaction]
    let nextCursor: TransactionCursor?
}

struct ReportCategoryAmount: Codable, Hashable, Sendable {
    let categoryID: String
    @DecimalString var amount: Int64
}

struct ReportSummary: Codable, Sendable {
    @DecimalString var personalIncome: Int64
    @DecimalString var personalExpense: Int64
    let categories: [ReportCategoryAmount]
    var allocations: [ReportAllocation]? = nil
    var cashAccounts: [ReportAccountCash]? = nil

    static let zero = ReportSummary(personalIncome: 0, personalExpense: 0, categories: [])
}

struct ReportAccountCash: Identifiable, Codable, Sendable {
    var id: String { accountID }
    let accountID: String
    @DecimalString var incoming: Int64
    @DecimalString var outgoing: Int64
    @DecimalString var net: Int64
}

struct ReportAllocation: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    @DecimalString var amount: Int64
}

struct ReviewAttachment: Sendable {
    let name: String
    let mimeType: String
    let data: Data
}

struct AccountDraft: Codable, Sendable {
    var name: String
    var kind: AccountKind
    @DecimalString var openingBalance: Int64
    var openedAt: Date
}

struct TransactionDraft: Codable, Sendable {
    var id: String?
    var kind: TransactionKind
    @DecimalString var amount: Int64
    var accountID: String
    var categoryID: String
    var occurredAt: Date
    var merchant: String?
    var note: String?
    var source: String
    var expectedVersion: Int?
    var goalID: String? = nil
}

struct TransferDraft: Codable, Sendable {
    var id: String? = nil
    var fromAccountID: String
    var toAccountID: String
    @DecimalString var amount: Int64
    var occurredAt: Date
    var note: String?
    var expectedVersion: Int? = nil
}

struct SplitBillDraft: Codable, Sendable {
    var title: String
    @DecimalString var total: Int64
    var categoryID: String
    var payer: SplitPayer
    var occurredAt: Date
    var note: String?
    var members: [SplitMember]
    var itemSplit: ItemSplit? = nil
}

struct SettlementDraft: Codable, Sendable {
    var billID: String
    var memberID: String
    var accountID: String
    @DecimalString var amount: Int64
    var occurredAt: Date
    var note: String?
}

struct ResolutionDraft: Codable, Sendable {
    var billID: String
    var memberID: String
    @DecimalString var amount: Int64
    var occurredAt: Date
    var reason: String
}

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userID: String
    let email: String?
    let expiresAt: Date
}

struct AppError: Error, Codable, Equatable, Sendable {
    let code: String
    let message: String
    let requestID: String?
    let details: [String: String]

    static func validation(_ message: String) -> AppError {
        AppError(code: "VALIDATION", message: message, requestID: nil, details: [:])
    }
}

extension Date {
    static let demoNow = ISO8601DateFormatter().date(from: "2026-09-30T03:00:00Z")!
}
