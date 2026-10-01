import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    var onAdd: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingGoal: SavingsGoal?
    @State private var progressGoal: SavingsGoal?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: DesignTokens.sectionGap) {
                    balanceCard
                    metrics
                    goals
                    budgets
                    unsettledBills
                    recentTransactions
                }
                .padding(DesignTokens.gutter)
                .padding(.bottom, 76)
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.title2.bold()).frame(width: 58, height: 58)
                        .foregroundStyle(Color.danarapiOnPrimary).background(Color.danarapiPrimary, in: Circle())
                        .shadow(color: Color.danarapiInk.opacity(0.12), radius: 14, y: 8)
                }.accessibilityLabel("Tambah catatan").padding(22)
            }
            .background(Color.danarapiCanvas)
            .navigationTitle("Ringkasan keuangan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { ReviewListView(embedded: true) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "tray").font(.system(size: 19))
                            if !app.snapshot.reviewItems.isEmpty { Text("\(app.snapshot.reviewItems.count)").font(.caption.weight(.semibold)) }
                        }.frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Tinjauan").accessibilityIdentifier("home.reviews")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.hideAmounts.toggle() } label: { Image(systemName: app.hideAmounts ? "eye.slash" : "eye") }.accessibilityLabel(app.hideAmounts ? "Tampilkan nominal" : "Sembunyikan nominal")
                }
            }
            .refreshable { await app.refresh() }
            .sheet(item: $editingGoal) { GoalEditorView(goal: $0) }
            .sheet(item: $progressGoal) { goal in NavigationStack { TransactionFormView(kind: .expense, initialGoal: goal) }.presentationDragIndicator(.visible) }
        }
    }

    private var balanceCard: some View {
        NavigationLink { AccountManagementView() } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Label("Saldo akun", systemImage: "wallet.pass"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)) }.font(.subheadline.weight(.semibold)).foregroundStyle(Color.danarapiMuted)
                MoneyText(amount: app.snapshot.overview.accountBalance, style: .largeTitle.bold())
                if let syncedAt = app.snapshot.syncedAt { Text("Diperbarui \(syncedAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(Color.danarapiMuted) }
            }.danarapiCard().contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerCard))
        }.buttonStyle(.plain).accessibilityIdentifier("home.accounts")
    }

    private var metrics: some View {
        LazyVGrid(columns: dynamicTypeSize >= .xxxLarge ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink { TransactionsView(initialKind: .income, currentMonth: true, embedded: true) } label: { metric("Pemasukan", app.monthlyReport.personalIncome, "arrow.down.left", .danarapiSurface, .danarapiPrimary) }.buttonStyle(.plain).accessibilityIdentifier("home.income")
            NavigationLink { TransactionsView(initialKind: .expense, currentMonth: true, embedded: true) } label: { metric("Pengeluaran", app.monthlyReport.personalExpense, "arrow.up.right", .danarapiSurface, .danarapiInk) }.buttonStyle(.plain).accessibilityIdentifier("home.expense")
            NavigationLink { GoalsView() } label: { metric("Target terkumpul", (app.snapshot.goals ?? []).reduce(0) { $0 + $1.savedAmount }, "target", .danarapiSky, .danarapiPrimary) }.buttonStyle(.plain).accessibilityIdentifier("home.goals")
            NavigationLink { BudgetListView() } label: { metric("Total anggaran bulan ini", currentBudgets.reduce(0) { $0 + $1.limitAmount }, "chart.pie", .danarapiSky, .danarapiPrimary) }.buttonStyle(.plain).accessibilityIdentifier("home.budgets")
        }
    }

    private func metric(_ title: String, _ amount: Int64, _ icon: String, _ background: Color, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: icon).foregroundStyle(color); Spacer(); Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.danarapiMuted) }
            Text(title).font(.caption).foregroundStyle(Color.danarapiMuted)
            MoneyText(amount: amount, style: .headline, color: color)
        }.frame(maxWidth: .infinity, alignment: .leading).danarapiCard(background)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerCard, style: .continuous))
    }

    private var budgets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Anggaran bulan ini").font(.title3.bold()); Spacer(); NavigationLink("Atur") { BudgetListView() }.font(.subheadline.bold()) }
            if currentBudgets.isEmpty { EmptyRow(icon: "chart.bar", text: "Belum ada anggaran."); NavigationLink("Buat anggaran") { BudgetListView() } }
            ForEach(currentBudgets) { budget in
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text(app.snapshot.categories.first(where: { $0.id == budget.categoryID })?.name ?? "Kategori"); Spacer(); Text("\(Int(budget.ratio * 100))%").font(.caption.weight(.semibold)) }
                    ProgressView(value: min(budget.ratio, 1)).tint(budget.progressColor)
                    HStack { MoneyText(amount: budget.spentAmount, style: .caption); Text("dari"); MoneyText(amount: budget.limitAmount, style: .caption) }.font(.caption).foregroundStyle(Color.danarapiMuted)
                }
            }
        }.danarapiCard()
    }

    private var currentBudgets: [Budget] { app.snapshot.budgets.filter { MonthPeriod.calendar.isDate($0.month, equalTo: .now, toGranularity: .month) } }
    private var goals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Target tabungan").font(.title3.bold()); Spacer(); NavigationLink("Atur") { GoalsView() }.font(.subheadline.bold()) }
            ForEach(app.snapshot.goals ?? []) { goal in GoalCard(goal: goal, onProgress: { progressGoal = goal }, onEdit: { editingGoal = goal }) }
            if (app.snapshot.goals ?? []).isEmpty { NavigationLink { GoalsView() } label: { Label("Buat target pertama", systemImage: "target").frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.danarapiSky, in: RoundedRectangle(cornerRadius: 20)) } }
        }
    }

    private var unsettledBills: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tagihan bersama").font(.title3.bold())
            let bills = app.snapshot.splitBills
            if bills.isEmpty { EmptyRow(icon: "person.3", text: "Belum ada tagihan bersama.") }
            ForEach(bills.prefix(3)) { bill in
                NavigationLink { SplitBillDetailView(billID: bill.id) } label: {
                    HStack { VStack(alignment: .leading) { Text(bill.title).font(.headline); Text("Bagian Saya").font(.caption).foregroundStyle(Color.danarapiMuted) }; Spacer(); MoneyText(amount: bill.selfShare, style: .subheadline.bold(), color: .danarapiPrimary) }
                }.buttonStyle(.plain)
            }
        }.danarapiCard(.danarapiLavender)
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transaksi terbaru").font(.title3.bold())
            if app.snapshot.transactions.isEmpty { EmptyRow(icon: "tray", text: "Belum ada transaksi. Catat yang pertama, yuk.") }
            ForEach(app.snapshot.transactions.prefix(5)) { item in TransactionRow(item: item) }
        }.danarapiCard()
    }
}

struct EmptyRow: View {
    let icon: String
    let text: String
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(Color.danarapiMuted); Text(text).font(.subheadline).foregroundStyle(Color.danarapiMuted) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
}
