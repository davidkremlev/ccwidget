import SwiftUI

@main
struct CCWidgetApp: App {
    /// One model for the whole app, started when the app starts rather than when
    /// a window appears.
    ///
    /// It used to be created by `StatusView` and started in its `onAppear`,
    /// which was right while the app was only ever a window somebody opened: no
    /// window, nothing to keep fresh. It is wrong now that the app can be
    /// launched at login to do exactly that — the watcher would never start, and
    /// the login item would be a process that runs and achieves nothing.
    @StateObject private var model = StatusModel()

    var body: some Scene {
        Window("Usage Widget for Claude Code", id: "main") {
            RootView(model: model)
                .task {
                    // Idempotent: `start()` is called here and never in a view,
                    // so opening and closing windows cannot start two watchers.
                    model.start()
                }
        }
        .windowResizability(.contentSize)
    }
}

/// Onboarding stays up until the exporter is wired into the status line and
/// the first snapshot has arrived. After that, the ordinary status window.
struct RootView: View {
    @State private var isConfigured = RootView.configured
    @ObservedObject var model: StatusModel

    var body: some View {
        Group {
            if isConfigured {
                StatusView(model: model)
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
