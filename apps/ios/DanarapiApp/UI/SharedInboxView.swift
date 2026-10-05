import QuickLook
import SwiftUI

private struct PreparedSharedProof {
    let record: SharedInboxRecord
    let review: ReviewItem
    let proof: BankProof?
    let error: String?
}

struct SharedInboxView: View {
    @Environment(AppModel.self) private var app
    @State private var records: [SharedInboxRecord] = []
    @State private var error: String?
    @State private var deleting: SharedInboxRecord?
    @State private var openingID: String?
    @State private var openingTask: Task<Void, Never>?
    @State private var preparedProof: PreparedSharedProof?

    var body: some View {
        List {
            Section {
                Label("Bukti dari aplikasi lain", systemImage: "tray.and.arrow.down.fill").font(.headline)
                Text("Bukti tersimpan khusus untuk akun ini. Periksa draft sebelum mencatat; belum ada perubahan saldo.").font(.subheadline).foregroundStyle(Color.danarapiMuted)
                if app.mode != .authenticated { Text("Masuk ke akun nyata untuk menyimpan draft. Mode Demo tidak menerima bukti pribadi.").font(.footnote).foregroundStyle(Color.danarapiExpense) }
            }
            if let error { Section { Text(error).foregroundStyle(Color.danarapiExpense); Button("Coba lagi") { reload() } } }
            if records.isEmpty && error == nil {
                Section { Text("Belum ada bukti Share. Dari aplikasi bank, Foto, atau Files, pilih Bagikan → Danarapi → Simpan draft.").foregroundStyle(Color.danarapiMuted) }
            }
            ForEach([false, true], id: \.self) { imported in
                let values = records.filter { $0.imported == imported }
                if !values.isEmpty {
                    Section(imported ? "Salinan bukti yang sudah diimpor" : "Draft lokal") {
                        ForEach(values) { record in
                            Button {
                                openingTask = Task { await open(record) }
                            } label: {
                                HStack(spacing: 12) {
                                    SymbolBadge(symbol: record.mime == "application/pdf" ? "doc.richtext" : record.mime == "text/plain" ? "text.quote" : "photo", background: .danarapiMint, size: 40)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text(record.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(Color.danarapiMuted)
                                        Text(openingID == record.id ? "Menyiapkan draft…" : record.imported ? "Draft telah diimpor" : record.ownerID == nil ? "Belum terikat akun" : "Tersimpan untuk akun ini · dapat dicoba lagi").font(.caption).foregroundStyle(Color.danarapiMuted)
                                    }
                                    Spacer(minLength: 8)
                                    if openingID == record.id { ProgressView().accessibilityLabel("Menyiapkan draft") }
                                    else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.danarapiMuted) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(openingID != nil)
                            .swipeActions { Button("Hapus lokal", role: .destructive) { deleting = record } }
                        }
                    }
                }
            }
        }
        .danarapiListSurface()
        .navigationTitle("Bukti dari Share").navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .refreshable { reload() }
        .navigationDestination(isPresented: Binding(get: { preparedProof != nil }, set: { if !$0 { preparedProof = nil } })) {
            if let preparedProof { SharedProofDetailView(prepared: preparedProof) }
        }
        .onDisappear { openingTask?.cancel() }
        .onChange(of: preparedProof == nil) { _, closed in if closed { reload() } }
        .onChange(of: app.ownerID) { _, _ in openingTask?.cancel(); preparedProof = nil; reload() }
        .onChange(of: app.isLocked) { _, locked in if locked { openingTask?.cancel(); preparedProof = nil } }
        .confirmationDialog("Hapus salinan lokal bukti?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Hapus lokal", role: .destructive) {
                guard let record = deleting else { return }
                do { try app.sharedInbox?.remove(record.id, ownerID: app.ownerID); reload() }
                catch { self.error = error.localizedDescription }
                deleting = nil
            }
        } message: { Text("Draft yang sudah diunggah tetap berada di akun. Bukti yang belum diimpor akan dihapus dari perangkat.") }
    }

