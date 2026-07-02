import SwiftUI

@main
struct RunCockpitApp: App {
    @State private var app = AppState()

    init() {
        #if DEBUG
        gitRemoteNormalizeSelfCheck()
        sessionIdSelfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.theme, app.theme)
                .environment(\.locale, Locale(identifier: app.settings.language.rawValue))
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(app.theme.isDark ? .dark : .light)
                .task { app.start() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1180, height: 760)
    }
}
