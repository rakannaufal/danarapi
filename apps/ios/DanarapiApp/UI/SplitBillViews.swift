import SwiftUI

private enum SplitMethod: String, CaseIterable, Identifiable {
    case equal = "Sama rata"
    case manual = "Nominal"
    case percentage = "Persentase"
    var id: String { rawValue }
}

private struct ParticipantDraft: Identifiable {
    let id: String
    var name: String
    var isSelf: Bool
    var included: Bool
    var amountText: String
    var percentText: String
}

struct SplitBillFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let editing: SplitBill?
    let reviewItemID: String?
    let convertingTransaction: FinanceTransaction?
    let onSaved: () -> Void
    @State private var title = ""
    @State private var total = ""
    @State private var method: SplitMethod = .equal
    @State private var participants = [
        ParticipantDraft(id: UUID().uuidString, name: "Saya", isSelf: true, included: true, amountText: "", percentText: "100")
    ]
    @State private var payerID = "self"
    @State private var accountID = ""
    @State private var categoryID = ""
    @State private var occurredAt = Date.now
    @State private var note = ""
    @State private var calculating = false

    init(seedTitle: String = "", seedTotal: Int64? = nil, editing: SplitBill? = nil, reviewItemID: String? = nil, convertingTransaction: FinanceTransaction? = nil, onSaved: @escaping () -> Void = {}) {
        self.editing = editing
        self.reviewItemID = reviewItemID
        self.convertingTransaction = convertingTransaction
        self.onSaved = onSaved
        _title = State(initialValue: editing?.title ?? convertingTransaction?.merchant ?? seedTitle)
        _total = State(initialValue: editing.map { String($0.total) } ?? convertingTransaction.map { String($0.amount) } ?? seedTotal.map(String.init) ?? "")
        if let editing {
            _participants = State(initialValue: editing.members.sorted { $0.sortOrder < $1.sortOrder }.map {
                ParticipantDraft(id: $0.id, name: $0.displayName, isSelf: $0.isSelf, included: $0.shareAmount > 0, amountText: String($0.shareAmount), percentText: "0")
            })
            switch editing.payer {
            case let .selfPaid(accountID):
                _payerID = State(initialValue: "self")
                _accountID = State(initialValue: accountID)
            case let .other(memberID):
                _payerID = State(initialValue: memberID)
            }
            _categoryID = State(initialValue: editing.categoryID)
            _occurredAt = State(initialValue: editing.occurredAt)
            _note = State(initialValue: editing.note ?? "")
            _method = State(initialValue: .manual)
        } else if let convertingTransaction {
            _accountID = State(initialValue: convertingTransaction.accountID)
            _categoryID = State(initialValue: convertingTransaction.categoryID)
            _occurredAt = State(initialValue: convertingTransaction.occurredAt)
            _note = State(initialValue: convertingTransaction.note ?? "")
        }
    }

    private var parsedTotal: Int64? { Int64(total) }
    private var structureLocked: Bool { editing?.settlements.contains { !$0.reversed } == true || editing?.resolutions.contains { !$0.reversed } == true }
    private var amountSum: Int64 { participants.reduce(0) { $0 + (Int64($1.amountText) ?? 0) } }
    private var isValid: Bool {
        guard let parsedTotal, parsedTotal > 0, amountSum == parsedTotal, participants.count >= 2,
              participants.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 80 }),
              Set(participants.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == participants.count,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !categoryID.isEmpty else { return false }
        if method == .percentage && (participants.compactMap { basisPoints($0.percentText) }.count != participants.count || participants.compactMap { basisPoints($0.percentText) }.reduce(0, +) != 10_000) { return false }
        return payerID == "self" ? !accountID.isEmpty : participants.contains(where: { $0.id == payerID && !$0.isSelf })
    }

    var body: some View {
        Form {
            Section {
                MoneyField(title: "Total tagihan", value: $total).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).disabled(structureLocked)
                TextField("Judul atau merchant", text: $title)
                TextField("Catatan (opsional)", text: $note)
                if structureLocked { Label("Struktur dikunci karena ada pelunasan atau penghapusan aktif. Judul dan catatan tetap dapat diubah.", systemImage: "lock.fill").font(.caption).foregroundStyle(Color.danarapiMuted) }
            }
            Section("Pembagian") {
                Picker("Metode", selection: $method) { ForEach(SplitMethod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                ForEach($participants) { $participant in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Nama", text: $participant.name).disabled(participant.isSelf)
                            if method == .equal { Toggle("Ikut", isOn: $participant.included).labelsHidden() }
                            if method == .percentage { TextField("%", text: $participant.percentText).keyboardType(.decimalPad).frame(width: 70).multilineTextAlignment(.trailing) }
                            else { RupiahTextField("Rp", text: $participant.amountText).keyboardType(.numberPad).frame(width: 100).multilineTextAlignment(.trailing).disabled(method == .equal) }
                            if !participant.isSelf { Button(role: .destructive) { participants.removeAll { $0.id == participant.id }; if payerID == participant.id { payerID = "self" } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Hapus \(participant.name)") }
                        }
                    }.frame(minHeight: 44)
                }
                HStack {
                    Text("Peserta").foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        participants.append(ParticipantDraft(id: UUID().uuidString, name: "", isSelf: false, included: true, amountText: "", percentText: "0"))
                    } label: {
                        Image(systemName: "plus").font(.body.weight(.semibold))
                            .frame(width: DesignTokens.minimumTouch, height: DesignTokens.minimumTouch)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Tambah peserta")
                    .accessibilityIdentifier("split.addParticipant")
                    .disabled(participants.count >= 20)
                }
                Button(calculating ? "Menghitung…" : "Hitung pembagian") { Task { await calculate() } }.disabled(parsedTotal == nil || calculating)
                HStack { Text("Jumlah"); Spacer(); Text(amountSum.idr).monospacedDigit(); Text(amountSum == parsedTotal ? "Tepat" : "Selisih \((parsedTotal ?? 0) - amountSum)").font(.caption).foregroundStyle(amountSum == parsedTotal ? Color.danarapiIncome : Color.danarapiExpense) }
            }.disabled(structureLocked)
            Section("Pembayar") {
                Picker("Siapa membayar", selection: $payerID) {
                    Text("Saya").tag("self")
                    ForEach(participants.filter { !$0.isSelf }) { Text($0.name).tag($0.id) }
                }
                if payerID == "self" { Picker("Akun pembayar", selection: $accountID) { ForEach(app.activeAccounts) { Text($0.name).tag($0.id) } } }
                Picker("Kategori", selection: $categoryID) { ForEach(app.expenseCategories) { Text($0.name).tag($0.id) } }
                DatePicker("Tanggal", selection: $occurredAt)
            }.disabled(structureLocked)
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Total \((parsedTotal ?? 0).idr) · Bagian saya \((Int64(participants.first(where: \.isSelf)?.amountText ?? "") ?? 0).idr)").font(.headline)
                    Text("Pelunasan hanya mengurangi piutang atau utang; bukan pemasukan atau pengeluaran baru.").font(.caption).foregroundStyle(Color.danarapiMuted)
                }
                Button(editing == nil ? "Simpan tagihan" : "Simpan perubahan") { Task { await save() } }.buttonStyle(PrimaryButtonStyle()).disabled(!isValid).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden).background(Color.danarapiCanvas).navigationTitle(editing != nil ? "Ubah split bill" : convertingTransaction != nil ? "Jadikan split bill" : "Split bill").navigationBarTitleDisplayMode(.inline)
        .onAppear { if accountID.isEmpty { accountID = app.activeAccounts.first?.id ?? "" }; if categoryID.isEmpty { categoryID = app.expenseCategories.first?.id ?? "" } }
        .onChange(of: method) { _, _ in if method == .equal { Task { await calculate() } } }
    }

    private func calculate() async {
        guard let parsedTotal else { return }
        calculating = true
        defer { calculating = false }
        do {
            let result: [String: Int64]
            switch method {
            case .equal:
                result = try await app.calculateEqualSplit(total: parsedTotal, participants: participants.map { EqualParticipant(id: $0.id, included: $0.included) })
            case .percentage:
                let values = participants.map { participant -> PercentageParticipant in
                    PercentageParticipant(id: participant.id, basisPoints: basisPoints(participant.percentText) ?? -1)
                }
                result = try await app.calculatePercentageSplit(total: parsedTotal, participants: values)
            case .manual: return
            }
            for index in participants.indices { participants[index].amountText = String(result[participants[index].id] ?? 0) }
        } catch { app.errorMessage = (error as? AppError)?.message ?? "Pembagian tidak dapat dihitung." }
    }

    private func save() async {
        guard let parsedTotal else { return }
        let members = participants.enumerated().map { index, value in SplitMember(id: value.id, displayName: value.name, isSelf: value.isSelf, shareAmount: Int64(value.amountText) ?? 0, settledAmount: 0, resolvedAmount: 0, sortOrder: index) }
        let payer: SplitPayer = payerID == "self" ? .selfPaid(accountID: accountID) : .other(memberID: payerID)
        let draft = SplitBillDraft(title: title, total: parsedTotal, categoryID: categoryID, payer: payer, occurredAt: occurredAt, note: note.nilIfBlank, members: members)
        let saved: Bool
        if let editing { saved = await app.updateSplitBill(editing, draft: draft) }
        else if let convertingTransaction { saved = await app.convertTransactionToSplitBill(convertingTransaction, draft: draft) }
        else { saved = await app.createSplitBill(draft, reviewItemID: reviewItemID) }
        if saved { onSaved(); dismiss() }
    }

    private func basisPoints(_ value: String) -> Int? {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^(?:100(?:\.0{1,2})?|\d{1,2}(?:\.\d{1,2})?)$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized) else { return nil }
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }
}

