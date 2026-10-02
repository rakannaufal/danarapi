import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showDelete = false
    @State private var showLogout = false
    @State private var discardMutationID: String?

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                if app.mode == .demo {
                    Section { Label("Demo · data contoh", systemImage: "sparkles") }
                }
                Section("Tampilan") {
                    Picker("Tema", selection: $app.theme) { ForEach(ThemePreference.allCases) { Text($0.title).tag($0) } }
                    Toggle("Sembunyikan nominal", isOn: $app.hideAmounts)
                    Toggle("Kunci saat aplikasi ditinggalkan", isOn: $app.appLockEnabled)
                        .disabled(app.mode == .demo || !AppLockService.isAvailable)
                    InformationDisclosure(title: "Tentang pengunci", message: "Gunakan Face ID, Touch ID, atau kode perangkat. Pengunci melindungi tampilan perangkat, bukan menggantikan keamanan akun.")
                }
                Section("Kelola") {
                    NavigationLink("Akun keuangan") { AccountManagementView() }
                    NavigationLink("Kategori") { CategoryManagementView() }
                    NavigationLink("Aturan merchant") { MerchantRulesView() }
                    NavigationLink("Tagihan bersama") { SplitBillListView() }
                }
                Section("Data") {
                    Button { Task { await export() } } label: { Label("Ekspor data lengkap", systemImage: "square.and.arrow.up") }
                    Text("Ekspor berisi informasi sensitif. Periksa tujuan berbagi sebelum melanjutkan.")
                        .font(.caption).foregroundStyle(Color.danarapiMuted)
                    if app.mode == .demo {
                        Button("Reset data contoh", role: .destructive) { Task { await app.resetDemo() } }
                    } else {
                        Button("Hapus akun", role: .destructive) { showDelete = true }
                    }
                }
                if app.mode == .authenticated {
                    Section("Perubahan perangkat") {
                        LabeledContent("Belum tersinkron", value: "\(app.pendingOutboxCount)")
                        Button(app.isSyncing ? "Menyinkronkan…" : "Sinkronkan sekarang") { Task { await app.syncOutbox(forceRetry: true) } }
                            .disabled(!app.network.isOnline || app.isSyncing)
                        ForEach(app.outboxChanges, id: \.mutationID) { change in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(change.operation.replacingOccurrences(of: "_", with: " ")).font(.headline)
                                Text(change.status == "conflict" ? "Versi server berubah; tidak ditimpa." : "Belum diterima server.")
                                    .font(.subheadline).foregroundStyle(Color.danarapiMuted)
                                if let code = change.lastErrorCode { Text(code).font(.caption).foregroundStyle(Color.danarapiExpense) }
                                NavigationLink("Bandingkan dengan versi server") { OutboxChangeView(change: change) }
                                Button("Buang perubahan ini, gunakan versi server", role: .destructive) { discardMutationID = change.mutationID }
                                    .disabled(!app.network.isOnline || app.isSyncing)
                            }
                        }
                        Text("Saldo dan laporan tetap merupakan versi server terakhir. Catatan belum sinkron tidak dihitung sebagai saldo terverifikasi.")
                            .font(.caption).foregroundStyle(Color.danarapiMuted)
                    }
                }
                Section("Privasi") {
                    InformationDisclosure(title: "Pemrosesan struk", message: "Foto dan halaman PDF struk dikirim ke layanan AI eksternal saat Anda memilih membaca struk. Penggunaan dan penyimpanan oleh penyedia mengikuti ketentuan layanannya; layanan gratis dapat menggunakan data untuk peningkatan model. Hindari data sensitif. QRIS dan teks diproses lokal. Hasil ekstraksi tetap draft sampai Anda mengonfirmasi.")
                    Label("Danarapi tidak memproses pembayaran", systemImage: "shield.lefthalf.filled")
                    Text("Saldo adalah catatan Anda. Bukti impor perlu diperiksa sebelum disimpan.")
                        .font(.caption).foregroundStyle(Color.danarapiMuted)
                    Picker("Zona waktu", selection: Binding(get: { app.timezone }, set: { value in Task { _ = await app.updateTimezone(value) } })) { ForEach(["Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura", "UTC"], id: \.self) { Text($0).tag($0) } }
                }
                Section("Tentang & bantuan") { ForEach(ProductCatalog.links, id: \.0) { identifier, title in NavigationLink(title) { ProductPageView(pageID: identifier) } } }
                Section {
                    Button(app.mode == .demo ? "Keluar dari Demo" : "Keluar akun", role: .destructive) { showLogout = true }
                }
            }
            .navigationTitle("Pengaturan").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showShare) { if let exportURL { ShareSheet(items: [exportURL]) } }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
            .confirmationDialog("Buang perubahan perangkat ini?", isPresented: Binding(get: { discardMutationID != nil }, set: { if !$0 { discardMutationID = nil } }), titleVisibility: .visible) {
                if let id = discardMutationID {
                    Button("Buang dan muat versi server", role: .destructive) { Task { _ = await app.discardOutboxChange(id) } }
                }
                Button("Batal", role: .cancel) {}
            } message: { Text("Draft lokal akan dihapus permanen. Perubahan yang sudah diterima server tidak dibatalkan. Setelah memuat versi server, buat ulang koreksi bila diperlukan.") }
            .confirmationDialog("Keluar dari Danarapi?", isPresented: $showLogout, titleVisibility: .visible) {
                if app.pendingOutboxCount > 0 && app.network.isOnline {
                    Button("Sinkronkan dulu") { Task { await app.syncOutbox() } }
                }
                Button("Keluar", role: .destructive) { Task { _ = await app.logout(discardPending: false) } }
                if app.pendingOutboxCount > 0 { Button("Buang perubahan perangkat lalu keluar", role: .destructive) { Task { _ = await app.logout(discardPending: true) } } }
                Button("Batal", role: .cancel) {}
            } message: {
                Text(app.pendingOutboxCount > 0 ? "Ada perubahan offline yang belum tersinkron." : "Sesi aman dan cache lokal akan dihapus.")
            }
        }
    }

    private func export() async {
        if let url = await app.exportArchive() { exportURL = url; showShare = true }
    }
}

