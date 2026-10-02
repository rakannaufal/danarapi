import Charts
import SwiftUI

struct ReportsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var month = MonthPeriod.start(.now)
    @State private var editingBudget: Budget?
    @State private var newBudget = false
    @State private var report = ReportSummary.zero
    @State private var trends: [MonthlyReportTrend] = []
    @State private var yearly = false
    @State private var year = MonthPeriod.calendar.component(.year, from: .now)
    @State private var loading = true
    @State private var loadError: String?
    @State private var reportExport: URL?
    @State private var exportError: String?

    private var startDate: Date { yearly ? MonthPeriod.calendar.date(from: DateComponents(year: year, month: 1, day: 1))! : MonthPeriod.start(month) }
    private var endDate: Date { yearly ? MonthPeriod.calendar.date(byAdding: .year, value: 1, to: startDate)! : MonthPeriod.end(startDate) }
    private var reportKey: String { "\(startDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)-\(app.timezone)" }
    private var periodBudgets: [Budget] { app.snapshot.budgets.filter { $0.month >= startDate && $0.month < endDate } }
    private var reportBudgets: [Budget] {
        guard yearly else { return periodBudgets }
        return Dictionary(grouping: periodBudgets, by: \.categoryID).map { categoryID, rows in
            Budget(id: categoryID, categoryID: categoryID, month: startDate, limitAmount: rows.reduce(0) { $0 + $1.limitAmount }, spentAmount: rows.reduce(0) { $0 + $1.spentAmount })
        }.sorted { $0.categoryID < $1.categoryID }
    }

    private var allocationRows: [ReportAllocation] {
        if let allocations = report.allocations { return allocations }
        var remaining = Dictionary(uniqueKeysWithValues: report.categories.map { ($0.categoryID, $0.amount) })
        var goalAmounts: [String: Int64] = [:]
        for transaction in app.snapshot.transactions where !transaction.deleted && transaction.kind == .expense && transaction.occurredAt >= startDate && transaction.occurredAt < endDate {
            if let goalID = transaction.goalID {
                goalAmounts[goalID, default: 0] += transaction.amount
                remaining[transaction.categoryID, default: 0] -= transaction.amount
            }
        }
        let budgetIDs = Set(app.snapshot.budgets.filter { $0.month >= startDate && $0.month < endDate }.map(\.categoryID))
        var rows = goalAmounts.map { goalID, amount in ReportAllocation(id: "goal:\(goalID)", name: "Target · \(app.snapshot.goals?.first(where: { $0.id == goalID })?.name ?? "Target")", amount: amount) }
        rows += remaining.filter { $0.value > 0 }.map { categoryID, amount in
            let name = app.snapshot.categories.first(where: { $0.id == categoryID })?.name ?? "Kategori"
            return ReportAllocation(id: categoryID, name: budgetIDs.contains(categoryID) ? "Anggaran · \(name)" : name, amount: amount)
        }
        return rows.sorted { $0.amount == $1.amount ? $0.id < $1.id : $0.amount > $1.amount }
    }

    private var categoryRows: [CategorySpend] {
        report.categories.map { row in
            CategorySpend(id: row.categoryID, name: app.snapshot.categories.first(where: { $0.id == row.categoryID })?.name ?? "Kategori", amount: row.amount)
        }.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    Picker("Periode", selection: $yearly) { Text("Bulanan").tag(false); Text("Tahunan").tag(true) }.pickerStyle(.segmented)
                    if yearly {
                        HStack { Button { year -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Tahun sebelumnya"); Spacer(); Text(String(year)).font(.headline); Spacer(); Button { year += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Tahun berikutnya") }
                    } else { MonthPicker(month: $month) }
                    if loading { ProgressView("Memuat laporan…").frame(maxWidth: .infinity, minHeight: 160) }
                    else if let loadError { VStack(spacing: 14) { Text(loadError).font(.subheadline).foregroundStyle(.secondary); Button("Coba lagi") { Task { await loadReport() } }.buttonStyle(.bordered) }.frame(maxWidth: .infinity, minHeight: 160) }
                    else {
                    overview
                    ReportDonut(title: "Alokasi pengeluaran", rows: allocationRows)
                    ReportDonut(title: "Pemasukan & pengeluaran", rows: [ReportAllocation(id: "income", name: "Pemasukan", amount: report.personalIncome), ReportAllocation(id: "expense", name: "Pengeluaran", amount: report.personalExpense)])
                    comparisonChart
                    categoryChart
                    budgetSection
                    cashSection
                    Button("Ekspor laporan CSV", systemImage: "square.and.arrow.up") {
                        do { reportExport = try ExportService.createReportCSV(report, snapshot: app.snapshot, start: startDate, end: endDate); exportError = nil } catch { exportError = error.localizedDescription }
                    }.buttonStyle(.bordered)
                    if let reportExport { ShareLink(item: reportExport) { Label("Bagikan laporan", systemImage: "square.and.arrow.up") } }
                    if let exportError { Text(exportError).foregroundStyle(Color.danarapiExpense).font(.caption) }
                    cashExplanation
                    }
                }
                .padding(DesignTokens.gutter)
            }
            .background(Color.danarapiCanvas)
            .navigationTitle("Laporan")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await app.refresh(); await loadReport() }
            .task(id: reportKey) { await loadReport() }
            .onChange(of: reportKey) { _, _ in reportExport = nil; exportError = nil }
            .sheet(item: $editingBudget) { BudgetEditorView(budget: $0) }
            .sheet(isPresented: $newBudget) { BudgetEditorView(budget: nil, initialMonth: month) }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ringkasan").font(.title3.bold())
            (dynamicTypeSize >= .xxxLarge ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
                metric("Pemasukan", report.personalIncome, .danarapiIncome)
                Divider()
                metric("Pengeluaran", report.personalExpense, .danarapiExpense)
            }
            Divider()
            LabeledContent("Selisih periode") { MoneyText(amount: report.personalIncome - report.personalExpense, style: .headline) }
        }
        .danarapiCard(.danarapiMint)
    }

    private func metric(_ title: String, _ amount: Int64, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(Color.danarapiMuted)
            MoneyText(amount: amount, style: .title3.bold(), color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pengeluaran per kategori").font(.title3.bold())
            if categoryRows.isEmpty {
                EmptyRow(icon: "chart.bar", text: "Belum ada pengeluaran pada periode ini.")
            } else {
                Chart(categoryRows.prefix(7)) { row in
                    BarMark(x: .value("Nominal", row.amount), y: .value("Kategori", row.name))
                        .foregroundStyle(Color.danarapiPrimary)
                        .cornerRadius(5)
                        .annotation(position: .trailing) { Text(row.amount.idr).font(.caption2).foregroundStyle(Color.danarapiMuted) }
                }
                .frame(height: CGFloat(max(190, categoryRows.prefix(7).count * 46)))
                .chartXAxis(.hidden)
                .accessibilityLabel("Grafik pengeluaran per kategori")
                ForEach(categoryRows) { row in
                    HStack { Text(row.name); Spacer(); MoneyText(amount: row.amount, style: .subheadline.bold(), color: .danarapiExpense) }
                        .font(.subheadline)
                }
            }
        }
        .danarapiCard()
    }

    private var comparisonChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(yearly ? "Perbandingan tiga tahun" : "Perbandingan tiga bulan").font(.title3.bold())
            Chart(trends) { row in
                BarMark(x: .value("Bulan", row.name), y: .value("Nominal", row.income))
                    .foregroundStyle(by: .value("Jenis", "Pemasukan")).position(by: .value("Jenis", "Pemasukan"))
                BarMark(x: .value("Bulan", row.name), y: .value("Nominal", row.expense))
                    .foregroundStyle(by: .value("Jenis", "Pengeluaran")).position(by: .value("Jenis", "Pengeluaran"))
            }.chartForegroundStyleScale(["Pemasukan": Color.danarapiChartIncome, "Pengeluaran": Color.danarapiChartExpense])
                .chartYAxis(.hidden).frame(height: 190).accessibilityLabel(yearly ? "Perbandingan pemasukan dan pengeluaran tiga tahun" : "Perbandingan pemasukan dan pengeluaran tiga bulan")
                .accessibilityHidden(app.hideAmounts)
            ForEach(trends) { row in
                HStack { Text(row.name).font(.caption); Spacer(); MoneyText(amount: row.income, style: .caption, color: .danarapiIncome); MoneyText(amount: row.expense, style: .caption, color: .danarapiExpense) }
            }
        }.danarapiCard()
    }

    private var cashExplanation: some View {
        InformationDisclosure(title: "Tentang laporan", message: "Laporan memakai porsi Anda pada split bill. Arus kas memakai seluruh uang yang masuk dan keluar. Transfer dan pelunasan tidak dihitung dua kali. Saldo akun menggunakan posisi terkini, bukan saldo penutupan periode.")
            .danarapiCard()
    }

    private var cashSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Arus kas per akun").font(.title3.bold())
            if let rows = report.cashAccounts, !rows.isEmpty {
                ForEach(rows) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.snapshot.accounts.first(where: { $0.id == account.accountID })?.name ?? "Akun").font(.headline)
                        LabeledContent("Masuk") { MoneyText(amount: account.incoming, color: .danarapiIncome) }
                        LabeledContent("Keluar") { MoneyText(amount: account.outgoing, color: .danarapiExpense) }
                        LabeledContent("Arus bersih") { MoneyText(amount: account.net) }
                    }
                }
            } else { EmptyRow(icon: "wallet.bifold", text: "Belum ada arus kas pada periode ini.") }
        }.danarapiCard()
    }

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Anggaran").font(.title3.bold())
                Spacer()
                if !yearly { Button("Tambah") { newBudget = true } }
            }
            if reportBudgets.isEmpty { EmptyRow(icon: "gauge.with.dots.needle.33percent", text: "Belum ada anggaran periode ini.") }
            ForEach(reportBudgets) { budget in
                Button { if !yearly { editingBudget = budget } } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(app.snapshot.categories.first(where: { $0.id == budget.categoryID })?.name ?? "Kategori").font(.headline)
                            Spacer()
                            Text(budget.ratio > 1 ? "Melebihi batas" : budget.ratio >= 0.7 ? "Hampir penuh" : "Aman")
                                .font(.caption.weight(.semibold))
                        }
                        ProgressView(value: min(budget.ratio, 1)).tint(budget.progressColor)
                        Text("\(budget.spentAmount.idr) dari \(budget.limitAmount.idr) · \(Int(budget.ratio * 100))%")
                            .font(.caption).foregroundStyle(Color.danarapiMuted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(yearly)
                .accessibilityHint(yearly ? "Total anggaran tahunan" : "Ubah limit anggaran")
            }
        }
        .danarapiCard(.danarapiSun)
    }

    private func loadReport() async {
        let requestedKey = reportKey, requestedStart = startDate, requestedEnd = endDate, requestedYearly = yearly
        loading = true; loadError = nil
        defer { if reportKey == requestedKey { loading = false } }
        do {
            let value = try await app.reportResult(since: requestedStart, until: requestedEnd)
            try Task.checkCancellation()
            var collected: [MonthlyReportTrend] = []
            for offset in -2...0 {
                let component: Calendar.Component = requestedYearly ? .year : .month
                guard let date = MonthPeriod.calendar.date(byAdding: component, value: offset, to: requestedStart), let end = MonthPeriod.calendar.date(byAdding: component, value: 1, to: date) else { continue }
                let result = offset == 0 ? value : try await app.reportResult(since: date, until: end)
                try Task.checkCancellation()
                let formatter = DateFormatter(); formatter.timeZone = MonthPeriod.calendar.timeZone; formatter.locale = Locale(identifier: "id_ID"); formatter.dateFormat = requestedYearly ? "yyyy" : "MMM yy"
                collected.append(MonthlyReportTrend(id: MonthPeriod.key(date), name: formatter.string(from: date), income: result.personalIncome, expense: result.personalExpense))
            }
            guard reportKey == requestedKey else { return }
            report = value; trends = collected
        } catch is CancellationError { }
        catch { if reportKey == requestedKey { loadError = error.localizedDescription; trends = [] } }
    }
}