struct SplitBillDetailView: View {
    @Environment(AppModel.self) private var app
    let billID: String
    @State private var settlementMember: SplitMember?
    @State private var resolutionMember: SplitMember?
    @State private var settlementToReverse: SplitSettlement?
    @State private var resolutionToReverse: SplitResolution?
    @State private var deletedBill: SplitBill?
    @State private var editingBill: SplitBill?

    private var bill: SplitBill? { app.snapshot.splitBills.first(where: { $0.id == billID }) }

    var body: some View {
        Group {
            if let bill {
                List {
                    Section {
                        HStack { VStack(alignment: .leading) { Text("Total tagihan").font(.caption).foregroundStyle(Color.danarapiMuted); MoneyText(amount: bill.total, style: .title2.bold()) }; Spacer(); VStack(alignment: .trailing) { Text("Bagian saya").font(.caption).foregroundStyle(Color.danarapiMuted); MoneyText(amount: bill.selfShare, style: .title2.bold()) } }
                        LabeledContent("Status", value: bill.status.title)
                        LabeledContent("Sisa kewajiban") { MoneyText(amount: bill.remainingAmount, style: .headline, color: bill.remainingAmount > 0 ? .danarapiExpense : .danarapiIncome) }
                    }
                    Section("Peserta") {
                        ForEach(bill.members) { member in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(member.displayName).font(.headline); if member.isSelf { Text("Saya").font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(Color.danarapiMint, in: Capsule()) }; Spacer(); Text(member.shareAmount.idr).monospacedDigit() }
                                if bill.obligationMembers.contains(where: { $0.id == member.id }) {
                                    ProgressView(value: Double(member.shareAmount - member.remainingAmount), total: Double(max(member.shareAmount, 1))).tint(.danarapiPrimary)
                                    HStack { Text("Dibayar \(member.settledAmount.idr) · Dihapuskan \(member.resolvedAmount.idr)").font(.caption).foregroundStyle(Color.danarapiMuted); Spacer(); Text("Sisa \(member.remainingAmount.idr)").font(.caption.weight(.semibold)) }
                                    if member.remainingAmount > 0 {
                                        HStack { Button("Catat pelunasan") { settlementMember = member }; Button("Hapuskan sisa", role: .destructive) { resolutionMember = member } }.font(.subheadline.weight(.semibold))
                                    }
                                }
                            }.padding(.vertical, 5)
                        }
                    }
                    if let details = bill.itemSplit {
                        Section("Menu yang dibagikan") {
                            ForEach(details.items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(item.name) · \(item.quantity) × \((Int64(item.unitPrice) ?? 0).idr)").font(.headline)
                                    ForEach(item.allocations.filter { $0.quantity > 0 }, id: \.memberID) { allocation in
                                        Text("\(bill.members.first { $0.id == allocation.memberID }?.displayName ?? "Peserta")\(details.settings == nil ? ": \(allocation.quantity)" : " · berbagi menu")").font(.subheadline).foregroundStyle(Color.danarapiMuted)
                                    }
                                }
                            }
                            if details.settings != nil, let result = try? ItemSplitCalculator.receipt(details, memberIDs: bill.members.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)) {
                                LabeledContent("Pajak", value: result.rows.reduce(0) { $0 + $1.tax }.idr)
                                LabeledContent("Layanan", value: result.rows.reduce(0) { $0 + $1.service }.idr)
                                LabeledContent("Pembulatan", value: result.rows.reduce(0) { $0 + $1.rounding }.idr)
                            } else {
                                LabeledContent("Pajak", value: (Int64(details.tax) ?? 0).idr)
                                LabeledContent("Layanan", value: (Int64(details.service) ?? 0).idr)
                            }
                            LabeledContent("Diskon", value: (Int64(details.discount) ?? 0).idr)
                        }
                    }
                    if !bill.settlements.isEmpty || !bill.resolutions.isEmpty {
                        Section("Riwayat") {
                            ForEach(bill.settlements) { event in HStack { Label("Pelunasan \(event.amount.idr)", systemImage: event.reversed ? "arrow.uturn.backward.circle" : "checkmark.circle"); Spacer(); if !event.reversed { Button("Batalkan") { settlementToReverse = event }.font(.caption) } } }
                            ForEach(bill.resolutions) { event in HStack { Label("Dihapuskan \(event.amount.idr)", systemImage: event.reversed ? "arrow.uturn.backward.circle" : "xmark.circle"); Spacer(); if !event.reversed { Button("Batalkan") { resolutionToReverse = event }.font(.caption) } } }
                        }
                    }
                    Section {
                        Button("Ubah bill") { editingBill = bill }
                        ShareLink(item: reminder(bill)) { Label("Bagikan ringkasan", systemImage: "square.and.arrow.up") }
                        Button("Hapus bill", role: .destructive) { Task { if await app.deleteSplitBill(bill) { deletedBill = bill } } }.disabled(bill.settlements.contains { !$0.reversed } || bill.resolutions.contains { !$0.reversed })
                    }
                }.danarapiListSurface().navigationTitle(bill.title)
            } else { ContentUnavailableView("Bill tidak tersedia", systemImage: AppSymbol.split.rawValue) }
        }
        .sheet(item: $settlementMember) { SettlementSheet(billID: billID, member: $0) }
        .sheet(item: $resolutionMember) { ResolutionSheet(billID: billID, member: $0) }
        .sheet(item: $settlementToReverse) { SettlementReversalSheet(event: $0) }
        .sheet(item: $resolutionToReverse) { ResolutionReversalSheet(event: $0) }
        .sheet(item: $editingBill) { bill in NavigationStack { if bill.itemSplit != nil { ItemSplitFormView(editing: bill) { editingBill = nil } } else { SplitBillFormView(editing: bill) { editingBill = nil } } } }
        .safeAreaInset(edge: .bottom) {
            if let deletedBill {
                HStack { Text("Split bill dihapus"); Spacer(); Button("Urungkan") { Task { if await app.restoreSplitBill(deletedBill) { self.deletedBill = nil } } } }
                    .padding().background(.regularMaterial)
                    .task { try? await Task.sleep(for: .seconds(10)); self.deletedBill = nil }
            }
        }
    }

    private func reminder(_ bill: SplitBill) -> String { "Saya membayar \(bill.total.idr); bagian saya \(bill.selfShare.idr); \(bill.remainingAmount.idr) masih tercatat sebagai kewajiban. Danarapi tidak memproses atau memverifikasi pembayaran." }
}

