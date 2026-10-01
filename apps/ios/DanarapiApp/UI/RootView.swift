import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color.danarapiCanvas.ignoresSafeArea()
            switch app.mode {
            case .signedOut:
                if app.onboardingCompleted { AuthView() } else { OnboardingView() }
            case .demo, .authenticated:
                if app.requiresReauthentication { AuthView().disabled(app.isLocked).accessibilityHidden(app.isLocked) }
                else {
                    MainTabView()
                        .disabled(app.isLoading || app.isLocked)
                        .accessibilityHidden(app.isLocked)
                }
            }

            if app.isLoading {
                ProgressView("Menyiapkan data…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityAddTraits(.updatesFrequently)
            }

            if app.isLocked {
                LockView()
            }
        }
        .alert("Belum berhasil", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) {
            Button("Tutup", role: .cancel) { app.errorMessage = nil }
        } message: { Text(app.errorMessage ?? "") }
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
