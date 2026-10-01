import SwiftUI

struct ReviewListView: View {
    @Environment(AppModel.self) private var app
    var embedded = false

    var body: some View {
        Group {
            if embedded { reviewContent }
            else { NavigationStack { reviewContent } }
        }
        .safeAreaInset(edge: .bottom) {
            if app.lastRejectedReview != nil {
                HStack { Text("Draft ditolak"); Spacer(); Button("Urungkan") { Task { await app.restoreRejectedReview() } } }
                    .padding().background(.regularMaterial)
                    .task { try? await Task.sleep(for: .seconds(10)); app.clearReviewUndo() }
            }
        }
    }

    private var reviewContent: some View {
            Group {
                if app.snapshot.reviewItems.isEmpty {
                    ContentUnavailableView(
                        "Semua sudah ditinjau",
                        systemImage: "checkmark.circle",
                        description: Text("Bukti impor menunggu pemeriksaan.")
                    )
                } else {
                    List(app.snapshot.reviewItems) { item in
                        NavigationLink { ReviewDetailView(itemID: item.id) } label: {
                            ReviewRow(item: item)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tinjauan").navigationBarTitleDisplayMode(.inline)
            .refreshable { await app.refresh() }
    }
}

private struct ReviewRow: View {
    let item: ReviewItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(Color.danarapiSun, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.merchant.value ?? "Jumlah belum terbaca")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(item.source.title)
                    Text(item.amount.confidence.title)
                    if item.duplicateCandidateID != nil { Label("Mirip", systemImage: "doc.on.doc") }
                }
                .font(.caption)
                .foregroundStyle(Color.danarapiMuted)
            }
            Spacer()
            if let value = item.amount.value, let amount = Int64(value) {
                MoneyText(amount: amount, style: .subheadline.bold())
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch item.source {
        case .qris: "qrcode"
        case .image: "photo"
        case .pdfText: "doc.richtext"
        case .pastedText: "text.quote"
        }
    }
}

struct ReviewDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var amount = ""
    @State private var merchant = ""
    @State private var occurredAt = Date.now
    @State private var accountID = ""
    @State private var categoryID = ""
    @State private var showSplit = false
    @State private var rejectConfirmation = false
    @State private var showReceiptEditor = false
    @State private var confirmMismatch = false
    @State private var showReread = false

    private var item: ReviewItem? { app.snapshot.reviewItems.first(where: { $0.id == itemID }) }
    private var valid: Bool {
        guard let value = Int64(amount), value > 0, value <= Money.maximum else { return false }
        return !accountID.isEmpty && !categoryID.isEmpty
    }

    var body: some View {
        Group {
            if let item {
                Form {
                    Section("Hasil ekstraksi") {
                        HStack {
                            Text("Nominal")
                            Spacer(minLength: 16)
                            Text("Rp").foregroundStyle(Color.danarapiMuted)
                            RupiahTextField("Belum terbaca", text: $amount)
                                .multilineTextAlignment(.trailing).frame(maxWidth: 180)
                                .accessibilityLabel("Nominal hasil ekstraksi")
                        }
                        confidenceRow("Nominal", field: item.amount)
                        TextField("Nama toko", text: $merchant)
                        confidenceRow("Nama toko", field: item.merchant)
                        DatePicker("Tanggal", selection: $occurredAt, displayedComponents: .date)
                        if ImportService.receiptDate(item.date.value) == nil { Label("Tanggal belum terbaca atau belum valid", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(Color.danarapiExpense) }
                    }
                    if let receipt = item.receipt {
                        receiptDetails(receipt)
                        Section {
                            Button("Periksa atau koreksi struk", systemImage: "slider.horizontal.3") { showReceiptEditor = true }
                            Button("Baca ulang", systemImage: "arrow.clockwise") { showReread = true }
                        }
                    } else if let lines = item.receiptLines, !lines.isEmpty {
                        Section("Rincian menu") {
                            ForEach(lines) { line in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(line.name).font(.headline)
                                    Text("\(line.quantity.formatted(.number.locale(Locale(identifier: "id_ID")))) × \(receiptMoney(Int64(line.unitPrice)))").font(.subheadline).foregroundStyle(Color.danarapiMuted)
                                }
                            }
                        }
                    }
                    if let candidate = duplicateCandidate {
                        Section("Kemungkinan duplikat") {
                            Label("Ditemukan transaksi mirip. Periksa sebelum menyimpan.", systemImage: "doc.on.doc")
                                .foregroundStyle(Color.danarapiExpense)
                            TransactionRow(item: candidate)
                            Button("Gabungkan sumber ke transaksi ini") {
                                Task {
                                    if await app.mergeReview(item, into: candidate.id) { dismiss() }
                                }
                            }
                            Button("Bukan duplikat") { Task { _ = await app.clearReviewDuplicate(item) } }
                        }
                    }
                    Section("Catat sebagai pengeluaran") {
                        Picker("Akun", selection: $accountID) {
                            Text("Pilih akun").tag("")
                            ForEach(app.activeAccounts) { Text($0.name).tag($0.id) }
                        }
                        Picker("Kategori", selection: $categoryID) {
                            Text("Pilih kategori").tag("")
                            ForEach(app.expenseCategories.filter { $0.systemKey != "goal" }) { Text($0.name).tag($0.id) }
                        }.disabled(item.source == .qris)
                        if item.source == .qris { Text("QRIS untuk pencatatan, bukan pembayaran.")
                            .font(.footnote)
                            .foregroundStyle(Color.danarapiMuted) }
                        Button("Catat sebagai sudah dibayar") {
                            if item.receipt?.validation.passed == false { confirmMismatch = true }
                            else { Task { await confirm(item) } }
                        }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!valid)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        Button("Jadikan split bill") { showSplit = true }
                            .disabled(Int64(amount) == nil)
                    }
                    Section {
                        if let reference = item.rawReference, !reference.isEmpty {
                            DisclosureGroup("Bukti pembacaan") {
                                Text(reference.replacingOccurrences(of: "Google Gemini", with: "AI").replacingOccurrences(of: "Gemini", with: "AI"))
                                    .font(.caption).foregroundStyle(Color.danarapiMuted).textSelection(.enabled)
                            }
                        }
                        Button("Tolak draft", role: .destructive) { rejectConfirmation = true }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.danarapiCanvas)
                .navigationTitle("Tinjau draft")
                .navigationBarTitleDisplayMode(.inline)
                .task(id: item.id) {
                    if let recovered = ImportService.recoverLocalReview(item), await app.updateReview(recovered) { load(recovered) }
                    else { load(item) }
                }
                .sheet(isPresented: $showSplit) {
                    NavigationStack {
                        ItemSplitFormView(seedTitle: merchant, receiptLines: item.receiptLines ?? [], receipt: item.receipt, reviewItemID: item.id) {
                            dismiss()
                        }
                    }
                }
                .sheet(isPresented: $showReceiptEditor) {
                    if let receipt = item.receipt {
                        ReceiptScanReviewSheet(initial: receipt, images: []) { corrected in
                            Task {
                                let updated = ImportService.reviewFromReceipt(corrected, source: item.source, existing: item)
                                if await app.updateReview(updated) { load(updated); showReceiptEditor = false }
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $showReread) {
                    ScanHubView(existingReviewID: item.id, onReread: { if let updated = self.item { load(updated) } })
                }
                .confirmationDialog("Angka struk belum cocok. Sudah memeriksa nominal yang akan dicatat?", isPresented: $confirmMismatch, titleVisibility: .visible) {
                    Button("Catat nominal yang sudah diperiksa") { Task { await confirm(item) } }
                    Button("Periksa lagi", role: .cancel) {}
                }
                .confirmationDialog("Tolak hasil ini?", isPresented: $rejectConfirmation, titleVisibility: .visible) {
                    Button("Tolak", role: .destructive) { Task { await app.rejectReview(item); dismiss() } }
                    Button("Batal", role: .cancel) {}
                } message: {
                    Text("Bukti belum memengaruhi saldo. Penolakan dapat diurungkan.")
                }
            } else {
                ContentUnavailableView("Draft tidak tersedia", systemImage: "tray")
            }
        }
    }

    private var duplicateCandidate: FinanceTransaction? {
        guard let id = item?.duplicateCandidateID else { return nil }
        return app.snapshot.transactions.first(where: { $0.id == id })
    }

    private func confidenceRow(_ label: String, field: ExtractedField) -> some View {
        HStack {
            Label(label, systemImage: field.confidence == .low ? "exclamationmark.triangle.fill" : "checkmark.circle")
            Spacer()
            Text("Keyakinan \(field.confidence.title.lowercased())")
        }
        .font(.caption)
        .foregroundStyle(field.confidence == .low ? Color.danarapiExpense : Color.danarapiMuted)
    }

    private func load(_ item: ReviewItem) {
        amount = item.amount.value ?? ""
        merchant = item.merchant.value ?? ""
        occurredAt = ImportService.receiptDate(item.date.value ?? item.receipt?.date) ?? item.createdAt
        accountID = app.activeAccounts.first?.id ?? ""
        categoryID = item.source == .qris ? app.expenseCategories.first(where: { $0.systemKey == "qris" })?.id ?? "" : app.expenseCategories.first(where: { $0.systemKey != "goal" })?.id ?? ""
    }

    private func receiptMoney(_ amount: Int64?) -> String {
        guard let amount else { return "Belum terbaca" }
        return "Rp \(amount.formatted(.number.locale(Locale(identifier: "id_ID"))))"
    }

    @ViewBuilder private func receiptDetails(_ receipt: ScannedReceipt) -> some View {
        Section("Rincian struk · \(receipt.items.count) barang / menu") {
            ForEach(receipt.items.indices, id: \.self) { index in
                let line = receipt.items[index]
                VStack(alignment: .leading, spacing: 10) {
                    Text(line.name.isEmpty ? "Nama belum terbaca" : line.name).font(.headline)
                    if let note = line.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(Color.danarapiMuted) }
                    HStack { Text("Jumlah").foregroundStyle(Color.danarapiMuted); Spacer(); Text(line.qty.formatted(.number.locale(Locale(identifier: "id_ID")))) }
                    HStack { Text("Harga satuan").foregroundStyle(Color.danarapiMuted); Spacer(); Text(receiptMoney(line.unitPrice)) }
                    HStack { Text("Total tercetak").foregroundStyle(Color.danarapiMuted); Spacer(); Text(receiptMoney(line.lineTotal)).fontWeight(.semibold) }
                    if receipt.validation.badRows.contains(index) { Label("Perlu diperiksa", systemImage: "exclamationmark.triangle").font(.caption.weight(.medium)).foregroundStyle(Color.danarapiExpense) }
                }
                .font(.subheadline).monospacedDigit().padding(.vertical, 6)
                .listRowBackground(receipt.validation.badRows.contains(index) ? Color.danarapiSun : Color.danarapiSurface)
            }
        }
        Section("Ringkasan struk") {
            receiptCost("Subtotal", receipt.subtotal)
            receiptCost("Service", receipt.serviceCharge)
            receiptCost("Pajak", receipt.tax)
            receiptCost("Diskon", receipt.discount)
            receiptCost("Pembulatan", receipt.rounding)
            receiptCost("Total struk", receipt.grandTotal, emphasized: true)
            if receipt.taxIncludedInPrice { Text("Harga termasuk pajak dan service").font(.caption).foregroundStyle(Color.danarapiMuted) }
        }
    }

    private func receiptCost(_ label: String, _ amount: Int64?, emphasized: Bool = false) -> some View {
        HStack { Text(label); Spacer(minLength: 12); Text(receiptMoney(amount)).monospacedDigit() }
            .font(emphasized ? .body.weight(.semibold) : .subheadline)
    }

    private func confirm(_ item: ReviewItem) async {
        guard let value = Int64(amount) else { return }
        let draft = TransactionDraft(
            id: nil,
            kind: .expense,
            amount: value,
            accountID: accountID,
            categoryID: categoryID,
            occurredAt: occurredAt,
            merchant: merchant.nilIfBlank,
            note: "Draft dari \(item.source.title)",
            source: item.source == .qris ? "qris" : "review",
            expectedVersion: nil
        )
        if await app.confirmReview(item, transaction: draft) { dismiss() }
    }
}
