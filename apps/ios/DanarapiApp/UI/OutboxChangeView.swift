import SwiftUI

struct OutboxChangeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let change: OutboxRecord
    @State private var server: DashboardSnapshot?
    @State private var loading = true
    @State private var error: String?
    @State private var showDiscard = false
    @State private var showSaveAsNew = false

    private var transaction: TransactionDraft? { try? JSONDecoder.danarapi.decode(TransactionDraft.self, from: change.payload) }
    private var transfer: TransferDraft? { try? JSONDecoder.danarapi.decode(TransferDraft.self, from: change.payload) }
    private var deleted: VersionedID? { try? JSONDecoder.danarapi.decode(VersionedID.self, from: change.payload) }

    var body: some View {
        Form {
            Section("Perubahan perangkat") {
                Text(change.operation.replacingOccurrences(of: "_", with: " "))
                if let transaction {
                    LabeledContent("Nominal") { MoneyText(amount: transaction.amount, style: .headline) }
                    LabeledContent("Akun", value: accountName(transaction.accountID))
                    if let merchant = transaction.merchant { LabeledContent("Merchant", value: merchant) }
                    if let note = transaction.note { LabeledContent("Catatan", value: note) }
                    LabeledContent("Tanggal", value: MonthPeriod.display(transaction.occurredAt, template: "d MMM yyyy HHmm"))
                } else if let transfer {
                    LabeledContent("Nominal") { MoneyText(amount: transfer.amount, style: .headline) }
                    LabeledContent("Dari", value: accountName(transfer.fromAccountID))
                    LabeledContent("Ke", value: accountName(transfer.toAccountID))
                } else if let deleted {
                    Text("Permintaan hapus catatan versi \(deleted.version).")
                }
                if let version = change.baseVersion { LabeledContent("Versi dasar", value: "\(version)") }
                if let code = change.lastErrorCode { Text(code).foregroundStyle(Color.danarapiExpense) }
            }
            Section("Versi server") {
                if loading { ProgressView("Memuat versi terbaru…") }
                else if let error { Text(error).foregroundStyle(Color.danarapiExpense) }
                else if let server {
                    let id = transaction?.id ?? transfer?.id ?? deleted?.id
                    if let item = server.transactions.first(where: { $0.id == id }) {
                        LabeledContent("Nominal") { MoneyText(amount: item.amount, style: .headline) }
                        LabeledContent("Akun", value: accountName(item.accountID))
                        LabeledContent("Merchant", value: item.merchant ?? "—")
                        LabeledContent("Catatan", value: item.note ?? "—")
                        LabeledContent("Versi", value: "\(item.version)")
                    } else if let item = server.transfers.first(where: { $0.id == id }) {
                        LabeledContent("Nominal") { MoneyText(amount: item.amount, style: .headline) }
                        LabeledContent("Dari", value: accountName(item.fromAccountID))
                        LabeledContent("Ke", value: accountName(item.toAccountID))
                        LabeledContent("Versi", value: "\(item.version)")
                    } else { Text(id == nil ? "Catatan baru belum memiliki versi server." : "Catatan tidak ditemukan; mungkin sudah dihapus dari server.") }
                }
            }
            Section {
                Button("Buang perubahan, gunakan versi server", role: .destructive) { showDiscard = true }
                    .disabled(server == nil || loading || app.isSyncing)
                if change.status == "conflict", change.operation == "update_transaction", transaction?.kind == .expense {
                    Button("Simpan pengeluaran sebagai baru") { showSaveAsNew = true }
                        .disabled(server == nil || loading || app.isSyncing)
                }
                Text("Tidak ada penggabungan atau penimpaan otomatis. Periksa nominal dan catatan sebelum melanjutkan.")
                    .font(.footnote).foregroundStyle(Color.danarapiMuted)
            }
        }
        .danarapiListSurface()
        .navigationTitle("Tinjau perubahan")
        .task {
            do { server = try await app.serverSnapshotForOutbox(change) }
            catch { self.error = (error as? AppError)?.message ?? "Versi server belum dapat dimuat." }
            loading = false
        }
        .confirmationDialog("Buang perubahan perangkat?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Buang dan gunakan server", role: .destructive) {
                Task { if await app.discardOutboxChange(change.mutationID) { dismiss() } }
            }
            Button("Batal", role: .cancel) {}
        } message: { Text("Perubahan lokal dihapus permanen. Data yang sudah diterima server tidak dibatalkan.") }
        .confirmationDialog("Buat pengeluaran tambahan?", isPresented: $showSaveAsNew, titleVisibility: .visible) {
            Button("Buat pengeluaran baru") {
                Task { if await app.saveOutboxConflictAsNew(change) { dismiss() } }
            }
            Button("Batal", role: .cancel) {}
        } message: { Text("Catatan server tetap ada. Nominal ini akan dicatat sebagai pengeluaran tambahan dan dapat menggandakan pengeluaran jika sebenarnya catatan yang sama.") }
    }

    private func accountName(_ id: String) -> String {
        (server?.accounts ?? app.snapshot.accounts).first(where: { $0.id == id })?.name ?? "Akun tidak tersedia"
    }
}