private struct MonthlyReportTrend: Identifiable {
    let id: String
    let name: String
    let income: Int64
    let expense: Int64
}

private struct ReportDonut: View {
    @Environment(AppModel.self) private var app
    let title: String
    let rows: [ReportAllocation]
    private var visible: [ReportAllocation] { rows.filter { $0.amount > 0 } }
    private let colors = Color.danarapiChartColors
    private func color(for row: ReportAllocation, index: Int) -> Color {
        if row.id == "income" { return .danarapiChartIncome }
        if row.id == "expense" { return .danarapiChartExpense }
        return colors[index % colors.count]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            if visible.isEmpty { EmptyRow(icon: "chart.pie", text: "Belum ada transaksi pada periode ini.") }
            else {
                Chart(visible) { row in
                    SectorMark(angle: .value("Nominal", row.amount), innerRadius: .ratio(0.7), angularInset: 1)
                        .foregroundStyle(by: .value("Alokasi", row.id))
                }.chartForegroundStyleScale(domain: visible.map(\.id), range: visible.enumerated().map { color(for: $0.element, index: $0.offset) })
                    .chartLegend(.hidden).frame(height: 220)
                    .accessibilityLabel("Diagram \(title)").accessibilityHidden(app.hideAmounts)
                    .chartBackground { _ in VStack(spacing: 4) { Text("Total").font(.caption).foregroundStyle(Color.danarapiMuted); MoneyText(amount: visible.reduce(0) { $0 + $1.amount }, style: .subheadline.bold()) } }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) { Circle().fill(color(for: row, index: index)).frame(width: 8, height: 8); Text(row.name).font(.subheadline); Spacer(); MoneyText(amount: row.amount, style: .subheadline.weight(.medium)) }
                }
            }
        }.danarapiCard()
    }
}

