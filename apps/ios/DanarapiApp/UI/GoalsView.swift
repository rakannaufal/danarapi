import SwiftUI

struct GoalsView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: SavingsGoal?
    @State private var adding = false
    @State private var progressGoal: SavingsGoal?
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(app.snapshot.goals ?? []) { goal in
                    GoalCard(goal: goal, onProgress: { progressGoal = goal }, onEdit: { editing = goal })
                    NavigationLink("Lihat rincian", destination: GoalDetailView(goalID: goal.id)).font(.subheadline).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if (app.snapshot.goals ?? []).isEmpty { EmptyRow(icon: "target", text: "Apa yang ingin Anda capai atau beli?") }
                Button("Tambah target", systemImage: "plus") { adding = true }.buttonStyle(PrimaryButtonStyle())
            }.padding(DesignTokens.gutter)
        }
        .background(Color.danarapiCanvas).navigationTitle("Target").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) { GoalEditorView(goal: nil) }
        .sheet(item: $editing) { GoalEditorView(goal: $0) }
        .sheet(item: $progressGoal) { goal in NavigationStack { TransactionFormView(kind: .expense, initialGoal: goal) }.presentationDragIndicator(.visible) }
    }
}

struct GoalDetailView: View {
    @Environment(AppModel.self) private var app
    let goalID: String
    @State private var editing = false
    @State private var progress = false
    private var goal: SavingsGoal? { app.snapshot.goals?.first { $0.id == goalID } }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let goal {
                    GoalCard(goal: goal, onProgress: { progress = true }, onEdit: { editing = true })
                    PlanningHistoryView(request: PlanningHistoryRequest(goalID: goalID))
                } else { ContentUnavailableView("Target tidak tersedia", systemImage: "target") }
            }.padding(DesignTokens.gutter)
        }.background(Color.danarapiCanvas).navigationTitle(goal?.name ?? "Target").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { if let goal { GoalEditorView(goal: goal) } }
        .sheet(isPresented: $progress) { if let goal { NavigationStack { TransactionFormView(kind: .expense, initialGoal: goal) } } }
    }
}

struct PlanningHistoryView: View {
    @Environment(AppModel.self) private var app
    var request: PlanningHistoryRequest
    @State private var entries: [PlanningEntry] = []
    @State private var cursor: TransactionCursor?
    @State private var loading = true
    @State private var error: String?
    private var key: String { "\(request.goalID ?? request.categoryID ?? "")-\(request.startDate?.timeIntervalSince1970 ?? 0)-\(app.timezone)-\(app.snapshot.syncedAt?.timeIntervalSince1970 ?? 0)-\(app.snapshot.transactions.map { "\($0.id):\($0.version)" }.joined(separator: ","))" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.goalID == nil ? "Pengeluaran pembentuk realisasi" : "Riwayat kontribusi").font(.headline)
            if loading && entries.isEmpty { ProgressView("Memuat riwayat…") }
            if let error { Text(error).font(.subheadline).foregroundStyle(.secondary); Button("Coba lagi") { Task { await load(more: !entries.isEmpty) } } }
            if !loading && error == nil && entries.isEmpty { EmptyRow(icon: "tray", text: "Belum ada catatan.") }
            ForEach(entries) { entry in
                if entry.kind == "transaction" { NavigationLink { TransactionDetailView(itemID: entry.sourceID) } label: { row(entry) }.buttonStyle(.plain) }
                else if let bill = app.snapshot.splitBills.first(where: { $0.id == entry.sourceID || $0.resolutions.contains(where: { $0.id == entry.sourceID }) }) { NavigationLink { SplitBillDetailView(billID: bill.id) } label: { row(entry) }.buttonStyle(.plain) }
                else { row(entry) }
            }
            if cursor != nil { Button(loading ? "Memuat…" : "Muat lagi") { Task { await load(more: true) } }.disabled(loading) }
        }.frame(maxWidth: .infinity, alignment: .leading).danarapiCard()
        .task(id: key) { await load() }
    }
    private func row(_ entry: PlanningEntry) -> some View {
        HStack(alignment: .top) { VStack(alignment: .leading, spacing: 4) { Text(entry.merchant ?? (entry.kind == "transaction" ? "Kontribusi" : "Porsi split bill")).font(.subheadline.weight(.medium)); Text(MonthPeriod.display(entry.occurredAt)).font(.caption).foregroundStyle(.secondary); if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) } }; Spacer(); MoneyText(amount: entry.amount, style: .subheadline.bold()) }.padding(.vertical, 10).frame(minHeight: 44).foregroundStyle(Color.danarapiInk)
    }
    private func load(more: Bool = false) async {
        let requestedKey = key
        loading = true; error = nil
        if !more { entries = []; cursor = nil }
        defer { if requestedKey == key { loading = false } }
        do {
            var filter = request; filter.cursor = more ? cursor : nil
            let result = try await app.planningHistory(filter)
            try Task.checkCancellation()
            guard requestedKey == key else { return }
            entries = more ? entries + result.items.filter { value in !entries.contains { $0.id == value.id } } : result.items
            cursor = result.nextCursor
        } catch is CancellationError {} catch { if requestedKey == key { self.error = error.localizedDescription } }
    }
}

