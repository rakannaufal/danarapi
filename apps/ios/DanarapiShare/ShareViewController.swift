import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let context = extensionContext else { return }
        let controller = UIHostingController(rootView: ShareReceiptView(context: context))
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        controller.didMove(toParent: self)
    }
}

private struct ShareReceiptView: View {
    let context: NSExtensionContext
    @State private var payloads: [SharedPayload] = []
    @State private var loading = true
    @State private var saving = false
    @State private var saved = false
    @State private var message: String?
    @State private var savedCount = 0
    @State private var notes: [String] = []
    @State private var formats: [String] = []
    @State private var account: SharedInboxAccount?
    private let teal = Color(red: 0.06, green: 0.39, blue: 0.35)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: saved ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                            .font(.system(size: 36, weight: .medium)).foregroundStyle(teal)
                        Text(saved ? "Bukti tersimpan" : message != nil && payloads.isEmpty ? "Bukti belum terbaca" : "Simpan sebagai draft")
                            .font(.title2.bold())
                        Text(saved ? "Buka Danarapi dengan akun yang digunakan saat menyimpan, lalu Beranda → Tinjauan → Bukti dari Share. Periksa transaksi sebelum mencatatnya." : message != nil && payloads.isEmpty ? "Belum ada draft disimpan. Pastikan akun Danarapi sudah masuk, lalu bagikan kembali bukti." : "Bukti disimpan khusus untuk akun Danarapi yang sedang masuk. Pembacaan dilakukan di Danarapi; saldo belum berubah.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if saved { Text("\(savedCount) bukti tersimpan. Bukti dengan isi sama memakai salinan sebelumnya pada akun ini.").font(.footnote).foregroundStyle(.secondary) }
                    }.padding(.vertical, 12)
                }
                if loading { Section { ProgressView("Menyiapkan bukti…") } }
                if !payloads.isEmpty && !saved {
                    Section("Bukti yang dibagikan") {
                        ForEach(payloads.indices, id: \.self) { index in
                            let proof = payloads[index]
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(proof.name).font(.body.weight(.medium)).lineLimit(2)
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(proof.data.count), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: proof.mime == "application/pdf" ? "doc.richtext" : proof.mime == "text/plain" ? "text.quote" : "photo") }
                        }
                    }
                }
                if !notes.isEmpty && !saved {
                    Section { ForEach(notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) } }
                }
                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.red)
                        Button("Coba baca ulang", systemImage: "arrow.clockwise") { Task { await prepare() } }
                            .disabled(loading || saving).accessibilityIdentifier("share.retry")
                        DisclosureGroup("Detail format kiriman") {
                            Text(formats.isEmpty ? "Aplikasi pengirim tidak menyediakan lampiran." : formats.joined(separator: "\n"))
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                if !saved && (loading || !payloads.isEmpty) {
                    Section {
                        Button { save() } label: {
                            HStack { Spacer(); if saving { ProgressView().tint(.white) }; Text("Simpan draft").fontWeight(.semibold); Spacer() }.padding(.vertical, 7)
                        }
                        .foregroundStyle(.white).listRowBackground(teal)
                        .disabled(loading || saving || payloads.isEmpty || account == nil)
                        .accessibilityIdentifier("share.save")
                    } footer: { Text("Maksimal 5 bukti, 5 MB per berkas. JPEG, PNG, HEIC, PDF, atau teks. Tautan bank tidak dibuka otomatis.") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Danarapi").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Selesai" : "Batal") { context.completeRequest(returningItems: nil) }
                        .disabled(saving)
                }
            }
            .tint(teal)
            .task { await prepare() }
        }
    }

    @MainActor private func prepare() async {
        loading = true; message = nil; notes = []; payloads = []; account = nil
        defer { loading = false }
        do {
            let target = try SharedInbox.live().activeAccount()
            let providers = (context.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            formats = providers.enumerated().map { "Lampiran \($0.offset + 1): " + $0.element.registeredTypeIdentifiers.joined(separator: ", ") }
            let result = try await ShareItemReader.read(providers)
            try Task.checkCancellation()
            payloads = result.payloads; notes = result.notes; account = target
        } catch is CancellationError { return }
        catch { message = error.localizedDescription; payloads = [] }
    }

    @MainActor private func save() {
        guard !saving, !saved else { return }
        saving = true
        do {
            guard let account, let ownerID = account.ownerID else { throw SharedInboxError.signInRequired }
            let records = try SharedInbox.live().save(payloads, ownerID: ownerID, expectedAccount: account)
            savedCount = Set(records.map(\.id)).count
            saved = true; message = nil; payloads = []
        } catch { message = error.localizedDescription }
        saving = false
    }

}
