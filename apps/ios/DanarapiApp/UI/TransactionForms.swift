import SwiftUI
import UIKit

struct RupiahTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var signed = false
    var large = false
    var focus: FocusState<String?>.Binding? = nil
    var focusID: String? = nil
    var accessibilityName: String? = nil
    var accessibilityID: String? = nil
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.isEnabled) private var isEnabled

    init(_ placeholder: String, text: Binding<String>, signed: Bool = false, large: Bool = false, focus: FocusState<String?>.Binding? = nil, focusID: String? = nil, accessibilityName: String? = nil, accessibilityID: String? = nil) {
        self.placeholder = placeholder
        _text = text
        self.signed = signed
        self.large = large
        self.focus = focus
        self.focusID = focusID
        self.accessibilityName = accessibilityName
        self.accessibilityID = accessibilityID
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 16
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.placeholder = placeholder
        field.accessibilityLabel = accessibilityName ?? placeholder
        field.accessibilityIdentifier = accessibilityID
        let keyboardType: UIKeyboardType = signed ? .numbersAndPunctuation : .numberPad
        if field.keyboardType != keyboardType { field.keyboardType = keyboardType }
        field.textAlignment = alignment == .trailing ? .right : .left
        let font: UIFont = large ? .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .largeTitle).pointSize, weight: .bold) : .preferredFont(forTextStyle: .body)
        if field.font != font { field.font = font }
        field.adjustsFontForContentSizeCategory = true
        let current = MoneyInputFormat.raw(field.text ?? "", signed: signed)
        let transientZero = field.isFirstResponder && text == "0" && (current.isEmpty || current == "-")
        if current != text && !transientZero { field.text = MoneyInputFormat.display(text, signed: signed) }
        if let focus, let focusID, field.isFirstResponder && focus.wrappedValue != focusID { field.resignFirstResponder() }
        if let focus, let focusID, focus.wrappedValue == focusID && !field.isFirstResponder { field.becomeFirstResponder() }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RupiahTextField
        init(_ parent: RupiahTextField) { self.parent = parent }

        func textFieldDidBeginEditing(_ textField: UITextField) { if let focusID = parent.focusID { parent.focus?.wrappedValue = focusID } }
        func textFieldDidEndEditing(_ textField: UITextField) {
            textField.text = MoneyInputFormat.display(parent.text, signed: parent.signed)
            if parent.focus?.wrappedValue == parent.focusID { parent.focus?.wrappedValue = nil }
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let old = textField.text ?? ""
            var editRange = range
            if string.isEmpty && range.length == 1 && (old as NSString).substring(with: range) == "." {
                let selection = textField.selectedTextRange
                let caret = selection.map { textField.offset(from: textField.beginningOfDocument, to: $0.start) } ?? range.location + 1
                if caret > range.location && range.location > 0 { editRange = NSRange(location: range.location - 1, length: 2) }
                else if range.location + 1 < (old as NSString).length { editRange = NSRange(location: range.location, length: 2) }
            }
            let edited = (old as NSString).replacingCharacters(in: editRange, with: string)
            let display = MoneyInputFormat.display(edited, signed: parent.signed)
            let prefix = (edited as NSString).substring(to: editRange.location + (string as NSString).length)
            let offset = MoneyInputFormat.caret(edited, position: prefix.count, formatted: display)
            textField.text = display
            parent.text = MoneyInputFormat.raw(edited, signed: parent.signed)
            if let position = textField.position(from: textField.beginningOfDocument, offset: offset) { textField.selectedTextRange = textField.textRange(from: position, to: position) }
            return false
        }
    }
}

