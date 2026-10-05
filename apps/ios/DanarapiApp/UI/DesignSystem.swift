import SwiftUI
import UIKit

struct KeyboardDismissalView: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalAnchor { KeyboardDismissalAnchor(frame: .zero) }
    func updateUIView(_ uiView: KeyboardDismissalAnchor, context: Context) {}
    static func dismantleUIView(_ uiView: KeyboardDismissalAnchor, coordinator: ()) { uiView.detach() }
}

final class KeyboardDismissalAnchor: UIView, UIGestureRecognizerDelegate {
    private weak var attachedWindow: UIWindow?
    private weak var editingAtTouchStart: UIView?
    private lazy var outsideTap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard attachedWindow !== window else { return }
        detach()
        guard let window else { return }
        window.addGestureRecognizer(outsideTap)
        attachedWindow = window
    }

    func detach() {
        attachedWindow?.removeGestureRecognizer(outsideTap)
        attachedWindow = nil
        editingAtTouchStart = nil
    }

    static func isEditableTarget(_ view: UIView?) -> Bool {
        var candidate = view
        while let current = candidate {
            if current is UITextField || current is UITextView { return true }
            candidate = current.superview
        }
        return false
    }

    static func isEditableTarget(at point: CGPoint, in view: UIView) -> Bool {
        guard !view.isHidden, view.alpha > 0.01 else { return false }
        let inside = view.bounds.contains(point)
        if view.clipsToBounds && !inside { return false }
        if inside && (view is UITextField || view is UITextView) { return true }
        return view.subviews.contains { child in
            isEditableTarget(at: child.convert(point, from: view), in: child)
        }
    }

    private static func firstResponder(in view: UIView?) -> UIView? {
        guard let view else { return nil }
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let responder = firstResponder(in: child) { return responder }
        }
        return nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = attachedWindow else { return false }
        guard !Self.isEditableTarget(touch.view), !Self.isEditableTarget(at: touch.location(in: window), in: window) else { return false }
        editingAtTouchStart = Self.firstResponder(in: attachedWindow)
        return editingAtTouchStart != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    @objc private func dismissKeyboard() {
        guard let window = attachedWindow, let responder = editingAtTouchStart else { return }
        DispatchQueue.main.async { [weak window, weak responder] in
            guard let window, let responder, responder.isFirstResponder else { return }
            window.endEditing(true)
        }
    }
}

extension Budget {
    var progressColor: Color {
        if status == "over" { return .danarapiExpense }
        if status == "warning" { return Color(light: 0xD4A000, dark: 0xFFD60A) }
        return .danarapiPrimary
    }
}

struct DesignTokenCatalog: Decodable, Sendable {
    let version: String
    let color: [String: [String: String]]
    let space: [String: Double]
    let radius: [String: Double]
    let motion: Motion
    let touchTarget: [String: Double]
    let layout: [String: Double]

    struct Motion: Decodable, Sendable {
        let normalMs: Double
        let fastMs: Double
        let respectsReducedMotion: Bool
    }

    static let bundled: DesignTokenCatalog? = {
        guard let url = Bundle.main.url(forResource: "design-tokens", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DesignTokenCatalog.self, from: data)
    }()

    func hex(_ name: String, theme: String) -> UInt? {
        guard let raw = color[theme]?[name], raw.hasPrefix("#"), raw.count == 7 else { return nil }
        return UInt(raw.dropFirst(), radix: 16)
    }
}

enum DesignTokens {
    static let version = DesignTokenCatalog.bundled?.version ?? "1.4.0"
    static let cornerCard = CGFloat(DesignTokenCatalog.bundled?.radius["card"] ?? 28)
    static let cornerControl = CGFloat(DesignTokenCatalog.bundled?.radius["button"] ?? 24)
    static let gutter = CGFloat(DesignTokenCatalog.bundled?.layout["mobileGutter"] ?? 20)
    static let sectionGap = CGFloat(DesignTokenCatalog.bundled?.layout["sectionGap"] ?? 24)
    static let minimumTouch = CGFloat(DesignTokenCatalog.bundled?.touchTarget["minimum"] ?? 44)
    static let motion = (DesignTokenCatalog.bundled?.motion.normalMs ?? 240) / 1000
}

