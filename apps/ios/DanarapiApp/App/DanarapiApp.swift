import SwiftUI

@main
struct DanarapiApp: App {
    @State private var app = AppModel.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.colorScheme)
                .environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
                .environment(\.locale, Locale(identifier: "id_ID"))
                .overlay {
                    if app.privacyCoverVisible {
                        PrivacyCoverView()
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }
                }
                .task { await app.start() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background, .inactive:
                        app.privacyCoverVisible = true
                        app.pauseOutboxRetry()
                        app.lockIfNeeded()
                    case .active:
                        app.privacyCoverVisible = false
                        Task { await app.refresh() }
                    @unknown default: break
                    }
                }
        }
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Color.danarapiCanvas.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.danarapiPrimary)
                Text("Danarapi")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.danarapiInk)
            }
        }
    }
}
