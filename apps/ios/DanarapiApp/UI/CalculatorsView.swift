import SwiftUI
import UIKit

struct CalculatorsView: View {
    @Environment(AppModel.self) private var app
    @State private var search = ""
    @State private var category = "all"
    @State private var onlyFavorites = false
    @State private var favorites: Set<String> = []
    @State private var history: [CalculatorHistoryRecord] = []
    @State private var showHistory = false
    @State private var selected: CalculatorSelection?
    @State private var clearConfirmation = false
    @State private var storageError: String?
    private var catalog: CalculatorCatalog? { CalculatorCatalog.bundled }
    private var definitions: [CalculatorDefinition] {
        (catalog?.calculators ?? []).filter { definition in
            (category == "all" || definition.category == category)
                && (!onlyFavorites || favorites.contains(definition.id))
                && (search.isEmpty || (definition.title + " " + definition.description).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kalkulator").font(.largeTitle.weight(.semibold))
                        Text("Hitung kebutuhan sehari-hari, rencana keuangan, dan kewajiban Islami.").font(.subheadline).foregroundStyle(Color.danarapiMuted)
                    }
                    HStack {
                        Button { onlyFavorites.toggle() } label: { Label("Favorit", systemImage: onlyFavorites ? "star.fill" : "star") }.buttonStyle(.bordered).accessibilityAddTraits(onlyFavorites ? .isSelected : [])
                        Button { history = CalculatorPreferences.history(owner: app.ownerID); showHistory = true } label: { Label("Riwayat", systemImage: "clock.arrow.circlepath") }.buttonStyle(.bordered)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryButton("Semua", id: "all")
                            ForEach(catalog?.categories ?? []) { group in categoryButton(group.title, id: group.id) }
                        }
                    }
                    if let storageError { Text(storageError).font(.caption).foregroundStyle(Color.danarapiExpense) }
                    if catalog == nil { ContentUnavailableView("Kalkulator belum tersedia", systemImage: "calculator", description: Text("Buka ulang aplikasi atau perbarui versi Danarapi.")) }
                    else if definitions.isEmpty { ContentUnavailableView(onlyFavorites ? "Belum ada favorit yang cocok" : "Kalkulator tidak ditemukan", systemImage: "magnifyingglass", description: Text("Coba kategori atau kata lain.")) }
                    ForEach(catalog?.categories ?? []) { group in
                        let values = definitions.filter { $0.category == group.id }
                        if !values.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Text(group.title).font(.title3.weight(.semibold)); Text("\(values.count)").font(.caption).foregroundStyle(Color.danarapiMuted) }
                                ForEach(values) { definition in
                                    HStack(spacing: 12) {
                                        Button { selected = CalculatorSelection(definition: definition) } label: {
                                            HStack(spacing: 12) {
                                                SymbolBadge(symbol: group.symbol, background: definition.isIslamic ? .danarapiMint : .danarapiSky, size: 44)
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text(definition.title).font(.headline)
                                                    Text(definition.description).font(.caption).foregroundStyle(Color.danarapiMuted).fixedSize(horizontal: false, vertical: true)
                                                }
                                                Spacer(minLength: 0)
                                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                        Button { toggleFavorite(definition.id) } label: { Image(systemName: favorites.contains(definition.id) ? "star.fill" : "star").frame(width: 44, height: 44) }
                                            .buttonStyle(.plain).foregroundStyle(favorites.contains(definition.id) ? Color.danarapiPrimary : Color.danarapiMuted)
                                            .accessibilityLabel("\(favorites.contains(definition.id) ? "Hapus favorit" : "Favoritkan") \(definition.title)")
                                    }.foregroundStyle(Color.danarapiInk).padding(16).background(Color.danarapiSurface, in: RoundedRectangle(cornerRadius: DesignTokens.cornerCard))
                                }
                            }
                        }
                    }
                }.padding(DesignTokens.gutter)
            }.background(Color.danarapiCanvas)
            .danarapiMainHeader()
            .searchable(text: $search, prompt: "Cari kalkulator")
            .sheet(item: $selected, onDismiss: { history = CalculatorPreferences.history(owner: app.ownerID) }) { selection in CalculatorDetailView(definition: selection.definition, initialInputs: selection.inputs) }
            .sheet(isPresented: $showHistory) { historySheet }
            .task(id: app.ownerID) { selected = nil; showHistory = false; favorites = CalculatorPreferences.favorites(owner: app.ownerID); history = CalculatorPreferences.history(owner: app.ownerID) }
            .onChange(of: app.isLocked) { _, locked in if locked { selected = nil; showHistory = false; history = [] } else { history = CalculatorPreferences.history(owner: app.ownerID) } }
        }
    }

    private func categoryButton(_ title: String, id: String) -> some View {
        Button { category = id } label: { Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(minHeight: 44).background(category == id ? Color.danarapiMint : Color.danarapiSurface, in: Capsule()).foregroundStyle(category == id ? Color.danarapiPrimary : Color.danarapiInk) }.buttonStyle(.plain).accessibilityAddTraits(category == id ? .isSelected : [])
    }
    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        CalculatorPreferences.saveFavorites(favorites, owner: app.ownerID)
    }
    private var historySheet: some View {
        NavigationStack {
            List {
                Section { Text("Maksimal 20 perhitungan, tersimpan khusus akun ini dengan perlindungan perangkat.").font(.caption).foregroundStyle(Color.danarapiMuted) }
                if history.isEmpty { Text("Belum ada perhitungan tersimpan.").foregroundStyle(Color.danarapiMuted) }
                ForEach(history) { record in
                    if let definition = catalog?.calculators.first(where: { $0.id == record.calculatorID }) {
                        Button {
                            let owner = app.ownerID
                            showHistory = false
                            Task { try? await Task.sleep(for: .milliseconds(350)); guard !Task.isCancelled, !app.isLocked, app.ownerID == owner else { return }; selected = CalculatorSelection(definition: definition, inputs: record.inputs) }
                        } label: { VStack(alignment: .leading, spacing: 5) { Text(record.title).font(.headline); Text(record.createdAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(Color.danarapiMuted) } }
                    }
                }
                if !history.isEmpty { Section { Button("Hapus riwayat", role: .destructive) { clearConfirmation = true } } }
            }.danarapiListSurface().navigationTitle("Riwayat kalkulator").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { showHistory = false } } }
                .confirmationDialog("Hapus riwayat kalkulator akun ini?", isPresented: $clearConfirmation, titleVisibility: .visible) {
                    Button("Hapus riwayat", role: .destructive) { do { try CalculatorPreferences.saveHistory([], owner: app.ownerID); history = [] } catch { storageError = error.localizedDescription } }
                }
        }
    }
}