private struct MerchantRulesView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: MerchantRule?
    @State private var adding = false

    var body: some View {
        List {
            if app.snapshot.merchantRules.isEmpty {
                ContentUnavailableView("Belum ada aturan", systemImage: "wand.and.stars", description: Text("Aturan hanya menyarankan kategori. Pilihan tetap dapat diubah sebelum menyimpan."))
            } else {
                ForEach(app.snapshot.merchantRules) { rule in
                    Button { editing = rule } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.normalizedPattern).font(.headline)
                                Text("\(rule.matchType.title) · \(category(rule.categoryID)) · prioritas \(rule.priority)").font(.caption).foregroundStyle(Color.danarapiMuted)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(Color.danarapiMuted)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Aturan merchant")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Tambah aturan merchant") } }
        .sheet(isPresented: $adding) { MerchantRuleEditor(rule: nil) }
        .sheet(item: $editing) { MerchantRuleEditor(rule: $0) }
    }

    private func category(_ id: String) -> String { app.snapshot.categories.first(where: { $0.id == id })?.name ?? "Kategori" }
}

private struct MerchantRuleEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let rule: MerchantRule?
    @State private var pattern = ""
    @State private var matchType: MerchantMatchType = .contains
    @State private var categoryID = ""
    @State private var priority = 0
    @State private var deleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nama atau pola merchant", text: $pattern)
                    Picker("Pencocokan", selection: $matchType) { ForEach(MerchantMatchType.allCases) { Text($0.title).tag($0) } }
                    Picker("Kategori saran", selection: $categoryID) { ForEach(app.expenseCategories) { Text($0.name).tag($0.id) } }
                    Stepper("Prioritas \(priority)", value: $priority, in: 0...999)
                    Text("Pola dinormalisasi tanpa regex. Aturan tidak pernah menyimpan transaksi otomatis.").font(.caption).foregroundStyle(Color.danarapiMuted)
                }
                Section {
                    Button("Simpan aturan") { Task { await save() } }.buttonStyle(PrimaryButtonStyle()).disabled(MerchantRule.normalize(pattern).isEmpty || categoryID.isEmpty).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if rule != nil { Section { Button("Hapus aturan", role: .destructive) { deleteConfirmation = true } } }
            }
            .navigationTitle(rule == nil ? "Tambah aturan" : "Ubah aturan")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
            .onAppear {
                pattern = rule?.normalizedPattern ?? ""
                matchType = rule?.matchType ?? .contains
                categoryID = rule?.categoryID ?? app.expenseCategories.first?.id ?? ""
                priority = rule?.priority ?? 0
            }
            .confirmationDialog("Hapus aturan merchant?", isPresented: $deleteConfirmation) {
                Button("Hapus", role: .destructive) { Task { if let rule, await app.deleteMerchantRule(rule) { dismiss() } } }
                Button("Batal", role: .cancel) {}
            }
        }
    }

    private func save() async {
        let value = MerchantRule(
            id: rule?.id ?? UUID().uuidString,
            matchType: matchType,
            normalizedPattern: MerchantRule.normalize(pattern),
            categoryID: categoryID,
            priority: priority,
            version: rule?.version ?? 0
        )
        if await app.saveMerchantRule(value) { dismiss() }
    }
}