private struct SettlementReversalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let event: SplitSettlement
    @State private var reason = ""
    var body: some View {
        NavigationStack { Form { Section { Text("Membatalkan pelunasan \(event.amount.idr) akan memulihkan sisa kewajiban dan membalik arus kasnya."); TextField("Alasan wajib", text: $reason, axis: .vertical) }; Section { Button("Batalkan pelunasan", role: .destructive) { Task { if await app.reverseSettlement(event, reason: reason) { dismiss() } } }.disabled(reason.nilIfBlank == nil) } }.danarapiListSurface().navigationTitle("Batalkan pelunasan").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } } }
    }
}

private struct ResolutionReversalSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let event: SplitResolution
    @State private var reason = ""
    var body: some View {
        NavigationStack { Form { Section { Text("Pembalikan memulihkan piutang atau utang tanpa mengubah saldo akun."); TextField("Alasan wajib", text: $reason, axis: .vertical) }; Section { Button("Batalkan penghapusan", role: .destructive) { Task { if await app.reverseResolution(event, reason: reason) { dismiss() } } }.disabled(reason.nilIfBlank == nil) } }.danarapiListSurface().navigationTitle("Batalkan penghapusan").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } } }
    }
}

private struct SettlementSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let billID: String
    let member: SplitMember
    @State private var amount = ""
    @State private var accountID = ""
    @State private var note = ""
    var body: some View {
        NavigationStack { Form { Section { MoneyField(title: "Nominal pelunasan", value: $amount).listRowInsets(EdgeInsets()).listRowBackground(Color.clear); Text("Sisa \(member.remainingAmount.idr)").font(.caption) }; Section { Picker("Akun", selection: $accountID) { ForEach(app.activeAccounts) { Text($0.name).tag($0.id) } }; TextField("Catatan", text: $note) }; Section { Button("Catat pelunasan") { Task { guard let value = Int64(amount) else { return }; if await app.recordSettlement(SettlementDraft(billID: billID, memberID: member.id, accountID: accountID, amount: value, occurredAt: .now, note: note.nilIfBlank)) { dismiss() } } }.buttonStyle(PrimaryButtonStyle()).disabled((Int64(amount) ?? 0) <= 0 || (Int64(amount) ?? 0) > member.remainingAmount).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) } }.danarapiListSurface().navigationTitle("Pelunasan \(member.displayName)").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }.onAppear { accountID = app.activeAccounts.first?.id ?? "" } }
    }
}

private struct ResolutionSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let billID: String
    let member: SplitMember
    @State private var amount = ""
    @State private var reason = ""
    var body: some View {
        NavigationStack { Form { Section { MoneyField(title: "Nominal yang dihapuskan", value: $amount).listRowInsets(EdgeInsets()).listRowBackground(Color.clear); Text("Saldo akun tidak berubah. Piutang yang dihapus menjadi pengeluaran nonkas; pembebasan utang menjadi pemasukan nonkas.").font(.caption).foregroundStyle(Color.danarapiMuted) }; Section { TextField("Alasan wajib", text: $reason, axis: .vertical) }; Section { Button("Hapuskan kewajiban", role: .destructive) { Task { guard let value = Int64(amount) else { return }; if await app.recordResolution(ResolutionDraft(billID: billID, memberID: member.id, amount: value, occurredAt: .now, reason: reason)) { dismiss() } } }.disabled((Int64(amount) ?? 0) <= 0 || (Int64(amount) ?? 0) > member.remainingAmount || reason.nilIfBlank == nil) } }.danarapiListSurface().navigationTitle("Hapuskan sisa").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } } }
    }
}
