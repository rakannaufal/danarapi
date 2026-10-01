import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let content = [
        ("Uangmu lebih mudah dipahami", "Catat transaksi. Atur anggaran. Capai target Anda.", "wallet.pass.fill", Color.danarapiMint),
        ("Periksa sebelum disimpan", "Impor foto, PDF, atau teks. Bukti membantu pencatatan, bukan pembayaran.", "doc.text.magnifyingglass", Color.danarapiSky),
        ("Coba tanpa akun", "Jelajahi Demo dengan data contoh. Tidak perlu mendaftar.", "sparkles", Color.danarapiSun)
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(content.indices, id: \.self) { index in
                    VStack(spacing: 28) {
                        Spacer()
                        ZStack {
                            RoundedRectangle(cornerRadius: 42, style: .continuous).fill(content[index].3).frame(width: 190, height: 190)
                            Image(systemName: content[index].2).font(.system(size: 70, weight: .medium)).foregroundStyle(Color.danarapiInk)
                        }
                        Text(content[index].0).font(.largeTitle.bold()).foregroundStyle(Color.danarapiInk).multilineTextAlignment(.center)
                        Text(content[index].1).font(.body).foregroundStyle(Color.danarapiMuted).multilineTextAlignment(.center).lineSpacing(4)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: 12) {
                Button(page == content.count - 1 ? "Buat akun" : "Lanjut") {
                    if page < content.count - 1 {
                        if reduceMotion { page += 1 } else { withAnimation(.easeOut(duration: DesignTokens.motion)) { page += 1 } }
                    }
                    else { app.onboardingCompleted = true }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Lewati tur") { app.onboardingCompleted = true }
                    .frame(minHeight: 44)
                Button("Coba Demo") { Task { await app.startDemo() } }
                    .font(.headline).frame(minHeight: 44)
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
}

struct AuthView: View {
    @Environment(AppModel.self) private var app
    @State private var isAuthenticating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 40)
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 44)).foregroundStyle(Color.danarapiPrimary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selamat datang").font(.largeTitle.bold()).foregroundStyle(Color.danarapiInk)
                    Text(app.requiresReauthentication ? "Masuk kembali dengan akun yang sama." : "Satu akun untuk semua catatanmu.").foregroundStyle(Color.danarapiMuted)
                }
                VStack(spacing: 12) {
                    ProviderLoginButton(isBusy: isAuthenticating) { authenticate() }
                }.disabled(isAuthenticating || app.isLoading || !app.cloudReceiptScanConfigured)
                if !app.cloudReceiptScanConfigured { Text("Login belum tersedia. Coba Demo tanpa akun.").font(.caption).foregroundStyle(Color.danarapiMuted) }
                if !app.requiresReauthentication {
                    Button("Coba Demo tanpa akun") { Task { await app.startDemo() } }.frame(maxWidth: .infinity, minHeight: 44).disabled(isAuthenticating)
                }
                Text("Danarapi mencatat keuangan, bukan memproses pembayaran.").font(.caption).foregroundStyle(Color.danarapiMuted)
            }.padding(24)
        }.background(Color.danarapiCanvas)
    }

    private func authenticate() {
        isAuthenticating = true
        Task { _ = await app.signIn(provider: "google"); isAuthenticating = false }
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