extension Color {
    static let danarapiCanvas = token("canvas", fallbackLight: 0xFBFCFB, fallbackDark: 0x0A1624)
    static let danarapiSurface = token("surface", fallbackLight: 0xFFFFFF, fallbackDark: 0x112433)
    static let danarapiInk = token("ink", fallbackLight: 0x18343B, fallbackDark: 0xF1FAF7)
    static let danarapiMuted = token("muted", fallbackLight: 0x49635D, fallbackDark: 0xAAC6BE)
    static let danarapiBorder = token("border", fallbackLight: 0xD8E4DE, fallbackDark: 0x2C4651)
    static let danarapiPrimary = token("primary", fallbackLight: 0x09746C, fallbackDark: 0x7BDDC2)
    static let danarapiOnPrimary = token("on-primary", fallbackLight: 0xFFFFFF, fallbackDark: 0x0A1624)
    static let danarapiMint = token("primary-soft", darkName: "mint-surface", fallbackLight: 0xBAF4DE, fallbackDark: 0x153B3B)
    static let danarapiSky = token("sky-soft", darkName: "sky-surface", fallbackLight: 0xEFF7F3, fallbackDark: 0x132D36)
    static let danarapiPeach = token("peach-soft", darkName: "peach-surface", fallbackLight: 0xFDCEB2, fallbackDark: 0x3A2B2A)
    static let danarapiSun = token("sun-soft", darkName: "sun-surface", fallbackLight: 0xFFF1E7, fallbackDark: 0x36312A)
    static let danarapiLavender = token("lavender-soft", darkName: "lavender-surface", fallbackLight: 0xF0F4F4, fallbackDark: 0x253543)
    static let danarapiIncome = token("income-ink", fallbackLight: 0x09746C, fallbackDark: 0x9DE4C0)
    static let danarapiExpense = token("expense-ink", fallbackLight: 0xA83245, fallbackDark: 0xFFB3B0)
    static let danarapiChartIncome = danarapiPrimary
    static let danarapiChartExpense = Color(light: 0xA84E37, dark: 0xFDCBAC)
    static let danarapiPeachInk = Color(light: 0x843B19, dark: 0xFDCBAC)
    static let danarapiBalanceStart = Color(light: 0x09746C, dark: 0x153B3B)
    static let danarapiBalanceEnd = Color(light: 0x064E49, dark: 0x112433)
    static let danarapiOnBalance = Color(light: 0xFFFFFF, dark: 0xF1FAF7)
    static let danarapiChartColors: [Color] = [
        danarapiPrimary,
        Color(light: 0x4D9A80, dark: 0x9DE4C0),
        Color(light: 0xCC9274, dark: 0xFDCBAC),
        Color(light: 0x8C9D6B, dark: 0xC6D49A),
        Color(light: 0xB57368, dark: 0xE6AAA0),
        Color(light: 0x4E7F8E, dark: 0x90C7CE)
    ]

    private static func token(_ name: String, darkName: String? = nil, fallbackLight: UInt, fallbackDark: UInt) -> Color {
        Color(light: DesignTokenCatalog.bundled?.hex(name, theme: "light") ?? fallbackLight,
              dark: DesignTokenCatalog.bundled?.hex(darkName ?? name, theme: "dark") ?? fallbackDark)
    }

    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light) })
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct CardStyle: ViewModifier {
    var color: Color = .danarapiSurface
    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(color, in: RoundedRectangle(cornerRadius: DesignTokens.cornerCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerCard, style: .continuous).stroke(Color.danarapiBorder.opacity(0.45), lineWidth: 0.5))
            .shadow(color: Color.danarapiPrimary.opacity(0.045), radius: 12, y: 4)
    }
}

enum AppSymbol: String, CaseIterable {
    case home = "house"
    case transactions = "arrow.left.arrow.right"
    case scan = "viewfinder"
    case reports = "chart.xyaxis.line"
    case settings = "gearshape"
    case appearance = "circle.lefthalf.filled"
    case hidden = "eye.slash"
    case time = "clock"
    case wallet = "wallet.bifold"
    case bank = "building.columns"
    case cash = "banknote"
    case income = "arrow.down"
    case expense = "arrow.up"
    case goal = "scope"
    case budget = "chart.pie"
    case category = "square.grid.2x2"
    case split = "person.2"
    case gallery = "photo.stack"
    case receipt = "doc.text.viewfinder"
    case privacy = "lock.shield"
}