private struct CalculatorSelection: Identifiable {
    let definition: CalculatorDefinition
    var inputs: [String: String]? = nil
    var id: String { definition.id }
}

struct CalculatorDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let definition: CalculatorDefinition
    var initialInputs: [String: String]? = nil
    @State private var inputs: [String: String] = [:]
    @State private var result: CalculatorResult?
    @State private var error: String?
    @State private var showInformation = false
    @State private var calculated = false
    @State private var draftSaved = false
    @State private var saving = false
    @State private var openedOwner = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(definition.description).foregroundStyle(Color.danarapiMuted)
                    Button { showInformation = true } label: { Label(definition.isIslamic ? "Dalil dan metode" : "Informasi dan rumus", systemImage: "info.circle") }
                        .accessibilityIdentifier("calculator.info.\(definition.id)")
                }
                Section("Input perhitungan") {
                    ForEach(definition.fields.filter { $0.isVisible(inputs) }) { field in fieldView(field) }
                }
                Section {
                    Button("Hitung hasil", systemImage: "calculator") { calculate(save: true) }.buttonStyle(PrimaryButtonStyle()).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    Button("Reset input") { calculated = false; result = nil; error = nil; draftSaved = false; inputs = definition.defaults() }
                    if let error { Text(error).font(.subheadline).foregroundStyle(Color.danarapiExpense).accessibilityAddTraits(.updatesFrequently) }
                }
                if let result { resultView(result) }
            }.danarapiListSurface().navigationTitle(definition.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Tutup") { dismiss() } } }
                .sheet(isPresented: $showInformation) { CalculatorInformationView(definition: definition) }
                .onAppear {
                    openedOwner = app.ownerID
                    inputs = initialInputs ?? definition.defaults()
                    if initialInputs != nil { calculate(save: false) }
                }
                .onChange(of: inputs) { _, _ in if calculated { calculate(save: false) } }
                .onChange(of: app.ownerID) { _, _ in result = nil; inputs = [:]; showInformation = false; dismiss() }
                .onChange(of: app.isLocked) { _, locked in if locked { result = nil; inputs = [:]; showInformation = false; dismiss() } }
        }
    }

    @ViewBuilder private func fieldView(_ field: CalculatorField) -> some View {
        let binding = Binding(get: { inputs[field.key] ?? field.defaultValue }, set: { inputs[field.key] = $0 })
        switch field.kind {
        case "toggle": Toggle(field.label, isOn: Binding(get: { binding.wrappedValue == "true" }, set: { binding.wrappedValue = $0 ? "true" : "false" }))
        case "choice": Picker(field.label, selection: binding) { ForEach(field.options ?? []) { Text($0.label).tag($0.value) } }.pickerStyle(.menu)
        case "date": DatePicker(field.label, selection: dateBinding(field.key), displayedComponents: .date)
        case "money":
            VStack(alignment: .leading, spacing: 8) {
                Text(field.label).font(.subheadline.weight(.medium))
                HStack { Text("Rp").foregroundStyle(Color.danarapiMuted); RupiahTextField("0", text: binding, accessibilityName: field.label, accessibilityID: "calculator.input.\(field.key)") }
            }.padding(.vertical, 5)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text(field.label + (field.unit.map { " (\($0))" } ?? "")).font(.subheadline.weight(.medium))
                TextField("0", text: Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0.replacingOccurrences(of: ",", with: ".") }))
                    .keyboardType(field.kind == "integer" ? .numberPad : .decimalPad).accessibilityLabel(field.label)
            }.padding(.vertical, 5)
        }
    }
    private func dateBinding(_ key: String) -> Binding<Date> {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return Binding(get: { formatter.date(from: inputs[key] ?? "") ?? .now }, set: { inputs[key] = formatter.string(from: $0) })
    }
    @ViewBuilder private func resultView(_ result: CalculatorResult) -> some View {
        Section(result.headline) {
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.label).font(.caption).foregroundStyle(Color.danarapiMuted)
                    Text(row.formatted).font(row.kind == "money" ? .title3.weight(.semibold) : .subheadline.weight(.medium)).monospacedDigit().textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            ForEach(result.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Color.danarapiPeachInk).padding(12).background(Color.danarapiPeach, in: RoundedRectangle(cornerRadius: 12)) }
            if !result.steps.isEmpty { DisclosureGroup("Rincian perhitungan") { ForEach(result.steps, id: \.self) { Text($0).font(.subheadline) }; Text(definition.method).font(.caption).foregroundStyle(Color.danarapiMuted) } }
            if !result.schedule.isEmpty {
                DisclosureGroup("Jadwal / proyeksi \(result.schedule.count) periode") {
                    ForEach(result.schedule, id: \.period) { period in
                        VStack(alignment: .leading, spacing: 5) { Text(period.period).font(.headline); Text(CalculatorResult.Row(label: "", value: period.amount, kind: "money", unit: "Rp").formatted).font(.subheadline.weight(.semibold)); Text(period.detail).font(.caption).foregroundStyle(Color.danarapiMuted) }.padding(.vertical, 6)
                    }
                }
            }
            Button("Salin hasil", systemImage: "doc.on.doc") { UIPasteboard.general.string = result.summary(definition); app.toastMessage = "Hasil perhitungan disalin" }
            ShareLink(item: result.summary(definition)) { Label("Bagikan hasil", systemImage: "square.and.arrow.up") }
            if let raw = result.primaryAmount, let amount = Int64(raw), amount > 0 {
                Button(draftSaved ? "Sudah masuk draft" : "Simpan hasil ke draft", systemImage: "tray.and.arrow.down") { Task { await saveDraft(result, amount: amount) } }.disabled(saving || draftSaved || app.isLoading || (app.mode == .authenticated && !app.network.isOnline))
                Text("Nominal draft: \(result.primaryLabel ?? "Hasil utama") — \(CalculatorResult.Row(label: "", value: raw, kind: "money", unit: "Rp").formatted). Periksa jenis dan akun sebelum mencatat. Saldo berubah setelah konfirmasi.").font(.caption).foregroundStyle(Color.danarapiMuted)
            }
        }
    }
    private func calculate(save: Bool) {
        guard openedOwner == app.ownerID, !app.isLocked else { return }
        calculated = true; draftSaved = false
        do {
            let value = try CalculatorEngine.shared.calculate(definition, inputs: inputs)
            result = value; error = nil
            if save {
                var records = CalculatorPreferences.history(owner: openedOwner)
                records.insert(CalculatorHistoryRecord(id: UUID().uuidString, calculatorID: definition.id, title: definition.title, inputs: inputs, createdAt: .now), at: 0)
                do { try CalculatorPreferences.saveHistory(records, owner: openedOwner) } catch { self.error = "Hasil tersedia; riwayat belum dapat disimpan." }
            }
        } catch { result = nil; self.error = (error as? AppError)?.message ?? error.localizedDescription }
    }
    private func saveDraft(_ result: CalculatorResult, amount: Int64) async {
        guard !saving, !draftSaved, openedOwner == app.ownerID, !app.isLocked else { return }
        saving = true; defer { saving = false }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: .now)
        let item = ReviewItem(id: UUID().uuidString, source: .pastedText, status: .pending,
            amount: ExtractedField(value: String(amount), confidence: .high, evidenceSpan: String(amount), sourceType: .pastedText),
            merchant: ExtractedField(value: "Kalkulator: " + definition.title, confidence: .high, evidenceSpan: definition.title, sourceType: .pastedText),
            date: ExtractedField(value: date, confidence: .high, evidenceSpan: date, sourceType: .pastedText),
            rawReference: result.summary(definition), duplicateCandidateID: nil, attachmentName: nil, createdAt: .now)
        if await app.addReview(item), openedOwner == app.ownerID { draftSaved = true; app.toastMessage = "Hasil masuk draft. Saldo belum berubah." }
    }
}