private struct CategorySpend: Identifiable {
    let id: String
    let name: String
    let amount: Int64
}

struct BudgetEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let budget: Budget?
    var initialMonth: Date = .now
    var onSaved: () -> Void = {}
    @State private var categoryID = ""
    @State private var limit = ""
    @State private var month = Date.now
    @State private var newCategory = ""
    @State private var saving = false
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            Form {
                if budget == nil {
                    Section("Kategori") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 8) {
                            ForEach(BudgetCategoryPresets.names, id: \.self) { name in
                                Button {
                                    if let existing = app.expenseCategories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { newCategory = ""; categoryID = existing.id }
                                    else { newCategory = name; categoryID = "" }
                                } label: { Text(name).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Color.danarapiSky, in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section {
                    Picker("Kategori", selection: $categoryID) { Text(newCategory.isEmpty ? "Pilih kategori" : newCategory).tag(""); ForEach(app.expenseCategories) { Text($0.name).tag($0.id) } }.disabled(budget != nil)
                    MonthPicker(month: $month)
                    MoneyField(title: "Limit bulanan", value: $limit, focus: $focusedField, focusID: "limit").listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if budget == nil {
                    Section("Kategori khusus") {
                        TextField("Nama kategori baru", text: $newCategory)
                            .focused($focusedField, equals: "category")
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .onChange(of: newCategory) { _, name in if name.nilIfBlank != nil { categoryID = "" } }
                        Button("Buat kategori dan pilih") {
                            Task {
                                guard let name = newCategory.nilIfBlank, await app.createCategory(name: name, kind: .expense) else { return }
                                if let category = app.expenseCategories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { categoryID = category.id; newCategory = "" }
                            }
                        }.disabled(newCategory.nilIfBlank == nil)
                    }
                }
                Section {
                    Button("Simpan anggaran") { Task { await save() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving || (app.mode == .authenticated && !app.network.isOnline) || (categoryID.isEmpty && newCategory.nilIfBlank == nil) || (Int64(limit) ?? 0) <= 0 || (Int64(limit) ?? Int64.max) > Money.maximum)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .navigationTitle(budget == nil ? "Tambah anggaran" : "Ubah anggaran")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
            .onAppear {
                categoryID = budget?.categoryID ?? app.expenseCategories.first?.id ?? ""
                limit = budget.map { String($0.limitAmount) } ?? ""
                month = budget?.month ?? initialMonth
            }
        }
    }
    private func save() async {
        guard !saving, let value = Int64(limit) else { return }; saving = true; defer { saving = false }
        if categoryID.isEmpty {
            guard let name = newCategory.nilIfBlank else { return }
            if let existing = app.expenseCategories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { categoryID = existing.id }
            else { guard await app.createCategory(name: name, kind: .expense), let category = app.expenseCategories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }; categoryID = category.id }
        }
        if await app.upsertBudget(categoryID: categoryID, month: month, limit: value) { onSaved(); dismiss() }
    }
}

struct MonthPicker: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { month = MonthPeriod.calendar.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Bulan sebelumnya")
            Spacer()
            Text(MonthPeriod.display(month, template: "MMMM yyyy")).font(.headline)
            Spacer()
            Button { month = MonthPeriod.calendar.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Bulan berikutnya")
        }.foregroundStyle(Color.danarapiPrimary).padding(6).background(Color.danarapiSky, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct BudgetListView: View {
    @Environment(AppModel.self) private var app
    @State private var month = MonthPeriod.start(.now)
    @State private var editing: Budget?
    @State private var adding = false
    @State private var confirmCopy = false
    private var rows: [Budget] { app.snapshot.budgets.filter { MonthPeriod.calendar.isDate($0.month, equalTo: month, toGranularity: .month) } }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MonthPicker(month: $month)
                VStack(alignment: .leading, spacing: 8) { Text("Total anggaran").font(.subheadline); MoneyText(amount: rows.reduce(0) { $0 + $1.limitAmount }, style: .title.bold()); Text("Limit per kategori, bukan uang yang dipindahkan.").font(.caption).foregroundStyle(Color.danarapiMuted) }.frame(maxWidth: .infinity, alignment: .leading).danarapiCard(.danarapiSky)
                ForEach(rows) { budget in
                    NavigationLink { BudgetDetailView(budgetID: budget.id) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.snapshot.categories.first(where: { $0.id == budget.categoryID })?.name ?? "Kategori").font(.headline)
                            ProgressView(value: min(budget.ratio, 1)).tint(budget.progressColor)
                            HStack { MoneyText(amount: budget.spentAmount, style: .subheadline); Text("dari"); MoneyText(amount: budget.limitAmount, style: .subheadline) }
                        }.foregroundStyle(Color.danarapiInk).frame(maxWidth: .infinity, alignment: .leading).danarapiCard()
                    }.buttonStyle(.plain)
                }
                if rows.isEmpty { EmptyRow(icon: "chart.pie", text: "Belum ada anggaran bulan ini.") }
                if !rows.isEmpty { Button("Salin ke bulan berikutnya") { confirmCopy = true }.buttonStyle(.bordered) }
                Button("Tambah anggaran", systemImage: "plus") { adding = true }.buttonStyle(PrimaryButtonStyle())
            }.padding(DesignTokens.gutter)
        }.background(Color.danarapiCanvas).navigationTitle("Anggaran").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { BudgetEditorView(budget: nil, initialMonth: month) }
        .sheet(item: $editing) { BudgetEditorView(budget: $0) }
        .confirmationDialog("Salin limit ke bulan berikutnya? Anggaran yang sudah ada tidak ditimpa. Saldo tidak berubah.", isPresented: $confirmCopy, titleVisibility: .visible) { Button("Salin anggaran") { Task { if let next = MonthPeriod.calendar.date(byAdding: .month, value: 1, to: month), await app.copyBudgets(from: month, to: next) { month = next } } } }
    }
}

