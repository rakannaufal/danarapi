import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private var content: [ProductCatalog.OnboardingStep] { ProductCatalog.bundled?.onboarding ?? [] }
    private var lastPage: Bool { content.isEmpty || page >= content.count - 1 }

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                TabView(selection: $page) {
                    ForEach(content.indices, id: \.self) { index in
                        ScrollView {
                            VStack(spacing: 24) {
                                Image(content[index].image).renderingMode(.original).resizable().scaledToFit()
                                    .frame(width: min(max(geometry.size.width - 48, 0), 300), height: min(geometry.size.height * 0.55, 260))
                                    .accessibilityHidden(true)
                                Text(content[index].title).font(.title.bold()).foregroundStyle(Color.danarapiInk).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                Text(content[index].description).font(.body).foregroundStyle(Color.danarapiMuted).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(24).frame(maxWidth: .infinity)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            HStack(spacing: 8) {
                ForEach(content.indices, id: \.self) { index in
                    Capsule().fill(index == page ? Color.danarapiPrimary : Color.danarapiBorder).frame(width: index == page ? 24 : 8, height: 8)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("Langkah \(page + 1) dari \(content.count)")
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Kembali") { if reduceMotion { page -= 1 } else { withAnimation(.easeOut(duration: DesignTokens.motion)) { page -= 1 } } }.buttonStyle(.bordered).frame(minHeight: 44)
                    }
                    Button(lastPage ? "Mulai mencatat" : "Lanjut") {
                        if !lastPage {
                            if reduceMotion { page += 1 } else { withAnimation(.easeOut(duration: DesignTokens.motion)) { page += 1 } }
                        }
                        else { app.completeOnboarding() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Button { app.completeOnboarding() } label: {
                    Text("Lewati tur")
                        .foregroundStyle(Color.danarapiPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ProductLinksView()
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .background { BrandBackgroundView().ignoresSafeArea() }
    }
}

struct AuthView: View {
    @Environment(AppModel.self) private var app
    private var welcome: ProductCatalog.Welcome? { ProductCatalog.bundled?.welcome }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                BrandIdentityView().padding(.bottom, 8)
                VStack(alignment: .leading, spacing: 8) {
                    Text(welcome?.headline ?? "Keuangan rapi,\nhari lebih tenang.").font(.largeTitle.bold()).foregroundStyle(Color.danarapiInk).frame(maxWidth: .infinity)
                    Text(app.requiresReauthentication ? welcome?.reauthenticationMessage ?? "Masuk kembali dengan akun yang sama." : welcome?.subtitle ?? "Catat, rencanakan, dan bagi tagihan dengan mudah.").foregroundStyle(Color.danarapiMuted).frame(maxWidth: .infinity)
                }.multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    ProviderLoginButton(isBusy: app.isAuthenticating) { app.startGoogleSignIn() }
                }.disabled(app.isAuthenticating || app.isLoading || !app.cloudReceiptScanConfigured)
                if app.isAuthenticating {
                    Button("Batalkan login") { app.cancelSignIn() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("auth.cancel")
                }
                if !app.cloudReceiptScanConfigured { Text("Login belum tersedia. Coba Demo tanpa akun.").font(.caption).foregroundStyle(Color.danarapiMuted) }
                if !app.requiresReauthentication {
                    Button("Coba Demo tanpa akun") { Task { await app.startDemo() } }.frame(maxWidth: .infinity, minHeight: 44).disabled(app.isAuthenticating)
                }
                Text(welcome?.disclaimer ?? "Pencatat keuangan, bukan layanan pembayaran.").font(.caption).foregroundStyle(Color.danarapiMuted).multilineTextAlignment(.center)
                ProductLinksView().frame(maxWidth: .infinity)
            }.padding(24)
        }.background { BrandBackgroundView().ignoresSafeArea() }
    }

}

private struct ProviderLoginButton: View {
    let isBusy: Bool
    let action: () -> Void

    private let title = "Lanjutkan dengan Google"

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let logo = UIImage(named: "GoogleSignInLogo") { Image(uiImage: logo).renderingMode(.original).resizable().scaledToFit() }
                }.frame(width: 24, height: 24).accessibilityHidden(true)
                Text(isBusy ? "Menghubungkan…" : title)
                    .font(.custom("GoogleSans-Medium", size: 18, relativeTo: .headline))
                    .lineLimit(1).minimumScaleFactor(0.85).frame(maxWidth: .infinity)
                Group {
                    if isBusy { ProgressView().tint(.black) }
                    else { Color.clear }
                }.frame(width: 24, height: 24).accessibilityHidden(true)
            }
        }
        .buttonStyle(ProviderLoginButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isBusy ? "Menghubungkan" : "")
        .accessibilityIdentifier("auth.google")
    }
}

private struct ProviderLoginButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var minimumHeight = 56.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.black : Color(white: 0.4))
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: minimumHeight)
            .background(configuration.isPressed ? Color(white: 0.96) : .white, in: Capsule())
            .overlay(Capsule().stroke(Color(red: 116 / 255, green: 119 / 255, blue: 117 / 255), lineWidth: 1))
            .contentShape(Capsule())
    }
}