private struct CalculatorInformationView: View {
    @Environment(\.dismiss) private var dismiss
    let definition: CalculatorDefinition
    var body: some View {
        NavigationStack {
            List {
                Section("Metode perhitungan") { Text(definition.method).font(.body) }
                if definition.isIslamic {
                    Section {
                        Text("Ringkasan makna, bukan kutipan terjemahan lengkap. Buka sumber untuk membaca teks hadis atau ayat.").font(.caption).foregroundStyle(Color.danarapiMuted)
                        ForEach(definition.references, id: \.self) { id in
                            if let source = CalculatorCatalog.bundled?.sources[id] {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(source.title).font(.headline)
                                    Text(source.status).font(.caption.weight(.semibold)).foregroundStyle(Color.danarapiPrimary)
                                    Text(source.meaning).font(.body).fixedSize(horizontal: false, vertical: true)
                                    if let url = URL(string: source.url) { Link("Baca sumber", destination: url).frame(minHeight: 44) }
                                }.padding(.vertical, 6)
                            }
                        }
                    } header: { Text("Dalil dan rujukan") }
                }
                Section("Ketentuan dan asumsi") { ForEach(definition.notes, id: \.self) { Text($0).font(.subheadline).fixedSize(horizontal: false, vertical: true) } }
            }.danarapiListSurface().navigationTitle(definition.isIslamic ? "Dalil dan metode" : "Informasi kalkulator").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Selesai") { dismiss() } } }
        }
    }
}
