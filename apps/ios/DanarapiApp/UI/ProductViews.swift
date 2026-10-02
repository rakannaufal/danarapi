import SwiftUI
import UIKit

struct ProductCatalog: Decodable, Sendable {
    struct Welcome: Decodable, Sendable {
        let headline: String
        let subtitle: String
        let signInTitle: String
        let signInSubtitle: String
        let reauthenticationMessage: String
        let disclaimer: String
    }
    struct OnboardingStep: Decodable, Identifiable, Sendable { let id: String; let image: String; let title: String; let description: String }
    struct Link: Decodable, Identifiable, Sendable { let id: String; let title: String }
    struct Feature: Decodable, Identifiable, Sendable { let id: String; let title: String; let description: String }
    struct Help: Decodable, Sendable {
        let title: String
        let subtitle: String
        let searchPlaceholder: String
        let allTopics: String
        let emptyTitle: String
        let emptyMessage: String
        let gettingStartedTitle: String
        let gettingStarted: [Feature]
        let contactTitle: String
        let contactIntro: String
        let supportPrivacy: String
        let signInMessage: String
        let messagePlaceholder: String
        let requestLabel: String
        let submitLabel: String
    }
    struct Page: Decodable, Identifiable, Sendable {
        struct Section: Decodable, Sendable { let title: String; let paragraphs: [String] }
        let id: String
        let title: String
        let subtitle: String
        let sections: [Section]
    }
    struct Answer: Decodable, Identifiable, Sendable { let id: String; let topic: String; let question: String; let answer: String }
    let version: String
    let owner: String
    let name: String
    let welcome: Welcome
    let onboarding: [OnboardingStep]
    let pages: [Page]
    let faq: [Answer]
    let links: [Link]
    let features: [Feature]
    let help: Help
    let supportTopics: [Link]
    static let bundled: ProductCatalog? = {
        guard let url = Bundle.main.url(forResource: "product-content", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProductCatalog.self, from: data)
    }()
    static var policyVersion: String { bundled?.version ?? "2026-10-02" }
    static var links: [(String, String)] { (bundled?.links ?? []).map { ($0.id, $0.title) } }
}

struct ProductRoute: Identifiable { let id: String }
struct AIConsentState: Codable, Sendable { let granted: Bool; let policyVersion: String?; let updatedAt: Date? }
struct SupportTicket: Decodable, Identifiable, Sendable { let id: String; let topic: String; let description: String; let status: String; let reply: String?; let createdAt: Date }
struct SupportTickets: Decodable, Sendable { let items: [SupportTicket] }
struct ProductInfo: Decodable, Sendable { let policyVersion: String; let supportEmail: String?; let authentication: String; let scanConfigured: Bool; let checkedAt: Date }

@MainActor
enum AIConsentPresenter {
    private static var pending: CheckedContinuation<Bool, Never>?
    private static var alert: UIAlertController?
    static func cancel() { finish(false) }
    private static func finish(_ accepted: Bool) {
        let continuation = pending
        pending = nil
        alert?.dismiss(animated: false)
        alert = nil
        continuation?.resume(returning: accepted)
    }
    static func request() async -> Bool {
        guard !Task.isCancelled, pending == nil else { return false }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })?.windows.first(where: \.isKeyWindow), var presenter = window.rootViewController else { return false }
        while let presented = presenter.presentedViewController { presenter = presented }
        if presenter is UIAlertController { return false }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                pending = continuation
                let prompt = UIAlertController(title: "Izinkan pengiriman struk?", message: "Foto atau halaman PDF dikirim ke penyedia AI untuk membaca struk. Pemrosesan mengikuti ketentuan paket penyedia. Periksa hasil sebelum menyimpan. Kebijakan lengkap tersedia di Pengaturan → Kebijakan privasi.", preferredStyle: .alert)
                prompt.addAction(UIAlertAction(title: "Isi manual", style: .cancel) { _ in finish(false) })
                prompt.addAction(UIAlertAction(title: "Setuju dan lanjutkan", style: .default) { _ in finish(true) })
                alert = prompt
                presenter.present(prompt, animated: true)
            }
        } onCancel: { Task { @MainActor in cancel() } }
    }
}