    private func open(_ record: SharedInboxRecord) async {
        guard openingID == nil, !app.isLocked, app.mode == .authenticated else { return }
        let owner = app.ownerID
        openingID = record.id; error = nil
        defer { openingID = nil; openingTask = nil }
        do {
            guard let inbox = app.sharedInbox,
                  let current = try inbox.records(ownerID: owner).first(where: { $0.id == record.id }) else { throw SharedInboxError.unavailable }
            let data = try inbox.data(for: current.id, ownerID: owner)
            var proof = current.aiProof.flatMap { try? JSONDecoder().decode(BankProof.self, from: $0) }
            var issue: String?
            if proof == nil, !current.imported, app.mode == .authenticated, app.network.isOnline {
                do { proof = try await app.readSharedProofWithAI(current, retry: current.ownerID != nil) }
                catch {
                    guard !Task.isCancelled, owner == app.ownerID, !app.isLocked else { return }
                    issue = ((error as? AppError)?.message ?? error.localizedDescription) + " Isi manual tetap tersedia."
                }
            }
            let review: ReviewItem
            if current.imported, let saved = app.snapshot.reviewItems.first(where: { $0.matchesID(current.id) }) { review = saved }
            else if let proof { review = proof.review(current, timezone: app.timezone) }
            else { review = await SharedReceiptReader.read(current, data: data) }
            guard !Task.isCancelled, owner == app.ownerID, !app.isLocked else { return }
            preparedProof = PreparedSharedProof(record: current, review: review, proof: proof, error: issue)
        } catch {
            guard !Task.isCancelled, owner == app.ownerID, !app.isLocked else { return }
            self.error = (error as? AppError)?.message ?? error.localizedDescription
        }
    }

    private func reload() {
        guard !app.isLocked, app.mode == .authenticated else { records = []; return }
        do {
            guard let inbox = app.sharedInbox else { throw SharedInboxError.unavailable }
            records = try inbox.records(ownerID: app.ownerID)
            error = nil; app.refreshSharedInboxCount()
        } catch { records = []; self.error = (error as? AppError)?.message ?? error.localizedDescription }
    }
}

