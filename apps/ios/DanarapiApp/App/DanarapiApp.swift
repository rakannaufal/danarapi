import SwiftUI

@main
struct DanarapiApp: App {
    @State private var app = AppModel.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Color.danarapiPrimary)
                .scrollContentBackground(.hidden)
                .preferredColorScheme(app.colorScheme)
                .environment(\.timeZone, TimeZone(identifier: app.timezone) ?? TimeZone(identifier: "Asia/Jakarta")!)
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
                    case .background:
                        app.privacyCoverVisible = true
                        app.pauseOutboxRetry()
                        app.lockIfNeeded()
                    case .inactive:
                        app.privacyCoverVisible = true
                        app.pauseOutboxRetry()
                        if !app.isAuthenticating { app.lockIfNeeded() }
                    case .active:
                        app.privacyCoverVisible = false
                        if !app.isStarting { Task { await app.refresh() } }
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
                Image("AppLogo").renderingMode(.original).resizable().scaledToFit().frame(width: 96, height: 96)
                Image("danarapi_text").renderingMode(.original).resizable().scaledToFit().frame(width: 180, height: 42)
            }
        }
    }
}
