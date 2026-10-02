import AVFoundation
import PhotosUI
import SwiftUI

struct ReceiptScanReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var receipt: ScannedReceipt
    @State private var confirm = false
    @State private var enlarged = false
    let images: [UIImage]
    let onApply: (ScannedReceipt) -> Void
    init(initial: ScannedReceipt, images: [UIImage], onApply: @escaping (ScannedReceipt) -> Void) { _receipt = State(initialValue: initial); self.images = images; self.onApply = onApply }
    private var validation: ScannedReceiptValidation { receipt.validation }
    var body: some View {
        NavigationStack {
            Form {
                if !images.isEmpty { Section("Foto struk") {
                    ForEach(images.indices, id: \.self) { index in
                        Button { enlarged.toggle() } label: { Image(uiImage: images[index]).resizable().scaledToFit().frame(maxHeight: enlarged ? 900 : 240) }.buttonStyle(.plain).accessibilityLabel(enlarged ? "Perkecil foto struk" : "Perbesar foto struk")
                    }
                    Text("Ketuk foto untuk memperbesar.").font(.caption).foregroundStyle(.secondary)
                } }
                Section("Toko dan tanggal") {
                    TextField("Nama toko", text: Binding(get: { receipt.merchant ?? "" }, set: { receipt.merchant = String($0.prefix(160)); corrected("merchant") }))
                    TextField("Tanggal YYYY-MM-DD", text: Binding(get: { receipt.date ?? "" }, set: { receipt.date = String($0.prefix(10)); corrected("date") }))
                }
                ForEach(receipt.items.indices, id: \.self) { index in menuRow(index) }
                Section { Button("Tambah baris", systemImage: "plus") { receipt.items.append(ScannedReceiptItem()) }.disabled(receipt.items.count >= 100) }
                Section("Biaya pada struk") {
                    amountRow("Subtotal struk", field: "subtotal", key: \.subtotal)
                    amountRow("Service (Rp)", field: "service_charge", key: \.serviceCharge)
                    amountRow("Pajak (Rp)", field: "tax", key: \.tax)
                    HStack { Text("Diskon (Rp)"); Spacer(); RupiahTextField("0", text: Binding(get: { String(receipt.discount) }, set: { receipt.discount = abs(parsed($0) ?? 0); corrected("discount") })).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Pembulatan (Rp)"); Spacer(); RupiahTextField("0", text: Binding(get: { String(receipt.rounding) }, set: { receipt.rounding = parsed($0) ?? 0; corrected("rounding") }), signed: true).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
                    amountRow("Total struk", field: "grand_total", key: \.grandTotal)
                    Toggle("Harga termasuk pajak dan service", isOn: Binding(get: { receipt.taxIncludedInPrice }, set: { receipt.taxIncludedInPrice = $0; corrected("tax_included_in_price") }))
                }
                Section {
                    if !validation.passed || !validation.warnings.isEmpty {
                        DisclosureGroup("Perlu dikoreksi") {
                            ForEach(validation.problems, id: \.self) { Text($0).font(.subheadline).foregroundStyle(Color.danarapiExpense) }
                            ForEach(validation.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Button(validation.passed ? "Lanjut pilih pemesan" : "Lanjut, saya sudah memeriksa") { if validation.passed { onApply(receipt) } else { confirm = true } }.buttonStyle(PrimaryButtonStyle())
                }
            }.navigationTitle("Periksa struk").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Isi manual") { dismiss() } } }
                .confirmationDialog("Data struk belum cocok. Lanjut dengan angka yang sudah Anda periksa?", isPresented: $confirm, titleVisibility: .visible) { Button("Lanjut dengan koreksi") { onApply(receipt) }; Button("Periksa lagi", role: .cancel) {} }
        }
    }
    private func corrected(_ field: String) { receipt.unreadableFields.removeAll { $0 == field } }
    private func parsed(_ text: String) -> Int64? { guard let amount = Int64(text), amount >= -Money.maximum, amount <= Money.maximum else { return nil }; return amount }
    private func amountRow(_ label: String, field: String, key: WritableKeyPath<ScannedReceipt, Int64?>) -> some View {
        HStack { Text(label); Spacer(); RupiahTextField("Belum terbaca", text: Binding(get: { receipt[keyPath: key].map(String.init) ?? "" }, set: { receipt[keyPath: key] = parsed($0).flatMap { $0 >= 0 ? $0 : nil }; corrected(field) })).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
    }
    private func menuRow(_ index: Int) -> some View {
        Section("Menu \(index + 1)\(validation.badRows.contains(index) ? " · Perlu diperiksa" : "")") {
            TextField("Nama menu", text: Binding(get: { receipt.items[index].name }, set: { receipt.items[index].name = String($0.prefix(160)); corrected("items[\(index)].name") }))
            HStack { Text("Jumlah (1–999.999)"); Spacer(); TextField("Jumlah", value: Binding(get: { receipt.items[index].qty }, set: { receipt.items[index].qty = $0; corrected("items[\(index)].qty") }), format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            HStack { Text("Harga satuan"); Spacer(); RupiahTextField("Belum terbaca", text: itemAmount(index, key: \.unitPrice, field: "unit_price")).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            HStack { Text("Total baris"); Spacer(); RupiahTextField("Belum terbaca", text: itemAmount(index, key: \.lineTotal, field: "line_total")).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            TextField("Catatan menu", text: Binding(get: { receipt.items[index].note ?? "" }, set: { receipt.items[index].note = String($0.prefix(500)) }))
            Button("Hapus baris", role: .destructive) { receipt.items.remove(at: index); receipt.unreadableFields.removeAll { $0.hasPrefix("items[") } }
        }.listRowBackground(validation.badRows.contains(index) ? Color.danarapiExpense.opacity(0.08) : Color.danarapiSurface)
    }
    private func itemAmount(_ index: Int, key: WritableKeyPath<ScannedReceiptItem, Int64?>, field: String) -> Binding<String> {
        Binding(get: { receipt.items[index][keyPath: key].map(String.init) ?? "" }, set: { receipt.items[index][keyPath: key] = parsed($0).flatMap { $0 >= 0 ? $0 : nil }; corrected("items[\(index)].\(field)") })
    }
}

private struct DiningParticipant: Identifiable, Hashable {
    var id: String
    var name: String
    var isSelf: Bool
}

struct ItemSplitFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let reviewItemID: String?
    let editing: SplitBill?
    let onSaved: () -> Void
    @State private var title: String
    @State private var participants: [DiningParticipant]
    @State private var draft: ItemSplit
    @State private var result: ItemSplitResult?
    @State private var accountID = ""
    @State private var categoryID = ""
    @State private var payerID = "self"
    @State private var date = Date.now
    @State private var note = ""
    @State private var receiptText = ""
    @State private var showText = false
    @State private var showCamera = false
    @State private var processing = false
    @State private var receiptMessage: String?
    @State private var newName = ""
    @State private var copied = false
    @State private var scanPhotos: [PhotosPickerItem] = []
    @State private var scanTask: Task<Void, Never>?
    @State private var scanGeneration = UUID()
    @State private var scannedReceipt: ScannedReceipt?
    @State private var scanPreviews: [UIImage] = []
    @State private var showScanReview = false
    @State private var receiptTotal: Int64?
    @State private var mismatchConfirmed = false
    @State private var assignmentMode = "menu"
    @State private var selectedPerson = ""
    @FocusState private var focusedField: String?

    init(seedTitle: String = "", receiptLines: [ReceiptLine] = [], receipt: ScannedReceipt? = nil, reviewItemID: String? = nil, editing: SplitBill? = nil, onSaved: @escaping () -> Void = {}) {
        self.reviewItemID = reviewItemID; self.editing = editing; self.onSaved = onSaved
        _title = State(initialValue: editing?.title ?? seedTitle)
        _participants = State(initialValue: editing?.members.sorted { $0.sortOrder < $1.sortOrder }.map { DiningParticipant(id: $0.id, name: $0.displayName, isSelf: $0.isSelf) } ?? [DiningParticipant(id: UUID().uuidString, name: "Saya", isSelf: true)])
        _draft = State(initialValue: editing?.itemSplit ?? ItemSplit(items: receiptLines.isEmpty ? [ReceiptLine(name: "", quantity: 1, unitPrice: "")] : receiptLines, settings: ReceiptSettings()))
        if editing == nil, let receipt {
            let base = receipt.subtotal ?? receipt.items.reduce(0) { $0 + Int64($1.qty) * ($1.unitPrice ?? 0) }
            let settings = ReceiptSettings(serviceRate: base > 0 ? (Double(receipt.serviceCharge ?? 0) / Double(base) * 10000).rounded() / 100 : 0, taxRate: base > 0 ? (Double(receipt.tax ?? 0) / Double(base) * 10000).rounded() / 100 : 0, taxIncluded: receipt.taxIncludedInPrice)
            _draft = State(initialValue: ItemSplit(items: receipt.items.map { ReceiptLine(name: $0.name, quantity: $0.qty, unitPrice: $0.unitPrice.map(String.init) ?? "") }, discount: String(receipt.discount), settings: settings, rounding: String(receipt.rounding)))
            _receiptTotal = State(initialValue: receipt.grandTotal)
            _date = State(initialValue: ImportService.receiptDate(receipt.date) ?? .now)
        }
    }

    private var locked: Bool { editing.map { $0.settlements.contains { !$0.reversed } || $0.resolutions.contains { !$0.reversed } } ?? false }
    private var memberIDs: [String] { participants.map(\.id) }
    private var receiptCalculation: ReceiptCalculation? { try? ItemSplitCalculator.receipt(draft, memberIDs: memberIDs) }
    private var receiptAccent: Color { .danarapiPrimary }
    private var receiptCanvas: Color { .danarapiCanvas }
    private var receiptCard: Color { .danarapiSurface }

    var body: some View {
        Form {
            Section {
                if editing == nil { NavigationLink("Bagi total saja (sama rata / manual)") { SplitBillFormView(seedTitle: title, reviewItemID: reviewItemID, onSaved: onSaved) } }
                TextField("Judul tagihan", text: $title).focused($focusedField, equals: "title")
            }
            participantsSection.disabled(locked)
            if !locked { importSection }
            menusSection.disabled(locked)
            Section("3. Biaya tambahan") {
                if draft.settings != nil {
                    HStack { Text("Service (%)"); Spacer(); TextField("5", value: rateBinding(service: true), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
                    HStack { Text("Pajak / PB1 (%)"); Spacer(); TextField("10", value: rateBinding(service: false), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100) }
                    Toggle("Hitung pajak dari subtotal + service", isOn: Binding(get: { draft.settings?.taxOnService ?? false }, set: { draft.settings?.taxOnService = $0 }))
                    Toggle("Harga termasuk pajak dan service", isOn: Binding(get: { draft.settings?.taxIncluded ?? false }, set: { draft.settings?.taxIncluded = $0 }))
                    adjustment("Diskon (Rp)", value: $draft.discount)
                    HStack { Text("Pembulatan struk (Rp)"); Spacer(); RupiahTextField("0", text: Binding(get: { draft.rounding ?? "0" }, set: { draft.rounding = $0 }), signed: true).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(maxWidth: 140) }
                } else {
                adjustment("Pajak (Rp)", value: $draft.tax)
                adjustment("Layanan (Rp)", value: $draft.service)
                adjustment("Diskon (Rp)", value: $draft.discount)
                }
                InformationDisclosure(title: "Cara pembagian", message: "Menu bersama dibagi rata. Biaya tambahan mengikuti porsi pesanan. Pembulatan dibagi tanpa selisih menurut sisa terbesar.")
            }.disabled(locked)
            if draft.settings != nil { receiptResults }
            Section("Pencatatan") {
                Picker("Siapa membayar", selection: $payerID) { Text("Saya").tag("self"); ForEach(participants.filter { !$0.isSelf }) { Text($0.name).tag($0.id) } }
                if payerID == "self" { Picker("Akun pembayar", selection: $accountID) { ForEach(app.activeAccounts) { Text($0.name).tag($0.id) } } }
                Picker("Kategori", selection: $categoryID) { ForEach(app.expenseCategories) { Text($0.name).tag($0.id) } }
                DatePicker("Tanggal", selection: $date)
            }.disabled(locked)
            Section {
                TextField("Catatan (opsional)", text: $note).focused($focusedField, equals: "note")
                if draft.settings == nil { Button(processing ? "Menghitung…" : "Hitung pengeluaran per orang") { Task { await calculate() } }.disabled(processing) }
                if let result = draft.settings == nil ? result : receiptCalculation?.result {
                    if draft.settings == nil {
                    LabeledContent("Total tagihan") { MoneyText(amount: Int64(result.total) ?? 0, style: .headline) }
                    ForEach(participants) { person in
                        let amount = Int64(result.shares[person.id] ?? "0") ?? 0
                        LabeledContent(person.name) { MoneyText(amount: amount, style: .headline, color: .danarapiPrimary) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(person.name)
                            .accessibilityValue(app.hideAmounts ? "Nominal disembunyikan" : amount.idrAccessibility)
                            .accessibilityIdentifier("split.share.\(person.name)")
                    }
                    }
                    Text("Hanya porsi Anda menjadi pengeluaran.").font(.caption).foregroundStyle(Color.danarapiMuted)
                    Button("Simpan tagihan") { Task { await save(result) } }.buttonStyle(PrimaryButtonStyle()).disabled(locked || title.nilIfBlank == nil || categoryID.isEmpty || (payerID == "self" && accountID.isEmpty) || processing || participants.count < 2 || result.total == "0" || !(receiptCalculation?.unassigned.isEmpty ?? true))
                }
            }
        }
        .scrollContentBackground(.hidden).background(receiptCanvas).tint(receiptAccent).navigationTitle("Split bill").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Selesai") { focusedField = nil }.accessibilityLabel("Tutup keyboard").accessibilityIdentifier("split.keyboardDone") } }
        .onAppear {
            selectedPerson = participants.first?.id ?? ""
            categoryID = editing?.categoryID ?? app.expenseCategories.first?.id ?? ""
            date = editing?.occurredAt ?? .now; note = editing?.note ?? ""
            if let payer = editing?.payer { switch payer { case let .selfPaid(id): accountID = id; case let .other(id): payerID = id } }
            if accountID.isEmpty { accountID = app.activeAccounts.first?.id ?? "" }
        }
        .onChange(of: draft) { _, _ in result = nil; copied = false; mismatchConfirmed = false }
        .onChange(of: participants) { _, _ in result = nil; copied = false; mismatchConfirmed = false }
        .onChange(of: scanPhotos) { _, selections in
            guard !selections.isEmpty else { return }
            cancelScan(); let generation = scanGeneration; processing = true
            scanTask = Task {
                do {
                    var images: [UIImage] = []
                    for selection in selections { try Task.checkCancellation(); guard let data = try await selection.loadTransferable(type: Data.self) else { throw AppError.validation("Foto tidak dapat dibaca.") }; images.append(try ImportService.receiptImage(from: data)) }
                    await scan(images, generation: generation)
                } catch { if generation == scanGeneration { processing = false; receiptMessage = "Foto tidak dapat dibaca. Isi manual tetap tersedia." } }
                scanPhotos = []
            }
        }
        .sheet(isPresented: $showCamera) { PhotoCameraPicker { image in showCamera = false; if let image { cancelScan(); let generation = scanGeneration; scanTask = Task { await scan([image], generation: generation) } } }.ignoresSafeArea() }
        .sheet(isPresented: $showScanReview, onDismiss: { scanPreviews = []; scannedReceipt = nil }) {
            if let scannedReceipt { ReceiptScanReviewSheet(initial: scannedReceipt, images: scanPreviews) { applyScannedReceipt($0); showScanReview = false } }
        }
        .onDisappear { cancelScan() }
    }

    private var menusSection: some View {
        Section("2. Menu yang dipesan") {
            if draft.settings != nil {
                Picker("Cara memilih pemesan", selection: $assignmentMode) { Text("Per menu").tag("menu"); Text("Per orang").tag("person") }.pickerStyle(.segmented)
                if assignmentMode == "person" { Picker("Pilih pemesan", selection: $selectedPerson) { ForEach(participants) { Text($0.name).tag($0.id) } } }
            }
            ForEach($draft.items) { item in menuRow(item) }
            Button("Tambah menu", systemImage: "plus") { if draft.items.count < 100 { draft.items.append(ReceiptLine(name: "", quantity: 1, unitPrice: "")) } }
        }
    }

    private func menuRow(_ binding: Binding<ReceiptLine>) -> some View {
        let item = binding.wrappedValue
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Nama menu", text: binding.name).font(.headline).focused($focusedField, equals: "menu.\(item.id)")
                Button(role: .destructive) { draft.items.removeAll { $0.id == item.id } } label: { Image(systemName: "trash").frame(minWidth: DesignTokens.minimumTouch, minHeight: DesignTokens.minimumTouch) }.buttonStyle(.borderless).accessibilityLabel("Hapus menu \(item.name)")
            }
            HStack { Text("Jumlah dibeli (0–999.999)"); Spacer(); TextField("Jumlah dibeli", value: binding.quantity, format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            HStack { Text("Harga satuan"); Spacer(); RupiahTextField("Harga satuan", text: binding.unitPrice, focus: $focusedField, focusID: "price.\(item.id)").keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 150) }
            owners(for: item)
        }.padding(.vertical, 6)
    }

    @ViewBuilder private func owners(for item: ReceiptLine) -> some View {
        if draft.settings != nil {
            ForEach(participants.filter { assignmentMode == "menu" || $0.id == selectedPerson }) { person in
                Toggle(person.name, isOn: ownerBinding(itemID: item.id, memberID: person.id))
                    .toggleStyle(.switch).tint(receiptAccent)
                    .accessibilityLabel("\(person.name), pemesan \(item.name)")
            }
            Text(item.allocations.isEmpty ? "Belum ada pemesan" : "Dibagi rata ke \(item.allocations.count) orang")
                .font(.caption).foregroundStyle(item.allocations.isEmpty ? Color.danarapiExpense : receiptAccent)
        } else {
            ForEach(participants) { person in allocationRow(item: item, person: person) }
            let assigned = item.allocations.reduce(0) { $0 + $1.quantity }
            Text(assigned == item.quantity ? "Semua jumlah sudah dibagikan" : "Dibagikan \(assigned) dari \(item.quantity); harus tepat")
                .font(.caption).foregroundStyle(assigned == item.quantity ? Color.danarapiPrimary : Color.danarapiExpense)
        }
    }

    private func allocationRow(item: ReceiptLine, person: DiningParticipant) -> some View {
        let count = quantity(item: item, memberID: person.id)
        return HStack {
            Text(person.name).font(.subheadline)
            Spacer()
            Button { allocationBinding(itemID: item.id, memberID: person.id).wrappedValue = max(0, count - 1) } label: { Image(systemName: "minus").frame(width: 44, height: 44).background(Color.danarapiSky, in: Circle()) }
                .buttonStyle(.borderless).disabled(count == 0).accessibilityLabel("Kurangi jumlah \(item.name) untuk \(person.name)")
            Text("\(count)").font(.headline.monospacedDigit()).frame(minWidth: 24).accessibilityLabel("\(person.name) mendapat \(count) \(item.name)")
            Button { allocationBinding(itemID: item.id, memberID: person.id).wrappedValue = min(item.quantity, count + 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44).background(Color.danarapiSky, in: Circle()) }
                .buttonStyle(.borderless).disabled(count >= item.quantity).accessibilityLabel("Tambah jumlah \(item.name) untuk \(person.name)").accessibilityIdentifier("allocation.plus.\(item.name).\(person.name)")
        }
    }

    private var participantsSection: some View {
        Section("1. Siapa saja yang ikut?") {
            ForEach($participants) { $person in
                HStack {
                    TextField("Nama peserta", text: $person.name).focused($focusedField, equals: "person.\(person.id)").disabled(person.isSelf)
                    if !person.isSelf { Button(role: .destructive) { removeParticipant(person.id) } label: { Image(systemName: "minus.circle").frame(minWidth: DesignTokens.minimumTouch, minHeight: DesignTokens.minimumTouch) }.buttonStyle(.borderless).accessibilityLabel("Hapus peserta \(person.name)") }
                }
            }
            HStack(spacing: 12) {
                TextField("Nama orang", text: $newName).focused($focusedField, equals: "newPerson").submitLabel(.done).onSubmit(addParticipant)
                Button(action: addParticipant) {
                    Image(systemName: "plus").font(.body.weight(.semibold))
                        .frame(width: DesignTokens.minimumTouch, height: DesignTokens.minimumTouch)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Tambah orang")
                .accessibilityIdentifier("split.addPerson")
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || participants.count >= 20)
            }
        }.listRowBackground(receiptCard)
    }

    private var receiptResults: some View {
        Section("Hasil pembagian") {
            if let calculation = receiptCalculation {
                if !calculation.unassigned.isEmpty { Text("Belum ada pemesan: \(calculation.unassigned.joined(separator: ", ")).").font(.subheadline).foregroundStyle(Color.danarapiExpense).accessibilityAddTraits(.updatesFrequently) }
                ForEach(calculation.rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(participants.first { $0.id == row.id }?.name ?? "").font(.headline); Spacer(); MoneyText(amount: row.total, style: .headline, color: receiptAccent) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(participants.first { $0.id == row.id }?.name ?? "Peserta")
                            .accessibilityValue(app.hideAmounts ? "Nominal disembunyikan" : row.total.idrAccessibility)
                            .accessibilityIdentifier("split.share.\(participants.first { $0.id == row.id }?.name ?? row.id)")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { receiptAmount("Pesanan", row.subtotal); receiptAmount("Diskon", row.discount); receiptAmount("Service", row.service); receiptAmount("Pajak", row.tax); receiptAmount("Pembulatan", row.rounding) }
                            VStack(alignment: .leading, spacing: 8) { receiptAmount("Pesanan", row.subtotal); receiptAmount("Diskon", row.discount); receiptAmount("Service", row.service); receiptAmount("Pajak", row.tax); receiptAmount("Pembulatan", row.rounding) }
                        }
                    }.padding(.vertical, 6)
                }
                LabeledContent("Total pesanan") { MoneyText(amount: calculation.rows.reduce(0) { $0 + $1.subtotal }) }
                LabeledContent("Total service") { MoneyText(amount: calculation.rows.reduce(0) { $0 + $1.service }) }
                LabeledContent("Total pajak") { MoneyText(amount: calculation.rows.reduce(0) { $0 + $1.tax }) }
                LabeledContent("Total diskon") { MoneyText(amount: calculation.rows.reduce(0) { $0 + $1.discount }) }
                LabeledContent("Pembulatan struk") { MoneyText(amount: calculation.rows.reduce(0) { $0 + $1.rounding }) }
                LabeledContent("Total bayar") { MoneyText(amount: calculation.total, style: .headline, color: receiptAccent) }
                if let receiptTotal, calculation.unassigned.isEmpty {
                    if receiptTotal == calculation.total { Text("Total pembagian sama persis dengan total struk.").font(.caption).foregroundStyle(receiptAccent) }
                    else {
                        Text("Selisih terhadap struk: \(abs(calculation.total - receiptTotal).idr). Periksa diskon dan tarif.").font(.caption).foregroundStyle(Color.danarapiExpense)
                        Button("Sesuaikan pembulatan dengan struk") { draft.rounding = String((Int64(draft.rounding ?? "0") ?? 0) + receiptTotal - calculation.total) }.disabled(locked)
                        Toggle("Saya sudah memeriksa; gunakan total hasil koreksi", isOn: $mismatchConfirmed)
                    }
                }
                
                Button(copied ? "Ringkasan tersalin" : "Salin ringkasan", systemImage: "doc.on.doc") {
                    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
                    UIPasteboard.general.string = (["Split Bill - \(title.isEmpty ? "Tagihan bersama" : title) (\(formatter.string(from: date)))"] + calculation.rows.map { row in "\(participants.first { $0.id == row.id }?.name ?? ""): \(row.total.idr)" } + ["Total: \(calculation.total.idr)"]).joined(separator: "\n")
                    copied = true
                }.disabled(!calculation.unassigned.isEmpty)
            } else { Text("Isi harga dan qty valid; service dan pajak 0–100% (maksimal dua desimal).").foregroundStyle(Color.danarapiExpense) }
        }.listRowBackground(receiptCard)
    }
    private func receiptAmount(_ label: String, _ amount: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption).foregroundStyle(.secondary); MoneyText(amount: amount, style: .subheadline) }
    }
    private func addParticipant() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, participants.count < 20 else { return }
        guard !participants.contains(where: { $0.name.lowercased() == name.lowercased() }) else { app.errorMessage = "Nama peserta tidak boleh sama."; return }
        participants.append(DiningParticipant(id: UUID().uuidString, name: name, isSelf: false)); newName = ""
    }
    private func rateBinding(service: Bool) -> Binding<Double> {
        Binding(get: { service ? draft.settings?.serviceRate ?? 0 : draft.settings?.taxRate ?? 0 }, set: { if service { draft.settings?.serviceRate = $0 } else { draft.settings?.taxRate = $0 } })
    }
    private func ownerBinding(itemID: String, memberID: String) -> Binding<Bool> {
        Binding(get: { draft.items.first { $0.id == itemID }?.allocations.contains { $0.memberID == memberID } ?? false }, set: { selected in
            guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
            draft.items[index].allocations.removeAll { $0.memberID == memberID }
            if selected { draft.items[index].allocations.append(ItemAllocation(memberID: memberID, quantity: 1)) }
        })
    }

    private var importSection: some View {
        Section("Bantu isi dari struk") {
            PhotosPicker(selection: $scanPhotos, maxSelectionCount: 3, matching: .images) { Label("Pilih dari galeri (maks. 3)", systemImage: "photo") }.disabled(processing)
            Button("Scan struk dengan kamera", systemImage: "camera") { Task { await openCamera() } }.disabled(processing)
            if processing { HStack { ProgressView(); Text("Membaca struk…"); Spacer(); Button("Batal", action: cancelScan) } }
            Button("Isi manual") { cancelScan(); scanPreviews = []; scannedReceipt = nil }
            Button("Tempel teks struk", systemImage: "doc.text") { focusedField = nil; showText.toggle() }
            if showText {
                TextEditor(text: $receiptText).frame(minHeight: 110).focused($focusedField, equals: "receipt").autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("Teks struk menu").accessibilityIdentifier("receipt.menu.text")
                Button("Baca menu dari teks") { applyReceipt(receiptText) }
            }
            if let receiptMessage { Text(receiptMessage).font(.caption).foregroundStyle(Color.danarapiMuted) }
            Text("Periksa hasil sebelum menyimpan.").font(.caption).foregroundStyle(Color.danarapiMuted)
        }
    }

    private func cancelScan() { scanGeneration = UUID(); scanTask?.cancel(); scanTask = nil; processing = false }
    private func scan(_ images: [UIImage], generation: UUID) async {
        processing = true
        defer { if generation == scanGeneration { processing = false } }
        do {
            let compressed = try images.map { try ImportService.compressedReceipt($0) }
            try Task.checkCancellation()
            let response = try await app.scanReceipt(images: compressed.map(\.0))
            guard generation == scanGeneration, !Task.isCancelled else { return }
            receiptMessage = response.message
            if response.status == "ok", let data = response.data { scanPreviews = compressed.map(\.1); scannedReceipt = data; showScanReview = true }
        } catch { if generation == scanGeneration, !Task.isCancelled { receiptMessage = (error as? AppError)?.message ?? "Scan belum berhasil. Isi manual tetap tersedia." } }
    }
    private func applyScannedReceipt(_ receipt: ScannedReceipt) {
        draft.items = receipt.items.map { ReceiptLine(name: $0.name, quantity: $0.qty, unitPrice: String($0.unitPrice ?? 0)) }
        let base = receipt.subtotal ?? receipt.items.reduce(0) { $0 + Int64($1.qty) * ($1.unitPrice ?? 0) }
        draft.settings = ReceiptSettings(serviceRate: base > 0 ? (Double(receipt.serviceCharge ?? 0) / Double(base) * 10000).rounded() / 100 : 0, taxRate: base > 0 ? (Double(receipt.tax ?? 0) / Double(base) * 10000).rounded() / 100 : 0, taxIncluded: receipt.taxIncludedInPrice)
        draft.discount = String(receipt.discount); draft.rounding = String(receipt.rounding)
        if let merchant = receipt.merchant { title = merchant }
        if let value = receipt.date { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; if let parsed = formatter.date(from: value) { date = parsed } }
        receiptTotal = receipt.grandTotal; mismatchConfirmed = false; scanPreviews = []; scannedReceipt = nil
    }

    private func adjustment(_ label: String, value: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); RupiahTextField("0", text: value, focus: $focusedField, focusID: label).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 140) }
    }
    private func quantity(item: ReceiptLine, memberID: String) -> Int { item.allocations.first { $0.memberID == memberID }?.quantity ?? 0 }
    private func allocationBinding(itemID: String, memberID: String) -> Binding<Int> {
        Binding(get: { draft.items.first { $0.id == itemID }.map { quantity(item: $0, memberID: memberID) } ?? 0 }, set: { value in
            guard let index = draft.items.firstIndex(where: { $0.id == itemID }) else { return }
            draft.items[index].allocations.removeAll { $0.memberID == memberID }
            draft.items[index].allocations.append(ItemAllocation(memberID: memberID, quantity: value))
        })
    }
    private func removeParticipant(_ id: String) {
        participants.removeAll { $0.id == id }
        if selectedPerson == id { selectedPerson = participants.first?.id ?? "" }
        for index in draft.items.indices { draft.items[index].allocations.removeAll { $0.memberID == id } }
        if payerID == id { payerID = "self" }
    }
    private func applyReceipt(_ text: String) {
        focusedField = nil
        let lines = ReceiptParser.lines(from: text)
        guard !lines.isEmpty else { receiptMessage = "Menu belum dapat dibaca. Isi manual atau pakai format: Nasi 4 x 25000."; return }
        let retained = draft.items.filter { !$0.name.isEmpty || !$0.unitPrice.isEmpty }
        draft.items = Array((retained + lines).prefix(100))
        receiptMessage = "\(lines.count) menu ditambahkan sebagai draft. Periksa semua angka lalu bagikan ke peserta."
    }
    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { app.errorMessage = "Kamera tidak tersedia. Pilih foto atau tempel teks struk."; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        if status == .authorized { granted = true }
        else if status == .notDetermined { granted = await AVCaptureDevice.requestAccess(for: .video) }
        else { granted = false }
        if granted { showCamera = true } else { app.errorMessage = "Izin kamera diperlukan. Pilih foto atau izinkan Kamera di Pengaturan iOS." }
    }
    private func calculate() async {
        processing = true
        defer { processing = false }
        let requested = draft; let requestedIDs = memberIDs
        do {
            let value = try await app.calculateItemSplit(requested, memberIDs: requestedIDs)
            if requested == draft, requestedIDs == memberIDs { result = value }
        } catch { app.errorMessage = (error as? AppError)?.message ?? "Periksa semua menu, harga, penyesuaian dan jumlah per peserta."
        }
    }
    private func save(_ value: ItemSplitResult) async {
        if let receiptTotal, receiptTotal != Int64(value.total), !mismatchConfirmed { app.errorMessage = "Total pembagian belum sama dengan struk. Periksa biaya atau konfirmasi koreksi."; return }
        do { _ = try ItemSplitCalculator.calculate(draft, memberIDs: memberIDs) } catch { app.errorMessage = "Periksa nama menu, harga dan pemesan setiap menu."; return }
        guard let total = Int64(value.total) else { return }
        let members = participants.enumerated().map { order, person in SplitMember(id: person.id, displayName: person.name, isSelf: person.isSelf, shareAmount: Int64(value.shares[person.id] ?? "0") ?? 0, settledAmount: 0, resolvedAmount: 0, sortOrder: order) }
        let bill = SplitBillDraft(title: title, total: total, categoryID: categoryID, payer: payerID == "self" ? .selfPaid(accountID: accountID) : .other(memberID: payerID), occurredAt: date, note: note.nilIfBlank, members: members, itemSplit: draft)
        let success: Bool
        if let editing { success = await app.updateSplitBill(editing, draft: bill) }
        else { success = await app.createSplitBill(bill, reviewItemID: reviewItemID) }
        if success { onSaved(); dismiss() }
    }
}
