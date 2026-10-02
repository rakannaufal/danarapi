import SwiftUI

private enum HistoryKind: String, CaseIterable, Identifiable {
    case all = "Semua"
    case income = "Pemasukan"
    case expense = "Pengeluaran"
    case transfer = "Transfer"
    case split = "Split bill"
    var id: String { rawValue }
}

private enum HistoryPeriod: String, CaseIterable, Identifiable {
    case all = "Semua tanggal"
    case thisMonth = "Bulan ini"
    case last30Days = "30 hari"
    var id: String { rawValue }
}

struct TransactionsView: View {
    @Environment(AppModel.self) private var app
    private let embedded: Bool
    private let currentMonth: Bool
    @State private var query = ""
    @State private var filtersOpen = false
    @State private var showTransfer = false
    @State private var kind: HistoryKind = .all
    @State private var period: HistoryPeriod = .all
    @State private var accountID = ""
    @State private var categoryID = ""

    init(initialKind: TransactionKind? = nil, currentMonth: Bool = false, embedded: Bool = false) {
        self.embedded = embedded
        self.currentMonth = currentMonth
        _kind = State(initialValue: initialKind == .income ? .income : initialKind == .expense ? .expense : .all)
        _period = State(initialValue: currentMonth ? .thisMonth : .all)
    }

