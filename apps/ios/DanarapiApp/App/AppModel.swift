import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    private(set) var mode: AppMode = .signedOut
    private(set) var snapshot = DashboardSnapshot(accounts: [], categories: [], transactions: [], transfers: [], splitBills: [], reviewItems: [], merchantRules: [], budgets: [], overview: .zero, nextTransactionCursor: nil, syncedAt: nil)
    private(set) var isLoading = false
    private(set) var isStarting = true
    private(set) var hasLoadedDashboard = false
    private(set) var dashboardError: String?
    private(set) var monthlyReportError: String?
    var monthlyReport: ReportSummary? { snapshot.reportMonth == MonthPeriod.key(.now) ? snapshot.monthlyReport : nil }
    private(set) var isOnline = true
    private(set) var pendingOutboxCount = 0
    private(set) var isLoadingMoreTransactions = false
    private(set) var isSyncing = false
    private(set) var outboxChanges: [OutboxRecord] = []
    private(set) var requiresReauthentication = false
    private(set) var isAuthenticating = false
    private(set) var lastRejectedReview: ReviewItem?
    private(set) var session: AuthSession?
    var errorMessage: String?
    var toastMessage: String?
    var isLocked = false
    var privacyCoverVisible = false
    var productPage: ProductRoute?
    private(set) var aiConsent: AIConsentState?
    var timezone: String { snapshot.timezone ?? defaults.string(forKey: "financeTimezone") ?? "Asia/Jakarta" }

    var theme: ThemePreference {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }
    var hideAmounts: Bool {
        didSet { defaults.set(hideAmounts, forKey: "hideAmounts") }
    }
    var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: "appLockEnabled") }
    }
    private var onboardingRevision = 0
    private var demoOnboardingCompleted = false
    var onboardingCompleted: Bool {
        _ = onboardingRevision
        if mode == .demo { return demoOnboardingCompleted }
        guard mode == .authenticated, let userID = session?.userID else { return true }
        return hasCompletedOnboarding(userID: userID)
    }

    func hasCompletedOnboarding(userID: String) -> Bool {
        defaults.bool(forKey: "onboardingCompleted.\(userID)")
    }

    func completeOnboarding() {
        if mode == .demo {
            demoOnboardingCompleted = true
            return
        }
        guard mode == .authenticated, let userID = session?.userID else { return }
        defaults.set(true, forKey: "onboardingCompleted.\(userID)")
        onboardingRevision += 1
    }

    let network = NetworkMonitor()
    let offlineStore: OfflineStore
    let sessionStore: KeychainSessionStore
    private let defaults: UserDefaults
    private var repository: any FinanceRepository
    private var authService: AuthService?
    private var configuration: SupabaseConfiguration?
    private var recoverySession: AuthSession?
    private let oauthPresenter = OAuthPresenter()
    private var signInTask: Task<Void, Never>?
    private var outboxRetryTask: Task<Void, Never>?
    private var didStart = false
    private var dashboardLoadVersion = 0

    var showsStartupScreen: Bool {
        isStarting || (mode != .signedOut && !requiresReauthentication && !hasLoadedDashboard && (isLoading || dashboardError == nil))
    }

    init(
        defaults: UserDefaults = .standard,
        sessionStore: KeychainSessionStore = KeychainSessionStore(),
        offlineStore: OfflineStore
    ) {
        self.defaults = defaults
        self.sessionStore = sessionStore
        self.offlineStore = offlineStore
        theme = ThemePreference(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        hideAmounts = defaults.bool(forKey: "hideAmounts")
        appLockEnabled = defaults.bool(forKey: "appLockEnabled")
        repository = RepositoryFactory.demo()
        configuration = SupabaseConfiguration.fromBundle()
        if let configuration { authService = AuthService(configuration: configuration, sessionStore: sessionStore) }
    }

    static func make() -> AppModel {
        do { return AppModel(offlineStore: try OfflineStore()) }
        catch {
            let app = AppModel(offlineStore: try! OfflineStore(inMemory: true))
            app.errorMessage = "Penyimpanan terlindungi tidak tersedia. Pencatatan transaksi/transfer akun nyata dinonaktifkan; Mode Demo tetap tersedia."
            return app
        }
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var ownerID: String { mode == .demo ? "demo" : session?.userID ?? "signed-out" }
    var activeAccounts: [FinancialAccount] { snapshot.accounts.filter { !$0.archived } }
    var expenseCategories: [Category] { snapshot.categories.filter { $0.kind == .expense && !$0.archived } }
    var incomeCategories: [Category] { snapshot.categories.filter { $0.kind == .income && !$0.archived } }

    func start() async {
        guard !didStart else { return }
        didStart = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-startup") { return }
        #endif
        defer { isStarting = false }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-auth") {
            mode = .signedOut
            hasLoadedDashboard = false
            dashboardError = nil
            return
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-demo") {
            await startDemo()
            return
        }
        isOnline = network.isOnline
        if let stored = try? sessionStore.load() {
            session = stored
            guard let configuration else {
                errorMessage = "Konfigurasi Supabase belum diisi. Mode Demo tetap tersedia."
                return
            }
            mode = .authenticated
            repository = RepositoryFactory.remote(configuration: configuration, sessionStore: sessionStore)
            if appLockEnabled { isLocked = true }
            await refresh()
        }
    }

    func startDemo() async {
        guard mode != .authenticated else { return }
        demoOnboardingCompleted = false
        repository = RepositoryFactory.demo()
        mode = .demo
        session = nil
        await refresh()
    }

    func startGoogleSignIn() {
        guard signInTask == nil, !isAuthenticating else { return }
        signInTask = Task { [weak self] in
            guard let self else { return }
            defer { self.signInTask = nil }
            _ = await self.signIn(provider: "google")
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        oauthPresenter.cancel()
    }

    func signIn(provider: String) async -> Bool {
        guard !isAuthenticating else { return false }
        guard let authService, let configuration else { errorMessage = "Login belum dikonfigurasi."; return false }
        isAuthenticating = true
        errorMessage = nil
        dashboardLoadVersion += 1
        pauseOutboxRetry()
        defer { isAuthenticating = false }
        do {
            try Task.checkCancellation()
            try await authService.ensureOAuthProvider(provider)
            try Task.checkCancellation()
            let verifier = try OAuthPKCE.verifier()
            let url = try await authService.oauthURL(provider: provider, verifier: verifier)
            let callback = try await oauthPresenter.authenticate(url: url)
            try Task.checkCancellation()
            return await run {
                let value = try await authService.finishOAuth(callback: callback, verifier: verifier, expectedUserID: mode == .authenticated ? session?.userID : nil)
                session = value
                repository = RepositoryFactory.remote(configuration: configuration, sessionStore: sessionStore)
                mode = .authenticated
                requiresReauthentication = false
                try await loadDashboard()
            }
        } catch is CancellationError { return false }
        catch let error as URLError where error.code == .cancelled { return false }
        catch { present(error); return false }
    }

    func signIn(email: String, password: String) async -> Bool {
        guard let authService, let configuration else {
            errorMessage = "SUPABASE_URL dan SUPABASE_ANON_KEY belum dikonfigurasi."
            return false
        }
        return await run {
            let value = try await authService.signIn(email: email, password: password, expectedUserID: mode == .authenticated ? session?.userID : nil)
            session = value
            repository = RepositoryFactory.remote(configuration: configuration, sessionStore: sessionStore)
            mode = .authenticated
            requiresReauthentication = false
            try await loadDashboard()
        }
    }

    func signUp(email: String, password: String) async -> Bool {
        guard let authService else { errorMessage = "Backend belum dikonfigurasi."; return false }
        return await run { try await authService.signUp(email: email, password: password) }
    }

    func verify(email: String, code: String) async -> Bool {
        guard let authService, let configuration else { errorMessage = "Backend belum dikonfigurasi."; return false }
        return await run {
            session = try await authService.verify(email: email, code: code)
            repository = RepositoryFactory.remote(configuration: configuration, sessionStore: sessionStore)
            mode = .authenticated
            try await loadDashboard()
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        guard let authService else { errorMessage = "Backend belum dikonfigurasi."; return false }
        return await run { try await authService.requestPasswordReset(email: email) }
    }

    func resendVerification(email: String) async -> Bool {
        guard let authService else { errorMessage = "Backend belum dikonfigurasi."; return false }
        return await run { try await authService.resendVerification(email: email) }
    }

    func verifyRecovery(email: String, code: String) async -> Bool {
        guard mode == .signedOut, let authService else { return false }
        return await run { recoverySession = try await authService.verifyRecovery(email: email, code: code) }
    }

    func resetPassword(_ password: String) async -> Bool {
        guard mode == .signedOut, let authService, let recoverySession else { return false }
        return await run {
            try await authService.resetPassword(password, recovery: recoverySession)
            self.recoverySession = nil
            toastMessage = "Kata sandi diubah. Masuk dengan kata sandi baru."
        }
    }

    func cancelRecovery() { recoverySession = nil }

    func logout(discardPending: Bool = false) async -> Bool {
        guard !isSyncing else { errorMessage = "Tunggu sinkronisasi selesai sebelum keluar."; return false }
        pendingOutboxCount = (try? offlineStore.count(ownerID: ownerID)) ?? pendingOutboxCount
        if pendingOutboxCount > 0 && !discardPending {
            errorMessage = isOnline ? "Sinkronkan perubahan perangkat sebelum keluar, atau pilih buang perubahan." : "Ada perubahan offline. Buang secara eksplisit sebelum keluar."
            return false
        }
        return await run {
            if mode == .authenticated && network.isOnline { try await authService?.signOut() }
            try offlineStore.clear(ownerID: ownerID)
            sessionStore.clear()
            session = nil
            aiConsent = nil
            AIConsentPresenter.cancel()
            defaults.removeObject(forKey: "financeTimezone")
            UserDefaults.standard.removeObject(forKey: "financeTimezone")
            mode = .signedOut
            isLocked = false
            requiresReauthentication = false
            recoverySession = nil
            outboxRetryTask?.cancel()
            outboxRetryTask = nil
            outboxChanges = []
            pendingOutboxCount = 0
            lastRejectedReview = nil
            snapshot = DashboardSnapshot(accounts: [], categories: [], transactions: [], transfers: [], splitBills: [], reviewItems: [], merchantRules: [], budgets: [], overview: .zero, nextTransactionCursor: nil, syncedAt: nil)
            repository = RepositoryFactory.demo()
        }
    }

    func resetDemo() async { _ = await mutate(success: "Data contoh direset.") { try await repository.resetDemo() } }

    func refresh() async {
        guard mode != .signedOut, !isAuthenticating, !requiresReauthentication else { return }
        let requestedOwner = ownerID
        let requestedMode = mode
        var requestedVersion = dashboardLoadVersion
        isOnline = network.isOnline
        isLoading = true
        dashboardError = nil
        defer { isLoading = false }
        do {
            if mode == .authenticated && !isOnline {
                guard let cached = try offlineStore.cachedSnapshot(ownerID: ownerID) else { throw AppError.validation("Hubungkan internet untuk memuat catatan pertama kali.") }
                snapshot = cached
                adoptTimezone(cached.timezone)
                hasLoadedDashboard = true
                try updateOfflineProjection()
                return
            }
            requestedVersion = dashboardLoadVersion + 1
            try await loadDashboard()
            guard ownerID == requestedOwner, mode == requestedMode else { return }
            if mode == .authenticated {
                await syncOutbox()
            }
        } catch {
            guard ownerID == requestedOwner, mode == requestedMode, dashboardLoadVersion == requestedVersion else { return }
            guard !isAuthenticating, !requiresReauthentication else { return }
            if mode == .authenticated {
                if let cached = try? offlineStore.cachedSnapshot(ownerID: ownerID) { snapshot = cached; adoptTimezone(cached.timezone); hasLoadedDashboard = true }
                try? updateOfflineProjection()
            }
            present(error)
        }
    }

    func loadMoreTransactions() async {
        guard let cursor = snapshot.nextTransactionCursor, !isLoadingMoreTransactions else { return }
        let requestedOwner = ownerID
        let requestedMode = mode
        isLoadingMoreTransactions = true
        defer { isLoadingMoreTransactions = false }
        do {
            let page = try await repository.transactionPage(after: cursor)
            guard ownerID == requestedOwner, mode == requestedMode else { return }
            let known = Set(snapshot.transactions.map(\.id))
            snapshot.transactions.append(contentsOf: page.items.filter { !known.contains($0.id) })
            snapshot.nextTransactionCursor = page.nextCursor
            if mode == .authenticated { try offlineStore.cache(snapshot, ownerID: ownerID) }
        } catch {
            guard ownerID == requestedOwner, mode == requestedMode else { return }
            present(error)
        }
    }
    func ensureTransaction(id: String) async throws {
        if snapshot.transactions.contains(where: { $0.id == id }) { return }
        let requestedOwner = ownerID
        let value = try await repository.transaction(id: id)
        guard requestedOwner == ownerID else { throw AppError.validation("Akun berubah.") }
        if !snapshot.transactions.contains(where: { $0.id == id }) { snapshot.transactions.append(value) }
    }
    func planningHistory(_ request: PlanningHistoryRequest) async throws -> PlanningHistoryPage {
        let requestedOwner = ownerID
        let value = try await repository.planningHistory(request)
        guard requestedOwner == ownerID else { throw AppError.validation("Akun berubah.") }
        return value
    }
    func copyBudgets(from: Date, to: Date) async -> Bool { await onlineMutation { try await repository.copyBudgets(from: from, to: to) } }

    func report(since startDate: Date, until endDate: Date? = nil) async -> ReportSummary? {
        let requestedOwner = ownerID
        let requestedMode = mode
        do {
            let value = try await repository.report(since: startDate, until: endDate)
            guard ownerID == requestedOwner, mode == requestedMode else { return nil }
            return value
        } catch {
            guard ownerID == requestedOwner, mode == requestedMode else { return nil }
            present(error)
            return nil
        }
    }

    @discardableResult func createAccount(_ draft: AccountDraft) async -> Bool { await mutate { try await repository.createAccount(draft) } }
    func saveGoal(_ goal: SavingsGoal) async -> Bool { await onlineMutation { try await repository.saveGoal(goal) } }
    func deleteGoal(_ goal: SavingsGoal) async -> Bool { await onlineMutation { try await repository.deleteGoal(id: goal.id, expectedVersion: goal.version) } }
    func calculateItemSplit(_ draft: ItemSplit, memberIDs: [String]) async throws -> ItemSplitResult {
        guard mode == .demo || network.isOnline else { throw AppError.validation("Split bill akun nyata memerlukan koneksi.") }
        return try await repository.calculateItemSplit(draft, memberIDs: memberIDs)
    }
    func scanReceipt(images: [ReceiptScanImage]) async throws -> ReceiptScanResponse {
        if mode == .demo, ProcessInfo.processInfo.arguments.contains("--local-receipt-scan") {
            guard let scanner = DevelopmentReceiptScanConfiguration.bundled else { throw AppError.validation("Scanner pengembangan belum dikonfigurasi.") }
            if aiConsent?.granted != true || aiConsent?.policyVersion != ProductCatalog.policyVersion {
                guard await AIConsentPresenter.request() else { throw AppError.validation("Pengiriman AI dibatalkan.") }
                try Task.checkCancellation()
                aiConsent = AIConsentState(granted: true,policyVersion: ProductCatalog.policyVersion,updatedAt: .now)
            }
            try Task.checkCancellation()
            return try await scanner.scan(images)
        }
        guard configuration != nil else { throw AppError.validation("Layanan scan cloud belum dikonfigurasi. Foto tetap tersedia.") }
        guard mode == .authenticated else { throw AppError.validation("Masuk akun untuk membaca struk melalui layanan cloud.") }
        guard network.isOnline else { throw AppError.validation("Hubungkan internet untuk membaca struk. Foto tetap tersedia.") }
        let requestedOwner = ownerID
        let consent = try await refreshAIConsent()
        if !(consent.granted && consent.policyVersion == ProductCatalog.policyVersion) {
            guard await AIConsentPresenter.request() else { throw AppError.validation("Pengiriman AI dibatalkan. Isi manual tetap tersedia.") }
            try Task.checkCancellation()
            guard requestedOwner == ownerID, mode == .authenticated else { throw AppError.validation("Akun berubah. Coba kembali.") }
            try await setAIConsent(true)
        }
        try Task.checkCancellation()
        guard requestedOwner == ownerID, mode == .authenticated else { throw AppError.validation("Akun berubah. Coba kembali.") }
        return try await repository.scanReceipt(images: images)
    }
    func refreshAIConsent() async throws -> AIConsentState {
        let requestedOwner = ownerID
        let result = try await repository.aiConsentState()
        guard requestedOwner == ownerID else { throw AppError.validation("Akun berubah.") }
        aiConsent = result
        return result
    }
    func setAIConsent(_ granted: Bool) async throws {
        guard mode == .authenticated else { throw AppError.validation("Masuk untuk mengubah persetujuan AI.") }
        let requestedOwner = ownerID
        try await repository.setAIConsent(granted: granted, policyVersion: ProductCatalog.policyVersion)
        guard requestedOwner == ownerID else { throw AppError.validation("Akun berubah.") }
        aiConsent = AIConsentState(granted: granted, policyVersion: ProductCatalog.policyVersion, updatedAt: .now)
    }
    func updateTimezone(_ value: String) async -> Bool {
        guard ["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura", "UTC"].contains(value) else { return false }
        return await onlineMutation {
            try await repository.setTimezone(value)
            defaults.set(value, forKey: "financeTimezone")
            UserDefaults.standard.set(value, forKey: "financeTimezone")
            snapshot.timezone = value
        }
    }
    func acknowledgeRetention() async throws { try await repository.acknowledgeRetention() }
    func supportTickets() async throws -> [SupportTicket] { try await repository.supportTickets() }
    func reportResult(since startDate: Date, until endDate: Date) async throws -> ReportSummary {
        let requestedOwner = ownerID
        let value = try await repository.report(since: startDate, until: endDate)
        guard requestedOwner == ownerID else { throw AppError.validation("Akun berubah.") }
        return value
    }
    func sendSupportTicket(id: String, topic: String, description: String, requestID: String?) async throws { try await repository.sendSupportTicket(id: id, topic: topic, description: description, requestID: requestID) }
    func productInfo() async throws -> ProductInfo {
        guard let configuration else { throw AppError.validation("Layanan belum dikonfigurasi.") }
        var request = URLRequest(url: try configuration.endpoint("/functions/v1/product-info"))
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.validation("Status layanan belum dapat diperiksa.") }
        return try JSONDecoder.danarapi.decode(ProductInfo.self, from: data)
    }
    var cloudReceiptScanConfigured: Bool { configuration != nil }
    @discardableResult func updateAccount(_ account: FinancialAccount) async -> Bool { await mutate { try await repository.updateAccount(account) } }
    @discardableResult func archiveAccount(_ account: FinancialAccount) async -> Bool { await mutate { try await repository.archiveAccount(id: account.id, expectedVersion: account.version) } }
    @discardableResult func createCategory(name: String, kind: TransactionKind) async -> Bool { await mutate { try await repository.createCategory(name: name, kind: kind) } }
    @discardableResult func updateCategory(_ category: Category) async -> Bool { await mutate { try await repository.updateCategory(category) } }
    func archiveCategory(_ category: Category) async { _ = await mutate { try await repository.archiveCategory(id: category.id, expectedVersion: category.version) } }

    func saveTransaction(_ draft: TransactionDraft) async -> Bool {
        if let id = draft.id, snapshot.transactions.contains(where: { $0.id == id && $0.pendingSync }) {
            present(AppError.validation("Sinkronkan atau buang perubahan sebelumnya sebelum mengubah catatan ini.")); return false
        }
        if mode == .authenticated {
            guard !isLoading else { return false }
            isLoading = true
            defer { isLoading = false }
            do {
                try requirePersistentOutbox()
                let operation = draft.id == nil ? "create_transaction" : "update_transaction"
                try offlineStore.enqueue(ownerID: ownerID, operation: operation, payload: draft, baseVersion: draft.expectedVersion)
                try updateOfflineProjection()
                return await finishQueuedMutation(success: "Tersimpan")
            } catch { present(error); return false }
        }
        return await mutate { try await repository.saveTransaction(draft) }
    }

    func deleteTransaction(_ item: FinanceTransaction) async -> Bool {
        guard !snapshot.transactions.contains(where: { $0.id == item.id && $0.pendingSync }) else {
            present(AppError.validation("Sinkronkan atau buang perubahan sebelumnya sebelum menghapus catatan ini.")); return false
        }
        if mode == .authenticated {
            guard !isLoading else { return false }
            isLoading = true
            defer { isLoading = false }
            do {
                try requirePersistentOutbox()
                try offlineStore.enqueue(ownerID: ownerID, operation: "delete_transaction", payload: VersionedID(id: item.id, version: item.version), baseVersion: item.version)
                if let index = snapshot.transactions.firstIndex(where: { $0.id == item.id }) { snapshot.transactions.remove(at: index) }
                try updateOfflineProjection()
                return await finishQueuedMutation(success: "Transaksi dihapus. Urungkan tersedia 10 detik.")
            } catch { present(error); return false }
        }
        return await mutate(success: "Transaksi dihapus. Urungkan tersedia 10 detik.") { try await repository.deleteTransaction(id: item.id, expectedVersion: item.version) }
    }

    func restoreTransaction(_ item: FinanceTransaction) async -> Bool {
        if let record = outboxChanges.first(where: { $0.operation == "delete_transaction" && (try? JSONDecoder.danarapi.decode(VersionedID.self, from: $0.payload).id) == item.id }) {
            guard !isSyncing, record.status == "pending", record.retryCount == 0 else {
                present(AppError.validation("Tunggu hasil sinkronisasi sebelum membatalkan penghapusan.")); return false
            }
            return await run {
                try offlineStore.discard(mutationID: record.mutationID, ownerID: ownerID)
                if let cached = try offlineStore.cachedSnapshot(ownerID: ownerID) { snapshot = cached }
                if !snapshot.transactions.contains(where: { $0.id == item.id }) { snapshot.transactions.insert(item, at: 0) }
                try updateOfflineProjection()
                toastMessage = "Penghapusan dibatalkan di perangkat."
            }
        }
        return await mutate { try await repository.restoreTransaction(id: item.id, expectedVersion: item.version + 1) }
    }

    func createTransfer(_ draft: TransferDraft) async -> Bool {
        if let id = draft.id, snapshot.transfers.contains(where: { $0.id == id && $0.pendingSync }) {
            present(AppError.validation("Sinkronkan atau buang perubahan sebelumnya sebelum mengubah transfer ini.")); return false
        }
        if mode == .authenticated {
            guard !isLoading else { return false }
            isLoading = true
            defer { isLoading = false }
            do {
                try requirePersistentOutbox()
                try offlineStore.enqueue(ownerID: ownerID, operation: draft.id == nil ? "create_transfer" : "update_transfer", payload: draft, baseVersion: draft.expectedVersion)
                try updateOfflineProjection()
                return await finishQueuedMutation(success: "Transfer tersimpan")
            } catch { present(error); return false }
        }
        return await mutate { try await repository.createTransfer(draft) }
    }

    func deleteTransfer(_ item: TransferRecord) async -> Bool {
        guard !snapshot.transfers.contains(where: { $0.id == item.id && $0.pendingSync }) else {
            present(AppError.validation("Sinkronkan atau buang perubahan sebelumnya sebelum menghapus transfer ini.")); return false
        }
        if mode == .authenticated {
            guard !isLoading else { return false }
            isLoading = true
            defer { isLoading = false }
            do {
                try requirePersistentOutbox()
                try offlineStore.enqueue(ownerID: ownerID, operation: "delete_transfer", payload: VersionedID(id: item.id, version: item.version), baseVersion: item.version)
                snapshot.transfers.removeAll { $0.id == item.id }
                try updateOfflineProjection()
                return await finishQueuedMutation(success: "Transfer dihapus")
            } catch { present(error); return false }
        }
        return await mutate { try await repository.deleteTransfer(id: item.id, expectedVersion: item.version) }
    }

    func createSplitBill(_ draft: SplitBillDraft, reviewItemID: String? = nil) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Split bill akun nyata memerlukan internet pada R1.", requestID: nil, details: [:])); return false }
        return await mutate {
            if let reviewItemID { try await repository.createSplitBillFromReview(reviewItemID: reviewItemID, draft: draft) }
            else { try await repository.createSplitBill(draft) }
        }
    }

    func updateSplitBill(_ bill: SplitBill, draft: SplitBillDraft) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Mengubah split bill akun nyata memerlukan internet pada R1.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.updateSplitBill(id: bill.id, expectedVersion: bill.version, draft: draft) }
    }

    func convertTransactionToSplitBill(_ transaction: FinanceTransaction, draft: SplitBillDraft) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Konversi transaksi ke split bill memerlukan internet pada akun nyata.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.convertTransactionToSplitBill(transactionID: transaction.id, expectedVersion: transaction.version, draft: draft) }
    }

    func calculateEqualSplit(total: Int64, participants: [EqualParticipant]) async throws -> [String: Int64] {
        try await repository.calculateEqualSplit(total: total, participants: participants)
    }

    func calculatePercentageSplit(total: Int64, participants: [PercentageParticipant]) async throws -> [String: Int64] {
        try await repository.calculatePercentageSplit(total: total, participants: participants)
    }

    func recordSettlement(_ draft: SettlementDraft) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Pelunasan akun nyata memerlukan internet.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.recordSettlement(draft) }
    }

    func recordResolution(_ draft: ResolutionDraft) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Penghapusan kewajiban memerlukan internet.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.recordResolution(draft) }
    }

    func reverseSettlement(_ item: SplitSettlement, reason: String) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Pembatalan pelunasan memerlukan internet.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.reverseSettlement(id: item.id, expectedVersion: item.version, reason: reason) }
    }
    func reverseResolution(_ item: SplitResolution, reason: String) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Pembatalan penghapusan memerlukan internet.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.reverseResolution(id: item.id, expectedVersion: item.version, reason: reason) }
    }
    func deleteSplitBill(_ bill: SplitBill) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Menghapus split bill memerlukan internet.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.deleteSplitBill(id: bill.id, expectedVersion: bill.version) }
    }
    func restoreSplitBill(_ bill: SplitBill) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Urungkan split bill memerlukan internet.", requestID: nil, details: [:])); return false }
        return await mutate { try await repository.restoreSplitBill(id: bill.id, expectedVersion: bill.version + 1) }
    }

    func addReview(_ item: ReviewItem, attachment: ReviewAttachment? = nil) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Draft lokal dapat dibuat, tetapi unggah lampiran memerlukan internet pada R1.", requestID: nil, details: [:])); return false }
        var value = item
        value.duplicateCandidateID = ImportService.duplicateCandidate(for: value, transactions: snapshot.transactions)
        let requestedRepository = repository
        return await persistReview(value) { try await requestedRepository.addReviewItem(value, attachment: attachment) }
    }

    func rejectReview(_ item: ReviewItem) async {
        if await mutate(success: "Item ditolak. Urungkan tersedia 10 detik.", operation: { try await repository.rejectReviewItem(id: item.id) }) { lastRejectedReview = item }
    }
    func restoreRejectedReview() async {
        guard let item = lastRejectedReview else { return }
        if await mutate(success: "Item dikembalikan.", operation: { try await repository.restoreReviewItem(id: item.id) }) { lastRejectedReview = nil }
    }
    func clearReviewUndo() { lastRejectedReview = nil }
    func updateReview(_ item: ReviewItem) async -> Bool {
        let requestedRepository = repository
        return await persistReview(item) { try await requestedRepository.updateReviewItem(item) }
    }
    func confirmReview(_ item: ReviewItem, transaction: TransactionDraft) async -> Bool { await mutate { try await repository.confirmReviewItem(id: item.id, transaction: transaction) } }
    func mergeReview(_ item: ReviewItem, into transactionID: String) async -> Bool { await mutate { try await repository.mergeReviewItem(id: item.id, into: transactionID) } }
    func clearReviewDuplicate(_ item: ReviewItem) async -> Bool { await mutate(success: "Ditandai bukan duplikat.") { try await repository.clearReviewDuplicate(id: item.id) } }
    func completeReview(_ item: ReviewItem) async { _ = await mutate { try await repository.completeReviewItem(id: item.id) } }
    func saveMerchantRule(_ rule: MerchantRule) async -> Bool { await mutate { try await repository.saveMerchantRule(rule) } }
    func deleteMerchantRule(_ rule: MerchantRule) async -> Bool { await mutate { try await repository.deleteMerchantRule(id: rule.id, expectedVersion: rule.version) } }
    func upsertBudget(categoryID: String, month: Date, limit: Int64) async -> Bool { await mutate { try await repository.upsertBudget(categoryID: categoryID, month: month, limit: limit) } }

    func exportArchive() async -> URL? {
        do { return try await repository.exportArchive() }
        catch { present(error); return nil }
    }

    func deleteAccount(password: String) async -> Bool {
        guard mode == .authenticated, network.isOnline else { present(AppError(code: "REQUIRES_ONLINE", message: "Hapus akun hanya tersedia online untuk akun nyata.", requestID: nil, details: [:])); return false }
        guard pendingOutboxCount == 0 else { present(AppError.validation("Sinkronkan atau buang perubahan offline lebih dahulu.")); return false }
        return await run {
            let owner = ownerID
            try await repository.requestAccountDeletion(password: password)
            try offlineStore.clear(ownerID: owner)
            sessionStore.clear()
            session = nil
            mode = .signedOut
            hasLoadedDashboard = false
            dashboardError = nil
            repository = RepositoryFactory.demo()
            snapshot = DashboardSnapshot(accounts: [], categories: [], transactions: [], transfers: [], splitBills: [], reviewItems: [], merchantRules: [], budgets: [], overview: .zero, nextTransactionCursor: nil, syncedAt: nil)
            toastMessage = "Permintaan penghapusan selesai."
            lastRejectedReview = nil
            isLocked = false
            requiresReauthentication = false
            pendingOutboxCount = 0
            outboxChanges = []
            pauseOutboxRetry()
        }
    }

    func unlock() async { if await AppLockService.unlock() { isLocked = false } }
    func unlock(password: String) async -> Bool {
        guard network.isOnline, let email = session?.email, let authService else {
            present(AppError(code: "REQUIRES_ONLINE", message: "Kata sandi akun memerlukan koneksi. Gunakan Face ID, Touch ID, atau kode perangkat saat offline.", requestID: nil, details: [:]))
            return false
        }
        return await run {
            let refreshed = try await authService.signIn(email: email, password: password, expectedUserID: session?.userID)
            guard refreshed.userID == session?.userID else { throw AppError(code: "UNAUTHORIZED", message: "Akun tidak cocok.", requestID: nil, details: [:]) }
            session = refreshed
            isLocked = false
        }
    }
    func lockIfNeeded() { if appLockEnabled && mode == .authenticated { isLocked = true } }

    func syncOutbox(forceRetry: Bool = false) async {
        guard mode == .authenticated, network.isOnline, !isSyncing, !requiresReauthentication,
              UIApplication.shared.isProtectedDataAvailable, UIApplication.shared.applicationState == .active else { return }
        isSyncing = true
        defer { isSyncing = false; scheduleOutboxRetry() }
        do {
            try updateOfflineProjection()
            if outboxChanges.contains(where: { $0.status == "conflict" }) {
                errorMessage = "Versi server berubah. Tinjau perubahan perangkat di Pengaturan; sinkronisasi dihentikan tanpa menimpa server."
                return
            }
            for record in try offlineStore.pending(ownerID: ownerID, forceRetry: forceRetry) {
                guard UIApplication.shared.isProtectedDataAvailable, UIApplication.shared.applicationState == .active else { break }
                do {
                    try await repository.replayOutbox(operation: record.operation, mutationID: record.mutationID, payload: record.payload)
                    guard UIApplication.shared.isProtectedDataAvailable, UIApplication.shared.applicationState == .active else { break }
                    try offlineStore.markSynced(record)
                } catch let error as AppError {
                    try offlineStore.markFailed(record, code: error.code)
                    present(error)
                    break
                } catch {
                    try offlineStore.markFailed(record, code: error is URLError ? "NETWORK" : "INTERNAL")
                    present(error)
                    break
                }
            }
            guard UIApplication.shared.isProtectedDataAvailable, UIApplication.shared.applicationState == .active else { return }
            try await loadDashboard()
        } catch { try? updateOfflineProjection(); present(error) }
    }

    func discardOutboxChange(_ mutationID: String) async -> Bool {
        guard mode == .authenticated, network.isOnline, !isSyncing else {
            present(AppError.validation("Hubungkan perangkat dan tunggu sinkronisasi selesai untuk memuat versi server.")); return false
        }
        return await run {
            let server = try await repository.dashboard()
            try offlineStore.discard(mutationID: mutationID, ownerID: ownerID)
            try offlineStore.cache(server, ownerID: ownerID)
            snapshot = server
            try updateOfflineProjection()
            toastMessage = "Perubahan perangkat dibuang. Versi server dimuat."
        }
    }

    func pauseOutboxRetry() {
        outboxRetryTask?.cancel()
        outboxRetryTask = nil
    }

    private func scheduleOutboxRetry() {
        pauseOutboxRetry()
        guard mode == .authenticated, !requiresReauthentication, network.isOnline,
              UIApplication.shared.applicationState == .active,
              !outboxChanges.contains(where: { $0.status == "conflict" }),
              let next = outboxChanges.compactMap(\.nextRetryAt).min() else { return }
        let owner = ownerID
        outboxRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) }
            catch { return }
            guard let self, self.ownerID == owner else { return }
            self.outboxRetryTask = nil
            await self.syncOutbox()
        }
    }

    func serverSnapshotForOutbox(_ change: OutboxRecord) async throws -> DashboardSnapshot {
        guard change.ownerID == ownerID, mode == .authenticated, network.isOnline else {
            throw AppError.validation("Hubungkan perangkat untuk membandingkan versi server.")
        }
        let owner = ownerID
        var value = try await repository.dashboard()
        let transactionID: String?
        if change.operation == "update_transaction" {
            transactionID = try JSONDecoder.danarapi.decode(TransactionDraft.self, from: change.payload).id
        } else if change.operation == "delete_transaction" {
            transactionID = try JSONDecoder.danarapi.decode(VersionedID.self, from: change.payload).id
        } else { transactionID = nil }
        if let id = transactionID {
            while !value.transactions.contains(where: { $0.id == id }), let cursor = value.nextTransactionCursor {
                let page = try await repository.transactionPage(after: cursor)
                value.transactions.append(contentsOf: page.items)
                value.nextTransactionCursor = page.nextCursor
            }
        }
        guard owner == ownerID else { throw AppError.validation("Sesi akun berubah.") }
        return value
    }

    func saveOutboxConflictAsNew(_ change: OutboxRecord) async -> Bool {
        guard !isSyncing else { return false }
        let saved = await run {
            let server = try await serverSnapshotForOutbox(change)
            try offlineStore.saveConflictAsNew(mutationID: change.mutationID, ownerID: ownerID)
            try offlineStore.cache(server, ownerID: ownerID)
            snapshot = server
            try updateOfflineProjection()
        }
        if saved { await syncOutbox() }
        return saved
    }

    private func requirePersistentOutbox() throws {
        guard offlineStore.isPersistent else { throw AppError.validation("Penyimpanan terlindungi tidak tersedia. Buka kunci perangkat lalu mulai ulang aplikasi sebelum mencatat transaksi/transfer akun nyata.") }
        guard UIApplication.shared.isProtectedDataAvailable, UIApplication.shared.applicationState == .active else {
            throw AppError.validation("Buka perangkat dan aktifkan Danarapi sebelum menyimpan perubahan.")
        }
    }

    private func finishQueuedMutation(success: String) async -> Bool {
        if network.isOnline { await syncOutbox() }
        toastMessage = pendingOutboxCount == 0 ? success : "Tersimpan di perangkat, belum tersinkron. Tinjau antrean di Pengaturan."
        return true
    }

    private func updateOfflineProjection() throws {
        guard mode == .authenticated else { return }
        outboxChanges = try offlineStore.allChanges(ownerID: ownerID)
        pendingOutboxCount = outboxChanges.count
        snapshot = try offlineStore.overlay(snapshot, ownerID: ownerID)
    }

    private func persistReview(_ item: ReviewItem, operation: () async throws -> Void) async -> Bool {
        let requestedOwner = ownerID
        let requestedMode = mode
        let saved = await mutate {
            try await operation()
            guard ownerID == requestedOwner, mode == requestedMode else {
                throw AppError.validation("Sesi akun berubah. Draft tersimpan pada akun sebelumnya.")
            }
            snapshot.reconcileAcknowledgedReview(item, replacingExisting: true)
            cacheAcknowledgedReview(item)
        }
        guard saved, ownerID == requestedOwner, mode == requestedMode else { return false }
        if snapshot.reconcileAcknowledgedReview(item) { cacheAcknowledgedReview(item) }
        return true
    }

    private func cacheAcknowledgedReview(_ item: ReviewItem) {
        guard mode == .authenticated else { return }
        do {
            var cached = try offlineStore.cachedSnapshot(ownerID: ownerID) ?? snapshot
            cached.reconcileAcknowledgedReview(item, replacingExisting: true)
            try offlineStore.cache(cached, ownerID: ownerID)
        }
        catch { present(error) }
    }

    private func mutate(success: String = "Tersimpan", operation: () async throws -> Void) async -> Bool {
        await run {
            try await operation()
            do {
                try await loadDashboard()
                toastMessage = success
            } catch {
                present(error)
                toastMessage = "Perubahan diterima. Muat ulang data; jangan ulangi operasi yang sama."
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func onlineMutation(_ operation: () async throws -> Void) async -> Bool {
        guard mode == .demo || network.isOnline else { present(AppError.validation("Perubahan ini memerlukan koneksi pada akun nyata.")); return false }
        return await mutate(operation: operation)
    }

    private func run(_ operation: () async throws -> Void) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do { try await operation(); return true }
        catch is CancellationError { return false }
        catch let error as URLError where error.code == .cancelled { return false }
        catch { present(error); return false }
    }

    private func loadDashboard() async throws {
        let requestedOwner = ownerID
        let requestedMode = mode
        let requestedRepository = repository
        dashboardLoadVersion += 1
        let requestedVersion = dashboardLoadVersion
        monthlyReportError = nil
        var value = try await requestedRepository.dashboard()
        guard ownerID == requestedOwner, mode == requestedMode, dashboardLoadVersion == requestedVersion else { return }
        let selectedTimezone = mode == .demo ? defaults.string(forKey: "financeTimezone") ?? "Asia/Jakarta" : value.timezone ?? "Asia/Jakarta"
        value.timezone = selectedTimezone
        adoptTimezone(selectedTimezone)
        value.syncedAt = mode == .authenticated ? .now : nil
        snapshot = value
        hasLoadedDashboard = true
        dashboardError = nil
        if mode == .authenticated {
            do {
                try offlineStore.cache(value, ownerID: ownerID)
                try updateOfflineProjection()
            } catch { present(error) }
        }
        let reportDate = Date.now
        let reportMonth = MonthPeriod.key(reportDate)
        do {
            let summary = try await requestedRepository.report(since: MonthPeriod.start(reportDate), until: MonthPeriod.end(reportDate))
            guard ownerID == requestedOwner, mode == requestedMode, dashboardLoadVersion == requestedVersion else { return }
            snapshot.monthlyReport = summary
            snapshot.reportMonth = reportMonth
            value.monthlyReport = summary
            value.reportMonth = reportMonth
            if mode == .authenticated {
                do { try offlineStore.cache(value, ownerID: ownerID) }
                catch { present(error) }
            }
        } catch {
            guard ownerID == requestedOwner, mode == requestedMode, dashboardLoadVersion == requestedVersion else { return }
            monthlyReportError = (error as? AppError)?.message ?? "Ringkasan bulan ini belum dimuat."
            if (error as? AppError)?.code == "UNAUTHORIZED" { present(error) }
        }
    }

    private func adoptTimezone(_ timezone: String?) {
        let value = timezone ?? "Asia/Jakarta"
        defaults.set(value, forKey: "financeTimezone")
        UserDefaults.standard.set(value, forKey: "financeTimezone")
    }

    private func present(_ error: Error) {
        if let appError = error as? AppError {
            if appError.code == "UNAUTHORIZED", mode == .authenticated { requiresReauthentication = true }
            errorMessage = appError.message
        }
        else if let urlError = error as? URLError { errorMessage = urlError.code == .notConnectedToInternet ? "Tidak ada koneksi internet." : "Jaringan bermasalah. Coba lagi." }
        else { errorMessage = "Terjadi kesalahan. Coba lagi." }
        if mode == .authenticated && !hasLoadedDashboard { dashboardError = errorMessage }
    }
}
