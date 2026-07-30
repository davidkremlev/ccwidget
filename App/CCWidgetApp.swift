import SwiftUI

@main
struct CCWidgetApp: App {
    var body: some Scene {
        Window("Usage Widget for Claude Code", id: "main") {
            RootView()
        }
        .windowResizability(.contentSize)
    }
}

/// Onboarding stays up until the exporter is wired into the status line and
/// the first snapshot has arrived. After that, the ordinary status window.
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
        // Setup can happen in another process — the user may have edited
        // statusLine by hand — so re-check whenever we regain focus.
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
