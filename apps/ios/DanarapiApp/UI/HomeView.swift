import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    var onAdd: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingGoal: SavingsGoal?
    @State private var progressGoal: SavingsGoal?
    @State private var addingIncome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: DesignTokens.sectionGap) {
                    balanceCard
                    metrics
                    goals
                    recentTransactions
                    budgets
                    unsettledBills
                }
                .padding(DesignTokens.gutter)
                .padding(.bottom, 76)
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.title2.bold()).frame(width: 58, height: 58)
                        .foregroundStyle(Color.danarapiOnPrimary).background(Color.danarapiPrimary, in: Circle())
                        .shadow(color: Color.danarapiPrimary.opacity(0.2), radius: 14, y: 8)
                }.accessibilityLabel("Tambah catatan").padding(22)
            }
            .background(Color.danarapiCanvas)
            .danarapiMainHeader()
            .refreshable { await app.refresh() }
            .sheet(isPresented: $addingIncome) { TransactionFormView(kind: .income) { addingIncome = false } }
            .sheet(item: $editingGoal) { GoalEditorView(goal: $0) }
            .sheet(item: $progressGoal) { goal in NavigationStack { TransactionFormView(kind: .expense, initialGoal: goal) }.presentationDragIndicator(.visible) }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("Saldo akun", systemImage: AppSymbol.wallet.rawValue)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
                Button { app.hideAmounts.toggle() } label: {
                    Image(systemName: app.hideAmounts ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44).background(.white.opacity(0.14), in: Circle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(app.hideAmounts ? "Tampilkan nominal" : "Sembunyikan nominal")
            }
            NavigationLink { AccountManagementView() } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        MoneyText(amount: app.snapshot.overview.accountBalance, style: .largeTitle.bold(), color: .danarapiOnBalance)
                        Text("\(app.activeAccounts.count) akun aktif")
                            .font(.caption.weight(.medium)).foregroundStyle(Color.danarapiOnBalance.opacity(0.85))
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44).background(.white.opacity(0.14), in: Circle())
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("home.accounts")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { reviewAction; incomeAction }
                VStack(spacing: 12) { reviewAction; incomeAction }
            }
        }
        .foregroundStyle(Color.danarapiOnBalance)
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.cornerCard + 4, style: .continuous)
                .fill(LinearGradient(colors: [.danarapiBalanceStart, .danarapiBalanceEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.cornerCard + 4, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.13), .clear], center: .topTrailing, startRadius: 0, endRadius: 300))
                }
        }
        .shadow(color: Color.danarapiPrimary.opacity(0.18), radius: 16, y: 8)
    }

    private var reviewAction: some View {
        NavigationLink { ReviewListView(embedded: true) } label: {
            HStack(spacing: 8) {
                Image(systemName: AppSymbol.receipt.rawValue)
                Text("Tinjau")
                if app.snapshot.reviewItems.count + app.sharedProofCount > 0 {
                    Text("\(app.snapshot.reviewItems.count + app.sharedProofCount)").font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(Color.danarapiBalanceEnd).background(Color.danarapiOnBalance, in: Capsule())
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 12)
            .background(.white.opacity(0.1), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.25), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel("Tinjauan").accessibilityIdentifier("home.reviews")
    }

    private var incomeAction: some View {
        Button { addingIncome = true } label: {
            Label("Tambah saldo", systemImage: "plus.circle")
                .font(.footnote.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 50)
                .padding(.horizontal, 12)
                .foregroundStyle(Color.danarapiBalanceStart)
                .background(Color.danarapiOnBalance, in: Capsule())
        }.buttonStyle(.plain)
    }

    private var metrics: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: dynamicTypeSize >= .xxxLarge ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink { TransactionsView(initialKind: .income, currentMonth: true, embedded: true) } label: { metric("Pemasukan", app.monthlyReport?.personalIncome, AppSymbol.income.rawValue, .danarapiSurface, .danarapiPrimary) }.buttonStyle(.plain).accessibilityIdentifier("home.income")
                NavigationLink { TransactionsView(initialKind: .expense, currentMonth: true, embedded: true) } label: { metric("Pengeluaran", app.monthlyReport?.personalExpense, AppSymbol.expense.rawValue, .danarapiSurface, .danarapiInk) }.buttonStyle(.plain).accessibilityIdentifier("home.expense")
                NavigationLink { GoalsView() } label: { metric("Target terkumpul", (app.snapshot.goals ?? []).reduce(0) { $0 + $1.savedAmount }, AppSymbol.goal.rawValue, .danarapiSurface, .danarapiPrimary) }.buttonStyle(.plain).accessibilityIdentifier("home.goals")
                NavigationLink { BudgetListView() } label: { metric("Total anggaran", currentBudgets.reduce(0) { $0 + $1.limitAmount }, AppSymbol.budget.rawValue, .danarapiSurface, .danarapiInk) }.buttonStyle(.plain).accessibilityIdentifier("home.budgets")
            }
            if app.monthlyReportError != nil {
                Button("Muat ringkasan", systemImage: "arrow.clockwise") { Task { await app.refresh() } }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: DesignTokens.minimumTouch)
                    .accessibilityIdentifier("home.retryReport")
            }
        }
    }

    private func metric(_ title: String, _ amount: Int64?, _ icon: String, _ background: Color, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SymbolBadge(symbol: icon,
                    color: icon == AppSymbol.expense.rawValue || icon == AppSymbol.budget.rawValue ? .danarapiChartExpense : .danarapiPrimary,
                    background: icon == AppSymbol.expense.rawValue || icon == AppSymbol.budget.rawValue ? .danarapiPeach : .danarapiMint,
                    size: 42)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.danarapiMuted.opacity(0.6))
            }
            Text(title).font(.subheadline).foregroundStyle(Color.danarapiMuted).padding(.top, 6)
            if let amount { MoneyText(amount: amount, style: .headline, color: color) }
            else { Text("—").font(.headline).foregroundStyle(Color.danarapiMuted).accessibilityLabel("Belum dimuat") }
        }.frame(maxWidth: .infinity, alignment: .leading).danarapiCard(background)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerCard, style: .continuous))
    }

    private var budgets: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Anggaran bulan ini").font(.title3.bold()); Spacer(); NavigationLink("Atur") { BudgetListView() }.font(.subheadline.bold()) }
            if currentBudgets.isEmpty { EmptyRow(icon: AppSymbol.reports.rawValue, text: "Belum ada anggaran."); NavigationLink("Buat anggaran") { BudgetListView() } }
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
            if (app.snapshot.goals ?? []).isEmpty { NavigationLink { GoalsView() } label: { Label("Buat target pertama", systemImage: AppSymbol.goal.rawValue).frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.danarapiSky, in: RoundedRectangle(cornerRadius: 20)) } }
        }
    }

    private var unsettledBills: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tagihan bersama").font(.title3.bold())
            let bills = app.snapshot.splitBills
            if bills.isEmpty { EmptyRow(icon: AppSymbol.split.rawValue, text: "Belum ada tagihan bersama.") }
            ForEach(bills.prefix(3)) { bill in
                NavigationLink { SplitBillDetailView(billID: bill.id) } label: {
                    HStack { VStack(alignment: .leading) { Text(bill.title).font(.headline); Text("Bagian Saya").font(.caption).foregroundStyle(Color.danarapiMuted) }; Spacer(); MoneyText(amount: bill.selfShare, style: .subheadline.bold(), color: .danarapiPrimary) }
                }.buttonStyle(.plain)
            }
        }.danarapiCard(.danarapiLavender)
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transaksi terbaru").font(.title3.bold())
                Spacer()
                NavigationLink { TransactionsView(embedded: true) } label: { Text("Lihat semua").font(.subheadline.weight(.semibold)) }
            }
            VStack(spacing: 0) {
                if app.snapshot.transactions.isEmpty { EmptyRow(icon: "tray", text: "Belum ada transaksi. Catat yang pertama, yuk.") }
                ForEach(Array(app.snapshot.transactions.prefix(5).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.vertical, 12) }
                    NavigationLink { TransactionDetailView(itemID: item.id) } label: { TransactionRow(item: item) }.buttonStyle(.plain)
                }
            }.danarapiCard()
        }
    }
}

struct EmptyRow: View {
    let icon: String
    let text: String
    var body: some View { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(Color.danarapiMuted); Text(text).font(.subheadline).foregroundStyle(Color.danarapiMuted) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
}