struct GoalCard: View {
    let goal: SavingsGoal
    var onProgress: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: goal.progress >= 1 ? "checkmark.seal.fill" : "target").foregroundStyle(Color.danarapiPrimary).padding(10).background(Color.danarapiSky, in: RoundedRectangle(cornerRadius: 14))
                Text(goal.name).font(.headline).foregroundStyle(Color.danarapiInk)
                Spacer()
                Text("\(Int(goal.progress * 100))%").font(.subheadline.bold()).foregroundStyle(Color.danarapiPrimary)
            }
            ProgressView(value: goal.progress).tint(Color.danarapiPrimary)
            HStack { MoneyText(amount: goal.savedAmount, style: .subheadline.bold()); Text("dari").foregroundStyle(Color.danarapiMuted); MoneyText(amount: goal.targetAmount, style: .subheadline, color: .danarapiMuted) }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack { Text(goal.countdown(asOf: context.date)).font(.caption.bold()).foregroundStyle(goal.progress >= 1 ? Color.danarapiPrimary : Color.danarapiMuted); Spacer(); if let date = goal.targetDate { Text(MonthPeriod.display(date)).font(.caption).foregroundStyle(Color.danarapiMuted) } }
            }
            HStack { if let onProgress { Button("Tambah progres", systemImage: "plus", action: onProgress).buttonStyle(.bordered).accessibilityIdentifier("goal.progress.\(goal.id)") }; Spacer(); if let onEdit { Button("Ubah target", action: onEdit).font(.subheadline) } }
        }.danarapiCard()
        .accessibilityElement(children: .contain)
    }
}

struct GoalEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal?
    var onSaved: () -> Void = {}
    @State private var name = ""
    @State private var target = ""
    @State private var hasDate = true
    @State private var date = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var goalID = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                Section("Tujuan Anda") {
                    TextField("Nama target", text: $name)
                    MoneyField(title: "Target tabungan", value: $target)
                    Toggle("Pakai tanggal target", isOn: $hasDate)
                    if hasDate { DatePicker("Tanggal target", selection: $date, displayedComponents: .date) }
                }
                Section {
                    Button("Simpan target") { Task { await save() } }.buttonStyle(PrimaryButtonStyle())
                        .disabled(saving || (app.mode == .authenticated && !app.network.isOnline) || name.nilIfBlank == nil || name.count > 100 || (Int64(target) ?? 0) <= 0 || (Int64(target) ?? Int64.max) > Money.maximum)
                }
                if goal != nil { Section { Button("Hapus target", role: .destructive) { confirmDelete = true } } }
            }
            .scrollContentBackground(.hidden).background(Color.danarapiCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(goal == nil ? "Tambah target" : "Ubah target").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
            .onAppear { if let goal { goalID = goal.id; name = goal.name; target = String(goal.targetAmount); hasDate = goal.targetDate != nil; date = goal.targetDate ?? .now } }
            .confirmationDialog("Hapus target? Saldo akun tidak berubah.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Hapus target", role: .destructive) { Task { if let goal, await app.deleteGoal(goal) { onSaved(); dismiss() } } }
            }
        }
    }
    private func save() async {
        guard !saving else { return }; saving = true; defer { saving = false }
        guard let amount = Int64(target) else { return }
        let value = SavingsGoal(id: goalID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), targetAmount: amount, savedAmount: goal?.savedAmount ?? 0, targetDate: hasDate ? date : nil, version: goal?.version ?? 0)
        if await app.saveGoal(value) { onSaved(); dismiss() }
    }
}