private struct SharedProofDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let record: SharedInboxRecord
    @State private var review: ReviewItem?
    @State private var saving = false
    @State private var imported = false
    @State private var error: String?
    @State private var amount = ""
    @State private var merchant = ""
    @State private var occurredAt = Date.now
    @State private var dateConfirmed = false
    @State private var confirmAccount = false
    @State private var deleteConfirmation = false
    @State private var aiProof: BankProof?
    @State private var readingAI = false
    @State private var aiTask: Task<Void, Never>?
    @State private var aiAttempted = false

    init(prepared: PreparedSharedProof) {
        record = prepared.record
        _review = State(initialValue: prepared.review)
        _aiProof = State(initialValue: prepared.proof)
        _error = State(initialValue: prepared.error)
        _imported = State(initialValue: prepared.record.imported)
        _amount = State(initialValue: prepared.review.amount.value ?? "")
        _merchant = State(initialValue: prepared.review.merchant.value ?? "")
        let date = ImportService.receiptDate(prepared.review.date.value)
        _occurredAt = State(initialValue: date ?? .now)
        _dateConfirmed = State(initialValue: date != nil)
        _aiAttempted = State(initialValue: prepared.error != nil)
    }

    var body: some View {
        Form {
            if readingAI {
                Section { ProgressView("Menyiapkan draft…").accessibilityIdentifier("share.aiProgress") }
            } else {
                Section("Bukti asli") {
                    Text(record.name).font(.headline)
                    SharedOriginalButton(itemID: record.id)
                    Text("Periksa rincian dengan bukti asli sebelum mencatat.").font(.caption).foregroundStyle(Color.danarapiMuted)
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(Color.danarapiExpense)
                        if !record.imported && !imported {
                            Button("Coba lagi") { aiTask = Task { await readAI() } }
                                .disabled(readingAI || saving || app.mode != .authenticated || !app.network.isOnline || app.isLocked)
                        }
                    }
                }
                if let review {
                    if let aiProof {
                        Section("Rincian dari bukti") {
                            if let provider = aiProof.provider { LabeledContent("Penyedia", value: provider) }
                            if let recipient = aiProof.recipient { LabeledContent("Penerima", value: recipient) }
                            LabeledContent("Status", value: aiProof.statusLabel)
                            LabeledContent("Jenis pada bukti", value: aiProof.typeLabel)
                            if let fee = aiProof.fee { LabeledContent("Biaya admin") { MoneyText(amount: fee, style: .subheadline) } }
                            if let total = aiProof.total { LabeledContent("Total debit") { MoneyText(amount: total, style: .subheadline) } }
                            if let reference = aiProof.reference { LabeledContent("Referensi", value: reference).font(.caption).textSelection(.enabled) }
                            if aiProof.time == nil { Text("Jam belum terbaca. Periksa sebelum menyimpan.").font(.caption).foregroundStyle(Color.danarapiExpense) }
                            ForEach(aiProof.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Color.danarapiExpense) }
                        }
                    }
                    Section("Periksa hasil pembacaan") {
                        HStack {
                            Text("Nominal"); Spacer(minLength: 12)
                            Text("Rp").foregroundStyle(Color.danarapiMuted)
                            RupiahTextField("Belum terbaca", text: $amount).multilineTextAlignment(.trailing).frame(maxWidth: 180).accessibilityLabel("Nominal bukti Share")
                        }
                        TextField("Nama penerima / merchant", text: $merchant).accessibilityIdentifier("share.merchant")
                        Toggle("Tanggal sudah diperiksa", isOn: $dateConfirmed)
                        if dateConfirmed { DatePicker("Tanggal", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute]) }
                        Text("Nominal transaksi terpisah dari biaya admin. Jangan gunakan saldo akhir sebagai nominal.").font(.footnote).foregroundStyle(Color.danarapiMuted)
                    }.disabled(imported || record.imported || saving || readingAI)
                    Section {
                        DisclosureGroup("Bukti pembacaan") { Text(review.rawReference ?? "Belum terbaca").font(.caption).textSelection(.enabled) }
                    }
                    if imported || record.imported {
                        Section {
                            Text("Draft sudah diimpor ke akun. Saldo berubah setelah transaksi dikonfirmasi.").font(.subheadline)
                            if app.snapshot.reviewItems.contains(where: { $0.matchesID(record.id) }) {
                                NavigationLink("Tinjau draft transaksi") { ReviewDetailView(itemID: record.id) }
                            } else { Text("Draft mungkin sudah selesai atau ditolak. Periksa daftar transaksi dan Tinjauan akun ini.").font(.caption).foregroundStyle(Color.danarapiMuted) }
                        }
                    } else {
                        Section {
                            Text("Akun tujuan: \(app.session?.email ?? "Belum masuk")").font(.subheadline.weight(.semibold))
                            Button("Simpan ke draft akun ini") { confirmAccount = true }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(app.mode != .authenticated || !app.network.isOnline || app.isLocked || app.isLoading || saving || readingAI || !validAmount)
                                .accessibilityIdentifier("share.import")
                        } footer: { Text("Simpan mengunggah bukti ke akun ini. Draft tidak otomatis menjadi transaksi.") }
                    }
                }
            }
            Section {
                Button("Hapus salinan lokal", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
                    .disabled(saving || readingAI || app.isLocked || record.ownerID != app.ownerID)
            }
        }
        .danarapiListSurface()
        .navigationTitle("Tinjau bukti Share").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Hapus salinan lokal bukti?", isPresented: $deleteConfirmation, titleVisibility: .visible) {
            Button("Hapus lokal", role: .destructive) {
                do {
                    guard let inbox = app.sharedInbox, record.ownerID == app.ownerID else { throw SharedInboxError.unavailable }
                    try inbox.remove(record.id, ownerID: app.ownerID)
                    app.refreshSharedInboxCount(); dismiss()
                } catch { self.error = error.localizedDescription }
            }
        } message: { Text("Bukti lokal dihapus dari perangkat. Draft yang sudah diunggah tetap berada di Tinjauan dan dapat dihapus dari sana.") }
        .onDisappear { aiTask?.cancel() }
        .onChange(of: app.network.isOnline) { _, online in
            if online, review != nil, aiProof == nil, !readingAI, !saving,
               !record.imported, !imported, app.mode == .authenticated, !app.isLocked {
                aiTask = Task { await readAI() }
            }
        }
        .onChange(of: app.ownerID) { _, _ in aiTask?.cancel(); review = nil; aiProof = nil; amount = ""; merchant = ""; dateConfirmed = false }
        .onChange(of: app.isLocked) { _, locked in if locked { aiTask?.cancel() } }
        .confirmationDialog("Simpan draft ke \(app.session?.email ?? "akun ini")?", isPresented: $confirmAccount, titleVisibility: .visible) {
            Button("Simpan draft") { Task { await save() } }
        } message: { Text("Bukti asli diunggah ke akun ini. Nominal, jenis transaksi, kategori, dan akun bank tetap diperiksa sebelum pencatatan.") }
    }

    private var validAmount: Bool { amount.isEmpty || Int64(amount).map { $0 > 0 && $0 <= Money.maximum } == true }
    private func readAI() async {
        guard !readingAI, !saving, let previous = review else { return }
        let owner = app.ownerID
        readingAI = true; error = nil
        defer { readingAI = false; aiTask = nil }
        do {
            let retry = aiAttempted || aiProof != nil || record.ownerID != nil
            aiAttempted = true
            let proof = try await app.readSharedProofWithAI(record, retry: retry)
            guard !Task.isCancelled, !app.isLocked, owner == app.ownerID else { return }
            let value = proof.review(record, timezone: app.timezone)
            // Keep fields the user already corrected, including intentional clearing.
            if amount == (previous.amount.value ?? "") { amount = value.amount.value ?? "" }
            if merchant == (previous.merchant.value ?? "") { merchant = value.merchant.value ?? "" }
            let previousDate = ImportService.receiptDate(previous.date.value)
            if dateConfirmed == (previousDate != nil), previousDate == nil || occurredAt == previousDate {
                if let date = ImportService.receiptDate(value.date.value) { occurredAt = date; dateConfirmed = true }
                else { dateConfirmed = false }
            }
            aiProof = proof; review = value
        } catch {
            guard !Task.isCancelled, owner == app.ownerID, !app.isLocked else { return }
            self.error = ((error as? AppError)?.message ?? error.localizedDescription) + " Hasil lokal dan koreksi tetap tersedia."
        }
    }
    private func save() async {
        guard var value = review, !saving else { return }
        saving = true; defer { saving = false }
        value.amount.value = amount.nilIfBlank
        value.merchant.value = merchant.nilIfBlank
        value.date.value = dateConfirmed ? ISO8601DateFormatter().string(from: occurredAt) : nil
        imported = await app.importSharedProof(record, review: value)
    }
}