struct AccountManagementView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: FinancialAccount?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(app.snapshot.accounts) { account in
                Button { editing = account } label: {
                    HStack {
                        Image(systemName: icon(account.kind)).frame(width: 36, height: 36).background(Color.danarapiSky, in: Circle())
                        VStack(alignment: .leading) { Text(account.name).font(.headline); Text(account.kind.title).font(.caption).foregroundStyle(Color.danarapiMuted) }
                        Spacer(); MoneyText(amount: account.balance, style: .subheadline.bold())
                    }
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle("Akun")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Tambah akun") } }
        .sheet(isPresented: $adding) { AccountEditorView(account: nil) }
        .sheet(item: $editing) { AccountEditorView(account: $0) }
    }

    private func icon(_ kind: AccountKind) -> String {
        switch kind { case .cash: "banknote"; case .bank: "building.columns"; case .ewallet: "iphone"; case .other: "wallet.pass" }
    }
}

private struct AccountEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let account: FinancialAccount?
    @State private var name = ""
    @State private var kind: AccountKind = .cash
    @State private var openingBalance = "0"
    @State private var openedAt = Date.now
    @State private var archiveConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nama akun", text: $name)
                    Picker("Jenis", selection: $kind) { ForEach(AccountKind.allCases) { Text($0.title).tag($0) } }
                    MoneyField(title: "Saldo awal", value: $openingBalance).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).disabled(account != nil && hasActivity)
                    DatePicker("Tanggal pembukaan", selection: $openedAt, displayedComponents: .date).disabled(account != nil && hasActivity)
                    if account != nil && hasActivity { Text("Akun sudah memiliki aktivitas. Gunakan penyesuaian saldo untuk koreksi berikutnya.").font(.caption).foregroundStyle(Color.danarapiMuted) }
                }
                Section {
                    Button("Simpan akun") { Task { await save() } }.buttonStyle(PrimaryButtonStyle()).disabled(name.nilIfBlank == nil || Int64(openingBalance) == nil).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                if account != nil {
                    Section { Button("Arsipkan akun", role: .destructive) { archiveConfirmation = true } }
                }
            }
            .navigationTitle(account == nil ? "Tambah akun" : "Ubah akun")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
            .onAppear {
                name = account?.name ?? ""
                kind = account?.kind ?? .cash
                openingBalance = String(account?.openingBalance ?? 0)
                openedAt = account?.openedAt ?? .now
            }
            .confirmationDialog("Arsipkan akun?", isPresented: $archiveConfirmation) {
                Button("Arsipkan", role: .destructive) { Task { if let account, await app.archiveAccount(account) { dismiss() } } }
                Button("Batal", role: .cancel) {}
            } message: { Text("Riwayat tetap tersimpan. Akun tidak dapat dipakai untuk catatan baru.") }
        }
    }

    private func save() async {
        guard let balance = Int64(openingBalance), let cleanName = name.nilIfBlank else { return }
        if var account {
            account.name = cleanName
            account.kind = kind
            if !hasActivity {
                account.openingBalance = balance
                account.openedAt = openedAt
            }
            if await app.updateAccount(account) { dismiss() }
        } else {
            if await app.createAccount(AccountDraft(name: cleanName, kind: kind, openingBalance: balance, openedAt: openedAt)) { dismiss() }
        }
    }

    private var hasActivity: Bool {
        guard let account else { return false }
        return app.snapshot.transactions.contains { $0.accountID == account.id }
            || app.snapshot.transfers.contains { $0.fromAccountID == account.id || $0.toAccountID == account.id }
            || app.snapshot.splitBills.contains { bill in
                if case let .selfPaid(accountID) = bill.payer, accountID == account.id { return true }
                return bill.settlements.contains { $0.accountID == account.id && !$0.reversed }
            }
    }
}

