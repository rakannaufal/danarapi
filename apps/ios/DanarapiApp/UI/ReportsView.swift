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

    private var startDate: Date { MonthPeriod.start(month) }

    private var allocationRows: [ReportAllocation] {
        if let allocations = report.allocations { return allocations }
        var remaining = Dictionary(uniqueKeysWithValues: report.categories.map { ($0.categoryID, $0.amount) })
        var goalAmounts: [String: Int64] = [:]
        for transaction in app.snapshot.transactions where !transaction.deleted && transaction.kind == .expense && transaction.occurredAt >= startDate && transaction.occurredAt < MonthPeriod.end(startDate) {
            if let goalID = transaction.goalID {
                goalAmounts[goalID, default: 0] += transaction.amount
                remaining[transaction.categoryID, default: 0] -= transaction.amount
            }
        }
        let budgetIDs = Set(app.snapshot.budgets.filter { MonthPeriod.calendar.isDate($0.month, equalTo: month, toGranularity: .month) }.map(\.categoryID))
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
                    MonthPicker(month: $month)
                    overview
                    ReportDonut(title: "Alokasi pengeluaran", rows: allocationRows)
                    ReportDonut(title: "Pemasukan & pengeluaran", rows: [ReportAllocation(id: "income", name: "Pemasukan", amount: report.personalIncome), ReportAllocation(id: "expense", name: "Pengeluaran", amount: report.personalExpense)])
                    comparisonChart
                    categoryChart
                    budgetSection
                    cashExplanation
                }
                .padding(DesignTokens.gutter)
            }
            .background(Color.danarapiCanvas)
            .navigationTitle("Laporan")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await app.refresh(); await loadReport() }
            .task(id: startDate) { report = .zero; await loadReport() }
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
            Text("Perbandingan tiga bulan").font(.title3.bold())
            Chart(trends) { row in
                BarMark(x: .value("Bulan", row.name), y: .value("Nominal", row.income))
                    .foregroundStyle(by: .value("Jenis", "Pemasukan")).position(by: .value("Jenis", "Pemasukan"))
                BarMark(x: .value("Bulan", row.name), y: .value("Nominal", row.expense))
                    .foregroundStyle(by: .value("Jenis", "Pengeluaran")).position(by: .value("Jenis", "Pengeluaran"))
            }.chartForegroundStyleScale(["Pemasukan": Color.danarapiIncome, "Pengeluaran": Color.danarapiExpense])
                .chartYAxis(.hidden).frame(height: 190).accessibilityLabel("Perbandingan pemasukan dan pengeluaran tiga bulan")
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

    private var budgetSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Anggaran").font(.title3.bold())
                Spacer()
                Button("Tambah") { newBudget = true }
            }
            if app.snapshot.budgets.isEmpty { EmptyRow(icon: "gauge.with.dots.needle.33percent", text: "Belum ada anggaran bulanan.") }
            ForEach(app.snapshot.budgets.filter { MonthPeriod.calendar.isDate($0.month, equalTo: month, toGranularity: .month) }) { budget in
                Button { editingBudget = budget } label: {
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
                .accessibilityHint("Ubah limit anggaran")
            }
        }
        .danarapiCard(.danarapiSun)
    }

    private func loadReport() async {
        let requested = startDate
        guard let value = await app.report(since: requested, until: MonthPeriod.end(requested)), !Task.isCancelled, startDate == requested else { return }
        report = value
        var collected: [MonthlyReportTrend] = []
        for offset in -2...0 {
            guard let date = MonthPeriod.calendar.date(byAdding: .month, value: offset, to: requested) else { continue }
            let result: ReportSummary?
            if offset == 0 { result = value } else { result = await app.report(since: date, until: MonthPeriod.end(date)) }
            guard !Task.isCancelled, startDate == requested else { return }
            if let result { collected.append(MonthlyReportTrend(id: MonthPeriod.key(date), name: date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "id_ID"))), income: result.personalIncome, expense: result.personalExpense)) }
        }
        trends = collected
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
    private let colors: [Color] = [.danarapiPrimary, .danarapiIncome, Color(light: 0x9471B4, dark: 0xB99AD9), Color(light: 0xC49A22, dark: 0xFFD60A), .danarapiExpense, .gray]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            if visible.isEmpty { EmptyRow(icon: "chart.pie", text: "Belum ada transaksi pada periode ini.") }
            else {
                Chart(visible) { row in
                    SectorMark(angle: .value("Nominal", row.amount), innerRadius: .ratio(0.7), angularInset: 1)
                        .foregroundStyle(by: .value("Alokasi", row.id))
                }.chartForegroundStyleScale(domain: visible.map(\.id), range: visible.indices.map { colors[$0 % colors.count] })
                    .chartLegend(.hidden).frame(height: 220)
                    .accessibilityLabel("Diagram \(title)").accessibilityHidden(app.hideAmounts)
                    .chartBackground { _ in VStack(spacing: 4) { Text("Total").font(.caption).foregroundStyle(Color.danarapiMuted); MoneyText(amount: visible.reduce(0) { $0 + $1.amount }, style: .subheadline.bold()) } }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) { Circle().fill(colors[index % colors.count]).frame(width: 8, height: 8); Text(row.name).font(.subheadline); Spacer(); MoneyText(amount: row.amount, style: .subheadline.weight(.medium)) }
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
                    MoneyField(title: "Limit bulanan", value: $limit).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if budget == nil {
                    Section("Kategori khusus") {
                        TextField("Nama kategori baru", text: $newCategory).onChange(of: newCategory) { _, name in if name.nilIfBlank != nil { categoryID = "" } }
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
            Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "id_ID")))).font(.headline)
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
    private var rows: [Budget] { app.snapshot.budgets.filter { MonthPeriod.calendar.isDate($0.month, equalTo: month, toGranularity: .month) } }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                MonthPicker(month: $month)
                VStack(alignment: .leading, spacing: 8) { Text("Total anggaran").font(.subheadline); MoneyText(amount: rows.reduce(0) { $0 + $1.limitAmount }, style: .title.bold()); Text("Limit per kategori, bukan uang yang dipindahkan.").font(.caption).foregroundStyle(Color.danarapiMuted) }.frame(maxWidth: .infinity, alignment: .leading).danarapiCard(.danarapiSky)
                ForEach(rows) { budget in
                    Button { editing = budget } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.snapshot.categories.first(where: { $0.id == budget.categoryID })?.name ?? "Kategori").font(.headline)
                            ProgressView(value: min(budget.ratio, 1)).tint(budget.progressColor)
                            HStack { MoneyText(amount: budget.spentAmount, style: .subheadline); Text("dari"); MoneyText(amount: budget.limitAmount, style: .subheadline) }
                        }.foregroundStyle(Color.danarapiInk).frame(maxWidth: .infinity, alignment: .leading).danarapiCard()
                    }.buttonStyle(.plain)
                }
                if rows.isEmpty { EmptyRow(icon: "chart.pie", text: "Belum ada anggaran bulan ini.") }
                Button("Tambah anggaran", systemImage: "plus") { adding = true }.buttonStyle(PrimaryButtonStyle())
            }.padding(DesignTokens.gutter)
        }.background(Color.danarapiCanvas).navigationTitle("Anggaran").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { BudgetEditorView(budget: nil, initialMonth: month) }
        .sheet(item: $editing) { BudgetEditorView(budget: $0) }
    }
}