    private var filtered: [FinanceTransaction] {
        app.snapshot.transactions.filter { item in
            ((kind == .all) || (kind == .income && item.kind == .income) || (kind == .expense && item.kind == .expense))
                && (accountID.isEmpty || item.accountID == accountID)
                && (categoryID.isEmpty || item.categoryID == categoryID)
                && matchesPeriod(item.occurredAt)
                && (query.isEmpty || (item.merchant ?? "").localizedCaseInsensitiveContains(query) || (item.note ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    private var filteredTransfers: [TransferRecord] {
        app.snapshot.transfers.filter { item in
            (kind == .all || kind == .transfer)
                && (accountID.isEmpty || item.fromAccountID == accountID || item.toAccountID == accountID)
                && matchesPeriod(item.occurredAt)
                && (query.isEmpty || (item.note ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    private var filteredBills: [SplitBill] {
        app.snapshot.splitBills.filter { bill in
            (kind == .all || kind == .split || kind == .expense)
                && (accountID.isEmpty || splitUsesAccount(bill, accountID: accountID))
                && (categoryID.isEmpty || bill.categoryID == categoryID)
                && matchesPeriod(bill.occurredAt)
                && (query.isEmpty || bill.title.localizedCaseInsensitiveContains(query) || (bill.note ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        Group {
            if embedded { transactionContent }
            else { NavigationStack { transactionContent } }
        }
    }

    private var transactionContent: some View {
            List {
                Section {
                    DisclosureGroup(kind == .all && period == .all ? "Filter" : "\(kind.rawValue) · \(period.rawValue)", isExpanded: $filtersOpen) {
                        Picker("Jenis", selection: $kind) { ForEach(HistoryKind.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Tanggal", selection: $period) { ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Akun", selection: $accountID) {
                            Text("Semua akun").tag("")
                            ForEach(app.activeAccounts) { Text($0.name).tag($0.id) }
                        }
                        Picker("Kategori", selection: $categoryID) {
                            Text("Semua kategori").tag("")
                            ForEach(app.snapshot.categories) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                if filtered.isEmpty && filteredTransfers.isEmpty && filteredBills.isEmpty { EmptyRow(icon: "magnifyingglass", text: "Tidak ada transaksi yang cocok.") }
                if !filtered.isEmpty {
                    Section("Pemasukan dan pengeluaran") {
                        ForEach(filtered) { item in NavigationLink { TransactionDetailView(itemID: item.id) } label: { TransactionRow(item: item) } }
                    }
                }
                if categoryID.isEmpty && !filteredTransfers.isEmpty {
                    Section("Transfer") {
                        ForEach(filteredTransfers) { item in NavigationLink { TransferDetailView(itemID: item.id) } label: { TransferRow(item: item) } }
                    }
                }
                if !filteredBills.isEmpty {
                    Section("Split bill") {
                        ForEach(filteredBills) { bill in
                            NavigationLink { SplitBillDetailView(billID: bill.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.3.fill").frame(width: 40, height: 40).background(Color.danarapiPeach, in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(bill.title).font(.headline)
                                        Text("Bagian saya \(bill.selfShare.idr) · \(bill.status.title)").font(.caption).foregroundStyle(Color.danarapiMuted)
                                    }
                                    Spacer(); MoneyText(amount: kind == .expense ? bill.selfShare : bill.total, style: .subheadline.bold())
                                }.frame(minHeight: 48)
                            }
                        }
                    }
                }
                if app.snapshot.nextTransactionCursor != nil {
                    Section {
                        Button { Task { await app.loadMoreTransactions() } } label: {
                            HStack { Spacer(); if app.isLoadingMoreTransactions { ProgressView() } else { Text("Muat 30 berikutnya") }; Spacer() }
                        }.disabled(app.isLoadingMoreTransactions)
                        Text("Filter berlaku pada data yang sudah dimuat.").font(.caption).foregroundStyle(Color.danarapiMuted)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(kind == .income ? "Pemasukan" : kind == .expense ? "Pengeluaran" : "Transaksi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Transfer", systemImage: "arrow.left.arrow.right") { showTransfer = true } } }
            .sheet(isPresented: $showTransfer) { NavigationStack { TransferFormView { showTransfer = false } } }
            .searchable(text: $query, prompt: "Cari merchant atau catatan")
            .refreshable { await app.refresh() }
            .task {
                guard currentMonth else { return }
                while let cursor = app.snapshot.nextTransactionCursor, cursor.occurredAt >= MonthPeriod.start(.now), !Task.isCancelled {
                    await app.loadMoreTransactions()
                    if app.snapshot.nextTransactionCursor?.id == cursor.id { break }
                }
            }
    }

    private func matchesPeriod(_ date: Date) -> Bool {
        return switch period {
        case .all: true
        case .thisMonth: MonthPeriod.calendar.isDate(date, equalTo: .now, toGranularity: .month)
        case .last30Days: date >= Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        }
    }

    private func splitUsesAccount(_ bill: SplitBill, accountID: String) -> Bool {
        if case let .selfPaid(payerAccountID) = bill.payer, payerAccountID == accountID { return true }
        return bill.settlements.contains { !$0.reversed && $0.accountID == accountID }
    }
}

private struct TransferRow: View {
    @Environment(AppModel.self) private var app
    let item: TransferRecord
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right").frame(width: 40, height: 40).background(Color.danarapiSky, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(account(item.fromAccountID)) ke \(account(item.toAccountID))").font(.headline)
                HStack { Text(MonthPeriod.display(item.occurredAt)); if item.pendingSync { Text("Belum tersinkron") } }.font(.caption).foregroundStyle(Color.danarapiMuted)
            }
            Spacer(); MoneyText(amount: item.amount, style: .subheadline.bold())
        }.frame(minHeight: 48)
    }
    private func account(_ id: String) -> String { app.snapshot.accounts.first(where: { $0.id == id })?.name ?? "Akun" }
}

private struct TransferDetailView: View {
    @Environment(AppModel.self) private var app
    let itemID: String
    @State private var edit = false
    private var item: TransferRecord? { app.snapshot.transfers.first(where: { $0.id == itemID }) }
    var body: some View {
        Group {
            if let item {
                List {
                    Section { LabeledContent("Nominal") { MoneyText(amount: item.amount, style: .title3.bold()) }; LabeledContent("Dari", value: account(item.fromAccountID)); LabeledContent("Ke", value: account(item.toAccountID)); LabeledContent("Tanggal", value: MonthPeriod.display(item.occurredAt, template: "d MMMM yyyy HHmm")) }
                    Section { LabeledContent("Catatan", value: item.note ?? "—") }
                    Section { Button("Ubah transfer") { edit = true }; Button("Hapus transfer", role: .destructive) { Task { _ = await app.deleteTransfer(item) } } }
                }
                .navigationTitle("Detail transfer")
                .sheet(isPresented: $edit) { NavigationStack { TransferFormView(editing: item) { edit = false } } }
            } else { ContentUnavailableView("Transfer tidak tersedia", systemImage: "arrow.left.arrow.right") }
        }
    }
    private func account(_ id: String) -> String { app.snapshot.accounts.first(where: { $0.id == id })?.name ?? "Akun" }
}

struct TransactionRow: View {
    @Environment(AppModel.self) private var app
    let item: FinanceTransaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .income ? "arrow.down.left" : "arrow.up.right")
                .frame(width: 40, height: 40).background(item.kind == .income ? Color.danarapiMint : Color.danarapiPeach, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.goalID.flatMap { identifier in app.snapshot.goals?.first { $0.id == identifier }?.name } ?? item.merchant ?? app.snapshot.categories.first(where: { $0.id == item.categoryID })?.name ?? item.kind.title).font(.headline).lineLimit(1)
                HStack { Text(MonthPeriod.display(item.occurredAt)); if item.pendingSync { Label("Belum tersinkron", systemImage: "clock.arrow.circlepath") } }.font(.caption).foregroundStyle(Color.danarapiMuted)
            }
            Spacer()
            MoneyText(amount: item.amount, style: .subheadline.bold(), color: item.kind == .income ? .danarapiIncome : .danarapiExpense)
        }.frame(minHeight: 48)
    }
}

struct TransactionDetailView: View {
    @Environment(AppModel.self) private var app
    let itemID: String
    @State private var edit = false
    @State private var convertToSplit = false
    @State private var deletedItem: FinanceTransaction?
    @State private var loading = true
    @State private var loadError: String?

    var item: FinanceTransaction? { app.snapshot.transactions.first(where: { $0.id == itemID }) }

    var body: some View {
        Group {
            if let item {
                List {
                    Section { LabeledContent("Nominal") { MoneyText(amount: item.amount, style: .title3.bold()) }; LabeledContent("Jenis", value: item.kind.title); LabeledContent("Tanggal", value: MonthPeriod.display(item.occurredAt, template: "d MMMM yyyy HHmm")) }
                    Section { LabeledContent("Merchant", value: item.merchant ?? "—"); LabeledContent("Catatan", value: item.note ?? "—") }
                    if let goalID = item.goalID, let goal = app.snapshot.goals?.first(where: { $0.id == goalID }) {
                        Section { LabeledContent("Target", value: goal.name) }
                    }
                    Section {
                        Button("Ubah transaksi") { edit = true }
                        if item.kind == .expense && item.goalID == nil { Button("Jadikan split bill") { convertToSplit = true } }
                        Button("Hapus transaksi", role: .destructive) { Task { deletedItem = item; _ = await app.deleteTransaction(item) } }
                    }
                }
                .navigationTitle("Detail transaksi")
                .sheet(isPresented: $edit) { TransactionFormView(kind: item.kind, editing: item) { edit = false } }
                .sheet(isPresented: $convertToSplit) { NavigationStack { SplitBillFormView(convertingTransaction: item) { convertToSplit = false } } }
            } else if loading { ProgressView("Memuat transaksi…") }
            else { ContentUnavailableView { Label("Transaksi tidak tersedia", systemImage: "tray") } description: { Text(loadError ?? "Catatan sudah dihapus.") } actions: { Button("Coba lagi") { Task { await load() } } } }
        }
        .safeAreaInset(edge: .bottom) {
            if let deletedItem { HStack { Text("Transaksi dihapus"); Spacer(); Button("Urungkan") { Task { _ = await app.restoreTransaction(deletedItem); self.deletedItem = nil } } }.padding().background(.regularMaterial).task { try? await Task.sleep(for: .seconds(10)); self.deletedItem = nil } }
        }
        .task(id: itemID) { await load() }
    }
    private func load() async {
        loading = true; loadError = nil; defer { loading = false }
        do { try await app.ensureTransaction(id: itemID) } catch { loadError = error.localizedDescription }
    }
}
