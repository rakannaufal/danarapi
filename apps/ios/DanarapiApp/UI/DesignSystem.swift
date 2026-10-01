import SwiftUI

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
    static let version = DesignTokenCatalog.bundled?.version ?? "1.2.0"
    static let cornerCard = CGFloat(DesignTokenCatalog.bundled?.radius["card"] ?? 20)
    static let cornerControl = CGFloat(DesignTokenCatalog.bundled?.radius["button"] ?? 12)
    static let gutter = CGFloat(DesignTokenCatalog.bundled?.layout["mobileGutter"] ?? 20)
    static let sectionGap = CGFloat(DesignTokenCatalog.bundled?.layout["sectionGap"] ?? 24)
    static let minimumTouch = CGFloat(DesignTokenCatalog.bundled?.touchTarget["minimum"] ?? 44)
    static let motion = (DesignTokenCatalog.bundled?.motion.normalMs ?? 240) / 1000
}

extension Color {
    static let danarapiCanvas = token("canvas", fallbackLight: 0xF5F5F7, fallbackDark: 0x111113)
    static let danarapiSurface = token("surface", fallbackLight: 0xFFFFFF, fallbackDark: 0x1C1C1E)
    static let danarapiInk = token("ink", fallbackLight: 0x1D1D1F, fallbackDark: 0xF5F5F7)
    static let danarapiMuted = token("muted", fallbackLight: 0x62626A, fallbackDark: 0xB0B0B8)
    static let danarapiBorder = token("border", fallbackLight: 0xDEDEE3, fallbackDark: 0x3B3B40)
    static let danarapiPrimary = token("primary", fallbackLight: 0x0066CC, fallbackDark: 0x80BAFF)
    static let danarapiOnPrimary = token("on-primary", fallbackLight: 0xFFFFFF, fallbackDark: 0x101C30)
    static let danarapiMint = token("primary-soft", darkName: "mint-surface", fallbackLight: 0xEAF2FF, fallbackDark: 0x222C37)
    static let danarapiSky = token("sky-soft", darkName: "sky-surface", fallbackLight: 0xF0F4FA, fallbackDark: 0x242B35)
    static let danarapiPeach = token("peach-soft", darkName: "peach-surface", fallbackLight: 0xFAF0F0, fallbackDark: 0x34282B)
    static let danarapiSun = token("sun-soft", darkName: "sun-surface", fallbackLight: 0xF7F4EA, fallbackDark: 0x323025)
    static let danarapiLavender = token("lavender-soft", darkName: "lavender-surface", fallbackLight: 0xF1EFF7, fallbackDark: 0x2C2837)
    static let danarapiIncome = token("income-ink", fallbackLight: 0x1C6B41, fallbackDark: 0x86D9A5)
    static let danarapiExpense = token("expense-ink", fallbackLight: 0xB32632, fallbackDark: 0xFFACB1)

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
            .padding(18)
            .background(color, in: RoundedRectangle(cornerRadius: DesignTokens.cornerCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.cornerCard, style: .continuous).stroke(Color.danarapiBorder.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    func danarapiCard(_ color: Color = .danarapiSurface) -> some View { modifier(CardStyle(color: color)) }
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