struct BudgetDetailView: View {
    @Environment(AppModel.self) private var app
    let budgetID: String
    @State private var editing = false
    private var budget: Budget? { app.snapshot.budgets.first { $0.id == budgetID } }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let budget {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(MonthPeriod.display(budget.month, template: "MMMM yyyy")).font(.subheadline).foregroundStyle(.secondary)
                        HStack { MoneyText(amount: budget.spentAmount, style: .title2.bold()); Text("dari").foregroundStyle(.secondary); MoneyText(amount: budget.limitAmount, style: .subheadline) }
                        ProgressView(value: min(budget.ratio, 1)).tint(budget.progressColor)
                        Text(budget.status == "over" ? "Melebihi batas" : budget.status == "warning" ? "Hampir penuh" : "Aman").font(.subheadline.bold())
                        Button("Ubah limit") { editing = true }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, alignment: .leading).danarapiCard()
                    PlanningHistoryView(request: PlanningHistoryRequest(categoryID: budget.categoryID, startDate: MonthPeriod.start(budget.month), endDate: MonthPeriod.end(budget.month)))
                } else { ContentUnavailableView("Anggaran tidak tersedia", systemImage: "chart.pie") }
            }.padding(DesignTokens.gutter)
        }.background(Color.danarapiCanvas).navigationTitle(budget.flatMap { value in app.snapshot.categories.first { $0.id == value.categoryID }?.name } ?? "Anggaran").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { if let budget { BudgetEditorView(budget: budget) } }
    }
}