private struct CategoryManagementView: View {
    @Environment(AppModel.self) private var app
    @State private var kind: TransactionKind = .expense
    @State private var newName = ""
    @State private var editing: Category?

    private var rows: [Category] { app.snapshot.categories.filter { $0.kind == kind && !$0.archived } }

    var body: some View {
        List {
            Section {
                Picker("Jenis", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            }
            Section("Kategori") {
                ForEach(rows) { category in
                    HStack {
                        Image(systemName: kind == .expense ? "tag" : "arrow.down.left").frame(width: 34, height: 34).background(Color.danarapiLavender, in: Circle())
                        Button(category.name) { editing = category }.foregroundStyle(Color.danarapiInk)
                        Spacer()
                        Button("Arsipkan", role: .destructive) { Task { await app.archiveCategory(category) } }.font(.caption)
                    }.frame(minHeight: 44)
                }
            }
            Section("Tambah") {
                TextField("Nama kategori", text: $newName)
                Button("Tambah kategori") { Task { guard let name = newName.nilIfBlank else { return }; if await app.createCategory(name: name, kind: kind) { newName = "" } } }.disabled(newName.nilIfBlank == nil)
            }
        }
        .navigationTitle("Kategori")
        .sheet(item: $editing) { CategoryEditorView(category: $0) }
    }
}

private struct CategoryEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let category: Category
    @State private var name = ""
    @State private var sortOrder = 0
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nama kategori", text: $name)
                    LabeledContent("Jenis", value: category.kind.title)
                    Stepper("Urutan \(sortOrder)", value: $sortOrder, in: 0...999)
                }
                Section {
                    Button("Simpan kategori") {
                        Task {
                            guard let clean = name.nilIfBlank else { return }
                            var value = category
                            value.name = clean
                            value.sortOrder = sortOrder
                            if await app.updateCategory(value) { dismiss() }
                        }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(name.nilIfBlank == nil).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Ubah kategori")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
            .onAppear { name = category.name; sortOrder = category.sortOrder }
        }
    }
}

private struct SplitBillListView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        List(app.snapshot.splitBills) { bill in
            NavigationLink { SplitBillDetailView(billID: bill.id) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(bill.title).font(.headline); Spacer(); Text(bill.status.title).font(.caption) }
                    HStack { Text("Total \(bill.total.idr) · Bagian saya \(bill.selfShare.idr)"); Spacer(); Text("Sisa \(bill.remainingAmount.idr)") }.font(.caption).foregroundStyle(Color.danarapiMuted)
                }
            }
        }.navigationTitle("Tagihan bersama")
    }
}

private struct DeleteAccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var authenticatedAt: Date?
    @State private var confirmed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Data Anda akan dihapus permanen setelah proses selesai.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.danarapiExpense)
                    Text("Transaksi, akun, kategori, tagihan bersama, lampiran, anggaran, sesi, dan cache perangkat akan dihapus. Retensi cadangan mengikuti konfigurasi backend yang berlaku.")
                        .font(.subheadline).foregroundStyle(Color.danarapiMuted)
                }
                Section("Autentikasi ulang") {
                    Button("Konfirmasi Google") { Task { authenticatedAt = await app.signIn(provider: "google") ? .now : nil } }.disabled(app.isLoading)
                    if authenticatedAt != nil { Label("Akun dikonfirmasi", systemImage: "checkmark.circle").foregroundStyle(Color.danarapiIncome) }
                    Toggle("Saya memahami konsekuensinya", isOn: $confirmed)
                }
                Section {
                    Button("Minta penghapusan akun", role: .destructive) {
                        Task { if await app.deleteAccount(password: "") { dismiss() } }
                    }.disabled(!confirmed || app.isLoading || authenticatedAt == nil || Date.now.timeIntervalSince(authenticatedAt ?? .distantPast) > 300)
                }
            }
            .navigationTitle("Hapus akun")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