struct CalculatorIcon: View {
    var body: some View {
        CalculatorOutline()
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 18, height: 24)
            .accessibilityHidden(true)
    }

    private struct CalculatorOutline: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addRoundedRect(in: CGRect(x: 1, y: 1, width: 16, height: 22), cornerSize: CGSize(width: 2.5, height: 2.5))
            path.addRoundedRect(in: CGRect(x: 4, y: 4, width: 10, height: 4), cornerSize: CGSize(width: 0.8, height: 0.8))
            for y in [12.0, 16.0, 20.0] {
                for x in [5.0, 9.0, 13.0] {
                    path.move(to: CGPoint(x: x - 0.3, y: y))
                    path.addLine(to: CGPoint(x: x + 0.3, y: y))
                }
            }
            return path.applying(CGAffineTransform(scaleX: rect.width / 18, y: rect.height / 24))
        }
    }
}

struct SymbolBadge: View {
    let symbol: String
    var color: Color = .danarapiPrimary
    var background: Color = .danarapiMint
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let symbol: AppSymbol
    var color: Color = .danarapiPrimary
    var background: Color = .danarapiMint

    var body: some View {
        Label { Text(title).foregroundStyle(Color.danarapiInk) } icon: {
            SymbolBadge(symbol: symbol.rawValue, color: color, background: background, size: 32)
        }
        .accessibilityLabel(title)
    }
}

struct BrandIdentityView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image("AppLogo").renderingMode(.original).resizable().scaledToFit().frame(width: 52, height: 52)
            Image("danarapi_text").renderingMode(.original).resizable().scaledToFit().frame(width: 180, height: 42)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Danarapi")
    }
}

private struct DanarapiSettingsActionKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var openDanarapiSettings: @MainActor () -> Void {
        get { self[DanarapiSettingsActionKey.self] }
        set { self[DanarapiSettingsActionKey.self] = newValue }
    }
}

private struct MainHeaderModifier: ViewModifier {
    @Environment(\.openDanarapiSettings) private var openSettings
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 7) {
                            Image("AppLogo").renderingMode(.original).resizable().scaledToFit().frame(width: 30, height: 30)
                            Image("danarapi_text").renderingMode(.original).resizable().scaledToFit().frame(width: 106, height: 27)
                        }.accessibilityElement(children: .ignore).accessibilityLabel("Danarapi")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: openSettings) { Image(systemName: AppSymbol.settings.rawValue).frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Pengaturan").accessibilityIdentifier("header.settings")
                    }
                }
        } else { content }
    }
}

extension View {
    func danarapiMainHeader(enabled: Bool = true) -> some View { modifier(MainHeaderModifier(enabled: enabled)) }
}

struct BrandBackgroundView: View {
    var body: some View {
        GeometryReader { geometry in
            Image("background").renderingMode(.original).resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.background(Color.danarapiCanvas).accessibilityHidden(true).allowsHitTesting(false)
    }
}

extension View {
    func danarapiCard(_ color: Color = .danarapiSurface) -> some View { modifier(CardStyle(color: color)) }
    func danarapiListSurface() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(16)
            .scrollContentBackground(.hidden)
            .background(Color.danarapiCanvas)
    }
}

struct InformationDisclosure: View {
    let title: String
    let message: String
    var body: some View {
        DisclosureGroup(title) {
            Text(message).font(.footnote).foregroundStyle(Color.danarapiMuted).padding(.top, 6)
        }
        .font(.subheadline)
        .tint(Color.danarapiPrimary)
        .frame(maxWidth: .infinity, minHeight: DesignTokens.minimumTouch, alignment: .leading)
    }
}

struct MoneyText: View {
    let amount: Int64
    var style: Font = .title2
    var color: Color = .danarapiInk
    @Environment(AppModel.self) private var app

    var body: some View {
        Text(app.hideAmounts ? "Rp••••••" : amount.idr)
            .font(style.monospacedDigit())
            
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .accessibilityLabel(app.hideAmounts ? "Nominal disembunyikan" : amount.idrAccessibility)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.minimumTouch)
            .padding(.horizontal, 16)
            .foregroundStyle(Color.danarapiOnPrimary)
            .background(Color.danarapiPrimary.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: DesignTokens.cornerControl, style: .continuous))
    }
}

extension Int64 {
    var idr: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.numberStyle = .currency
        formatter.currencySymbol = "Rp"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "Rp\(self)"
    }

    var idrAccessibility: String { "\(self) Rupiah" }
}
