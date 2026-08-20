import AppKit
import SwiftUI

/// Whether a launch was somebody opening the app, or something else starting it.
///
/// A login item that opens a window at every login is the behaviour this project
/// would complain about in somebody else's app. The signal is documented:
/// `NSApplication.launchIsDefaultUserInfoKey`, "a Boolean value that indicates
/// if the app launch is a default launch" — `apple/appkit-launch-user-info-keys.md`
/// in the reference store.
///
/// Separate from the delegate so that it can be checked. The delegate then does
/// one thing with the answer.
enum LaunchKind {
    /// The key, read once on the main actor where AppKit keeps it, so the
    /// decision itself needs no actor at all — and can therefore be checked
    /// without one.
    @MainActor static var key: AnyHashable { NSApplication.launchIsDefaultUserInfoKey }

    /// Absent means a person did it: the key is only there when the system has
    /// something to say about the launch, and a missing key must not turn an
    /// ordinary launch into a hidden one.
    /// **Both conditions, and the second one was missing.** A launch nobody asked
    /// for is not enough on its own: `open /Applications/CCWidget.app` from a
    /// terminal is reported as not-default too — measured, the app hid itself on
    /// a launch that was very much a person's doing. So the app only stays out of
    /// the way when it is *also* registered to run at login, which is the only
    /// situation this exists for.
    ///
    /// What remains, and it is a small thing: a shell `open` with background
    /// updates on starts the app hidden. The Dock icon is there and clicking it
    /// brings the window. Whether a double-click in Finder counts as default is
    /// **not measured** — nothing here can simulate one — so if it does not, that
    /// is the same mild outcome.
    static func staysOutOfTheWay(userInfo: [AnyHashable: Any]?,
                                 key: AnyHashable,
                                 runsAtLogin: Bool) -> Bool {
        guard runsAtLogin else { return false }
        guard let value = userInfo?[key] as? Bool else { return false }
        return !value
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Said at `notice` rather than `info`: `.info` lives in a ring buffer the
        // whole machine shares and is gone within minutes, which this project
        // has already been caught by twice. What the window says about the
        // background item has to be answerable from a log an hour later.
        let item = LoginItem.live().state
        ccwidgetStoreLog.notice(
            "login item: \(item.detail(locale: Locale(identifier: "en_US_POSIX")), privacy: .public)"
        )
        guard LaunchKind.staysOutOfTheWay(userInfo: notification.userInfo,
                                          key: LaunchKind.key,
                                          runsAtLogin: item.isOn) else { return }
        // Hidden rather than closed: the window goes on existing, so clicking
        // the Dock icon brings it back with nothing to reopen. Closing it would
        // mean teaching the app how to make a second one, which is a way to
        // spend an afternoon on a window nobody asked to see.
        ccwidgetStoreLog.info("launched without being asked; staying hidden")
        NSApp.hide(nil)
    }
}

@main
struct CCWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// One model for the whole app, started when the app starts rather than when
    /// a window appears.
    ///
    /// It used to be created by `StatusView` and started in its `onAppear`,
    /// which was right while the app was only ever a window somebody opened: no
    /// window, nothing to keep fresh. It is wrong now that the app can be
    /// launched at login to do exactly that — the watcher would never start, and
    /// the login item would be a process that runs and achieves nothing.
    /// The live watcher is built here rather than defaulted inside itself,
    /// because only the app knows it is the app. `NSApplication.isActive`
    /// decides whether a widget reload is free or comes out of the daily budget
    /// — section 2.3 — and asking that question from anywhere other than a real
    /// running app is both wrong and, in a process with no GUI session, slow
    /// enough to hang.
    @StateObject private var model = StatusModel(
        watcher: SnapshotWatcher(isForeground: { NSApplication.shared.isActive }))

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
        // Title and toolbar on one line. The unified style centres the title
        // between the traffic lights and the items and gives it what is left
        // over, which at this window's width is less than the title needs:
        // measured, "Usage Widget for Claude…" at 440 points. Compact puts the
        // title at the leading edge and lets it run up to the items.
        .windowToolbarStyle(.unifiedCompact)
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
                // The completion is the third way the answer can change; the
                // other two — appearing, and the app becoming active — cannot
                // see a setup that finishes inside this very window.
                OnboardingView(onFinished: { recheck("the setup screen's button") })
            }
        }
        .onAppear { recheck("appearing") }
        // Setup can happen in another process — the user may have edited
        // statusLine by hand — so re-check whenever we regain focus.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            recheck("activation")
        }
    }

    /// One place for the three triggers, and a log line when the answer
    /// changes — naming which trigger changed it.
    ///
    /// The line exists because its absence cost half an hour on 21 August
    /// 2026: the window swapped from the setup screen to the status view
    /// while two of the triggers were plausible, and nothing recorded which
    /// one had fired. The trigger is a difference visible only to a
    /// maintainer, and that is a legitimate difference to keep. Silent when
    /// nothing changes: activation fires on every ⌘-Tab, and a log that says
    /// "still configured" a hundred times a day is a log nobody reads.
    private func recheck(_ trigger: String) {
        let was = isConfigured
        isConfigured = Self.configured
        if isConfigured != was {
            ccwidgetStoreLog.notice(
                "window switched to \(isConfigured ? "status" : "setup", privacy: .public) on \(trigger, privacy: .public)"
            )
        }
    }

    private static var configured: Bool {
        Installer.live().statusLineState() == .ours
            && (try? SnapshotStore.default().load()) != nil
    }
}