struct SharedOriginalButton: View {
    @Environment(AppModel.self) private var app
    let itemID: String
    @State private var previewURL: URL?
    @State private var text: String?
    @State private var error: String?

    var body: some View {
        Button("Lihat bukti asli", systemImage: "doc.viewfinder") { preview() }
            .quickLookPreview($previewURL)
            .sheet(isPresented: Binding(get: { text != nil }, set: { if !$0 { text = nil } })) {
                NavigationStack {
                    ScrollView { Text(text ?? "").font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                        .navigationTitle("Bukti teks").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { text = nil } } }
                }
            }
            .alert("Bukti lokal", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Tutup", role: .cancel) {} } message: { Text(error ?? "") }
            .onChange(of: previewURL) { previous, current in
                if current == nil, let previous { try? FileManager.default.removeItem(at: previous) }
            }
            .onChange(of: app.isLocked) { _, locked in if locked { previewURL = nil; text = nil } }
            .onChange(of: app.privacyCoverVisible) { _, covered in if covered { previewURL = nil; text = nil } }
            .onChange(of: app.ownerID) { _, _ in previewURL = nil; text = nil }
            .onDisappear { if let previewURL { try? FileManager.default.removeItem(at: previewURL) } }
    }

    private func preview() {
        do {
            guard !app.isLocked, app.mode == .authenticated, let inbox = app.sharedInbox,
                  let record = try inbox.records(ownerID: app.ownerID).first(where: { $0.id == itemID }) else { throw AppError.validation("Salinan lokal tidak tersedia di perangkat ini. Bukti mungkin sudah dihapus dari kotak Share.") }
            let data = try inbox.data(for: itemID, ownerID: app.ownerID)
            if record.mime == "text/plain" { text = String(data: data, encoding: .utf8); return }
            let ext = ["application/pdf": "pdf", "image/jpeg": "jpg", "image/png": "png", "image/heic": "heic"][record.mime] ?? "bin"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(itemID).\(ext)")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            previewURL = url
        } catch { self.error = error.localizedDescription }
    }
}
