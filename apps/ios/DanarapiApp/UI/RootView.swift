import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        ZStack {
            Color.danarapiCanvas.ignoresSafeArea()
            if app.showsStartupScreen {
                StartupView()
            } else {
              switch app.mode {
            case .signedOut:
                AuthView()
            case .demo, .authenticated:
                if app.requiresReauthentication { AuthView().disabled(app.isLocked).accessibilityHidden(app.isLocked) }
                else if !app.hasLoadedDashboard {
                    ContentUnavailableView {
                        Label("Data belum dapat dimuat", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(app.dashboardError ?? "Hubungkan internet untuk memuat catatanmu.")
                    } actions: {
                        Button("Coba lagi") { Task { await app.refresh() } }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Keluar") { Task { _ = await app.logout() } }
                        ProductLinksView()
                    }
                    .disabled(app.isLoading || app.isLocked)
                    .accessibilityHidden(app.isLocked)
                }
                else if !app.onboardingCompleted {
                    OnboardingView()
                        .disabled(app.isLocked)
                        .accessibilityHidden(app.isLocked)
                }
                else {
                    MainTabView()
                        .disabled(app.isLoading || app.isLocked)
                        .accessibilityHidden(app.isLocked)
                }
              }
            }

            if app.isLoading && !app.showsStartupScreen {
                ProgressView("Menyiapkan data…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if app.isLocked {
                LockView()
            }
        }
        .background(KeyboardDismissalView().frame(width: 0, height: 0))
        .alert("Belum berhasil", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("Tutup", role: .cancel) { app.errorMessage = nil }
        } message: { Text(app.errorMessage ?? "") }
        .environment(\.timeZone, TimeZone(identifier: app.timezone) ?? TimeZone(identifier: "Asia/Jakarta")!)
        .sheet(item: $app.productPage) { route in
            NavigationStack { ProductPageView(pageID: route.id).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Selesai") { app.productPage = nil } } } }
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.danarapiInk)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.bottom, 84)
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        if app.toastMessage == toast { app.toastMessage = nil }
                    }
            }
        }
    }
}

private struct StartupView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .accessibilityLabel("Danarapi")
                .accessibilityIdentifier("startup.logo")
            Image("danarapi_text")
                .renderingMode(.original).resizable().scaledToFit()
                .frame(width: 170, height: 40)
                .accessibilityHidden(true)
            ProgressView()
                .tint(Color.danarapiMuted)
                .accessibilityLabel("Memuat catatan")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.danarapiCanvas)
    }
}

private struct LockView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        ZStack {
            Color.danarapiCanvas.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 38, weight: .semibold, design: .default))
                    .foregroundStyle(Color.danarapiPrimary)
                Text("Danarapi terkunci")
                    .font(.title.bold())
                Text("Buka kunci untuk melihat catatan Anda.")
                    .font(.body).foregroundStyle(Color.danarapiMuted).multilineTextAlignment(.center)
                Button("Buka dengan perangkat") { Task { await app.unlock() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(32)
        }
    }
}