struct MoneyField: View {
    let title: String
    @Binding var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.danarapiMuted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Rp").font(.title2.bold()).foregroundStyle(Color.danarapiMuted)
                RupiahTextField("0", text: $value, large: true, accessibilityName: title, accessibilityID: "money.\(title)")
                    .keyboardType(.numberPad)
                    .font(.system(.largeTitle, design: .default).bold().monospacedDigit())
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("money.\(title)")
            }
            .padding(16).background(Color.danarapiSurface, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct TransactionFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let editing: FinanceTransaction?
    let onSaved: () -> Void
    @State private var kind: TransactionKind
    @State private var amount: String
    @State private var accountID: String
    @State private var categoryID: String
    @State private var occurredAt: Date
    @State private var merchant: String
    @State private var note: String
    @State private var goalID: String

    init(kind: TransactionKind, editing: FinanceTransaction? = nil, initialGoal: SavingsGoal? = nil, onSaved: @escaping () -> Void = {}) {
        self.editing = editing
        self.onSaved = onSaved
        _kind = State(initialValue: editing?.kind ?? kind)
        _amount = State(initialValue: editing.map { String($0.amount) } ?? "")
        _accountID = State(initialValue: editing?.accountID ?? "")
        _categoryID = State(initialValue: editing?.categoryID ?? (initialGoal == nil ? "" : "feature-goal"))
        _occurredAt = State(initialValue: editing?.occurredAt ?? .now)
        _merchant = State(initialValue: editing?.merchant ?? "")
        _note = State(initialValue: editing?.note ?? "")
        _goalID = State(initialValue: editing?.goalID ?? initialGoal?.id ?? "")
    }

    private var categories: [Category] { kind == .income ? app.incomeCategories : app.expenseCategories }
    private var isQRIS: Bool { editing?.source == "qris" }
    private var merchantSuggestion: Category? {
        guard kind == .expense, !isQRIS, !goalSelected, let merchant = merchant.nilIfBlank else { return nil }
        let rule = app.snapshot.merchantRules.sorted { $0.priority > $1.priority }.first { $0.matches(merchant) }
        return rule.flatMap { match in app.expenseCategories.first(where: { $0.id == match.categoryID }) }
    }
    private var valid: Bool { Int64(amount).map { $0 > 0 && $0 <= Money.maximum } == true && !accountID.isEmpty && !categoryID.isEmpty && (!goalSelected || !goalID.isEmpty) }

    private var goalSelected: Bool { kind == .expense && categories.first(where: { $0.id == categoryID })?.systemKey == "goal" }

    var body: some View {
        Form {
            Section {
                if !isQRIS { Picker("Jenis", selection: $kind) { ForEach(TransactionKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                MoneyField(title: "Nominal", value: $amount).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("Rincian") {
                Picker("Akun", selection: $accountID) { Text("Pilih akun").tag(""); ForEach(app.activeAccounts) { Text($0.name).tag($0.id) } }
                Picker("Kategori", selection: $categoryID) { Text("Pilih kategori").tag(""); ForEach(categories) { Text($0.name).tag($0.id) } }.disabled(isQRIS)
                if goalSelected { Picker("Target", selection: $goalID) { Text("Pilih target").tag(""); ForEach(app.snapshot.goals ?? []) { Text($0.name).tag($0.id) } }.accessibilityIdentifier("transaction.goal") }
                DatePicker("Tanggal", selection: $occurredAt)
                LabeledContent { TextField("Nama merchant", text: $merchant).multilineTextAlignment(.trailing) } label: { HStack(spacing: 6) { Text("Merchant"); Text("opsional").font(.caption).foregroundStyle(Color.danarapiMuted) } }
                if let merchantSuggestion, merchantSuggestion.id != categoryID {
                    Button { categoryID = merchantSuggestion.id } label: { Label("Gunakan kategori \(merchantSuggestion.name)", systemImage: "wand.and.stars") }
                }
                TextField("Catatan (opsional)", text: $note, axis: .vertical)
            }
            Section { Button(editing == nil ? "Catat \(kind.title.lowercased())" : "Simpan perubahan") { Task { await save() } }.buttonStyle(PrimaryButtonStyle()).disabled(!valid).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
        }
        .scrollContentBackground(.hidden).background(Color.danarapiCanvas)
        .navigationTitle(editing == nil ? "Tambah transaksi" : "Ubah transaksi").navigationBarTitleDisplayMode(.inline)
        .onAppear { setDefaults() }
        .onChange(of: kind) { _, _ in categoryID = categories.first?.id ?? ""; goalID = "" }
        .onChange(of: categoryID) { _, _ in if !goalSelected { goalID = "" } }
    }

    private func setDefaults() {
        if accountID.isEmpty { accountID = app.activeAccounts.first?.id ?? "" }
        if !goalID.isEmpty, kind == .expense { categoryID = categories.first(where: { $0.systemKey == "goal" })?.id ?? "" }
        else if categoryID.isEmpty { categoryID = categories.first?.id ?? "" }
    }

    private func save() async {
        guard let parsed = Int64(amount) else { return }
        let draft = TransactionDraft(id: editing?.id, kind: kind, amount: parsed, accountID: accountID, categoryID: categoryID, occurredAt: occurredAt, merchant: merchant.nilIfBlank, note: note.nilIfBlank, source: editing?.source ?? "manual", expectedVersion: editing?.version, goalID: goalSelected ? goalID : nil)
        if await app.saveTransaction(draft) { onSaved(); dismiss() }
    }
}

struct TransferFormView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let editing: TransferRecord?
    let onSaved: () -> Void
    @State private var amount = ""
    @State private var fromID = ""
    @State private var toID = ""
    @State private var occurredAt = Date.now
    @State private var note = ""

    init(editing: TransferRecord? = nil, onSaved: @escaping () -> Void = {}) {
        self.editing = editing
        self.onSaved = onSaved
        _amount = State(initialValue: editing.map { String($0.amount) } ?? "")
        _fromID = State(initialValue: editing?.fromAccountID ?? "")
        _toID = State(initialValue: editing?.toAccountID ?? "")
        _occurredAt = State(initialValue: editing?.occurredAt ?? .now)
        _note = State(initialValue: editing?.note ?? "")
    }

    var body: some View {
        Form {
            Section { MoneyField(title: "Nominal transfer", value: $amount).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            Section("Rincian") {
                Picker("Dari akun", selection: $fromID) { Text("Pilih akun").tag(""); ForEach(app.activeAccounts) { Text($0.name).tag($0.id) } }
                Picker("Ke akun", selection: $toID) { Text("Pilih akun").tag(""); ForEach(app.activeAccounts) { Text($0.name).tag($0.id) } }
                DatePicker("Tanggal", selection: $occurredAt)
                TextField("Catatan (opsional)", text: $note)
                if fromID == toID && !fromID.isEmpty { Label("Akun asal dan tujuan harus berbeda.", systemImage: "exclamationmark.triangle").foregroundStyle(Color.danarapiExpense) }
            }
            Section { Button(editing == nil ? "Simpan transfer" : "Simpan perubahan") { Task { await save() } }.buttonStyle(PrimaryButtonStyle()).disabled(Int64(amount) == nil || fromID.isEmpty || toID.isEmpty || fromID == toID).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
        }
        .scrollContentBackground(.hidden).background(Color.danarapiCanvas).navigationTitle("Transfer").navigationBarTitleDisplayMode(.inline)
        .onAppear { if fromID.isEmpty { fromID = app.activeAccounts.first?.id ?? "" }; if toID.isEmpty { toID = app.activeAccounts.dropFirst().first?.id ?? "" } }
    }

    private func save() async {
        guard let parsed = Int64(amount) else { return }
        if await app.createTransfer(TransferDraft(id: editing?.id, fromAccountID: fromID, toAccountID: toID, amount: parsed, occurredAt: occurredAt, note: note.nilIfBlank, expectedVersion: editing?.version)) { onSaved(); dismiss() }
    }
}

extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : trimmingCharacters(in: .whitespacesAndNewlines) }
}