struct ProductLinksView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Menu("Tentang & bantuan", systemImage: "questionmark.circle") {
            ForEach(ProductCatalog.links, id: \.0) { identifier, title in
                Button(title) { app.productPage = ProductRoute(id: identifier) }
            }
        }.frame(minHeight: 44).font(.subheadline)
    }
}

struct ProductPageView: View {
    @Environment(AppModel.self) private var app
    let pageID: String
    @State private var search = ""
    @State private var faqTopic = ""
    @State private var topic = "lainnya"
    @State private var description = ""
    @State private var requestID = ""
    @State private var tickets: [SupportTicket] = []
    @State private var info: ProductInfo?
    @State private var error: String?
    @State private var success: String?
    @State private var busy = false
    @State private var ticketID = UUID().uuidString
    @State private var acknowledged = false
    private var page: ProductCatalog.Page? { ProductCatalog.bundled?.pages.first { $0.id == pageID } }
    private var title: String { page?.title ?? (pageID == "faq" ? help?.title : pageID == "contact" ? help?.contactTitle : nil) ?? ProductCatalog.bundled?.links.first(where: { $0.id == pageID })?.title ?? "Bantuan" }
    private var answers: [ProductCatalog.Answer] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (ProductCatalog.bundled?.faq ?? []).filter { answer in
            (faqTopic.isEmpty || answer.topic == faqTopic) && (query.isEmpty || "\(answer.topic) \(answer.question) \(answer.answer)".localizedCaseInsensitiveContains(query))
        }
    }
    private var faqTopics: [String] { Array(Set((ProductCatalog.bundled?.faq ?? []).map(\.topic))).sorted() }
    private var help: ProductCatalog.Help? { ProductCatalog.bundled?.help }
    private func featureSymbol(_ identifier: String) -> String {
        ["wallet": "wallet.pass", "transactions": "arrow.left.arrow.right", "budget": "chart.pie", "target": "target", "review": "viewfinder", "split": "person.2", "reports": "chart.bar.xaxis", "reset": "arrow.triangle.2.circlepath"][identifier] ?? "info.circle"
    }
    var body: some View {
        Form {
            if let page {
                Section { Text(page.subtitle).foregroundStyle(.secondary); if pageID != "about" { Text("Berlaku \(ProductCatalog.policyVersion)").font(.caption).foregroundStyle(.secondary) } }
                ForEach(page.sections, id: \.title) { section in
                    Section(section.title) { ForEach(section.paragraphs, id: \.self) { Text($0).font(.subheadline).lineSpacing(4).textSelection(.enabled) } }
                }
                if pageID == "about" {
                    Section("Fitur Danarapi") {
                        ForEach(ProductCatalog.bundled?.features ?? []) { feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: featureSymbol(feature.id)).font(.system(size: 20)).foregroundStyle(Color.danarapiPrimary).frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(feature.title).font(.headline)
                                    Text(feature.description).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                    Section("Versi") { LabeledContent("Aplikasi", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))") }
                }
                if pageID == "privacy" && app.mode == .authenticated {
                    Section("Pengiriman struk ke AI") {
                        Text(app.aiConsent?.granted == true ? "Persetujuan aktif." : "Persetujuan diminta sebelum unggahan pertama.").font(.subheadline)
                        Button("Cabut persetujuan AI", role: .destructive) { Task { busy = true; defer { busy = false }; do { try await app.setAIConsent(false); success = "Persetujuan dicabut. Isi manual tetap tersedia." } catch { self.error = error.localizedDescription } } }.disabled(busy)
                    }
                    Section("Penerimaan retensi") {
                        if acknowledged { Text("Penerimaan kebijakan tercatat.") }
                        else { Button("Saya sudah membaca kebijakan retensi") { Task { busy = true; defer { busy = false }; do { try await app.acknowledgeRetention(); acknowledged = true } catch { self.error = error.localizedDescription } } }.disabled(busy) }
                    }
                }
            } else if pageID == "faq" {
                if let help {
                    Section {
                        Text(help.subtitle).foregroundStyle(.secondary)
                        TextField(help.searchPlaceholder, text: $search).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Picker("Topik", selection: $faqTopic) {
                            Text(help.allTopics).tag("")
                            ForEach(faqTopics, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && faqTopic.isEmpty {
                        Section(help.gettingStartedTitle) {
                            ForEach(help.gettingStarted) { step in
                                VStack(alignment: .leading, spacing: 5) { Text(step.title).font(.headline); Text(step.description).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical, 4)
                            }
                        }
                    }
                    if answers.isEmpty { Section { Text(help.emptyTitle).font(.headline); Text(help.emptyMessage).foregroundStyle(.secondary); NavigationLink("Kontak") { ProductPageView(pageID: "contact") } } }
                }
                ForEach(answers) { answer in Section { DisclosureGroup(answer.question) { Text(answer.answer).font(.subheadline).lineSpacing(4).padding(.vertical, 8) } } }
            } else if pageID == "contact" {
                supportForm
                if !tickets.isEmpty {
                    Section("Laporan Anda") {
                        ForEach(tickets) { ticket in DisclosureGroup("\(ticket.topic) · \(ticket.status == "resolved" ? "Selesai" : ticket.status == "in_progress" ? "Ditangani" : "Menunggu")") { Text(ticket.description).font(.subheadline); if let reply = ticket.reply { Text("Balasan: \(reply)").font(.subheadline) }; Text(ticket.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }
                    }
                }
            }
            if let error { Section { Text(error).foregroundStyle(Color.danarapiExpense).font(.subheadline) } }
            if let success { Section { Text(success).font(.subheadline).textSelection(.enabled) } }
            Section("Tentang & bantuan") { ForEach(ProductCatalog.links.filter { $0.0 != pageID }, id: \.0) { identifier, title in NavigationLink(title) { ProductPageView(pageID: identifier) } } }
        }
        .scrollContentBackground(.hidden).background(Color.danarapiCanvas)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task(id: pageID) {
            if pageID == "contact" {
                if app.mode == .authenticated { do { tickets = try await app.supportTickets() } catch { self.error = error.localizedDescription } }
                info = try? await app.productInfo()
            }
            if pageID == "privacy" && app.mode == .authenticated { _ = try? await app.refreshAIConsent() }
        }
    }
    private var supportForm: some View {
        Section("Lapor masalah") {
            if let email = info?.supportEmail, let url = URL(string: "mailto:\(email)") { Link(email, destination: url) }
            if let help { Text(help.contactIntro).font(.subheadline); Text(help.supportPrivacy).font(.caption).foregroundStyle(.secondary) }
            if app.mode == .authenticated {
                Picker("Topik", selection: $topic) { ForEach(ProductCatalog.bundled?.supportTopics ?? []) { Text($0.title).tag($0.id) } }
                TextField(help?.messagePlaceholder ?? "Pesan", text: $description, axis: .vertical).lineLimit(4...10)
                TextField("\(help?.requestLabel ?? "ID permintaan") (opsional)", text: $requestID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(busy ? "Mengirim…" : help?.submitLabel ?? "Kirim laporan") { Task { await send() } }.disabled(busy || description.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || description.count > 4000 || !app.network.isOnline)
            } else { Text(help?.signInMessage ?? "Masuk untuk mengirim laporan privat dan melihat balasan.").font(.subheadline) }
        }
    }
    private func send() async {
        if !requestID.isEmpty && UUID(uuidString: requestID) == nil { error = "ID permintaan harus berupa UUID."; return }
        busy = true; error = nil; defer { busy = false }
        do {
            try await app.sendSupportTicket(id: ticketID, topic: topic, description: description.trimmingCharacters(in: .whitespacesAndNewlines), requestID: requestID.isEmpty ? nil : requestID)
            success = "Laporan tersimpan. ID: \(ticketID)"; description = ""; requestID = ""; ticketID = UUID().uuidString
            tickets = try await app.supportTickets()
        } catch { self.error = error.localizedDescription }
    }
}
