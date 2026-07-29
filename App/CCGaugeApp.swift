import SwiftUI

@main
struct CCGaugeApp: App {
    var body: some Scene {
        Window("Gauge for Claude Code", id: "main") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}

/// Онбординг показывается, пока экспортёр не подключён к статуслайну
/// либо пока не пришёл первый снимок. Дальше — обычное окно состояния.
struct RootView: View {
    @State private var isConfigured = RootView.configured

    var body: some View {
        Group {
            if isConfigured {
                StatusView()
            } else {
                OnboardingView()
            }
        }
        .onAppear { isConfigured = Self.configured }
        // Настройка происходит в другом процессе (пользователь мог
        // прописать statusLine руками), поэтому проверяем на возврате фокуса.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            isConfigured = Self.configured
        }
    }

    private static var configured: Bool {
        Installer.live().statusLineState() == .ours
            && (try? SnapshotStore.default().load()) != nil
    }
}
