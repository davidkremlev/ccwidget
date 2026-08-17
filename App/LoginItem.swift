import Foundation
import ServiceManagement

/// Whether this app starts with the session, and what to say about it.
///
/// **Why the app and not a helper.** The widget can only be reloaded by the app
/// itself: an auxiliary executable inside the same bundle is refused by
/// WidgetKit — `ChronoCoreErrorDomain` 27 — and a reload from it changes
/// nothing. Measured, `SPEC` 2.4, and `Tools/ccwidget-widgetkit-probe` says so
/// on demand. So background freshness is this app running in the background,
/// and the thing that arranges that is `SMAppService.mainApp`.
///
/// **What it buys, and what it does not.** With nothing running, WidgetKit comes
/// back on its own about every half hour, so the tile can be that stale. The
/// watcher inside this app notices a new snapshot and asks for a reload.
///
/// How often that reload is allowed depends on where the app is. Apple exempts
/// reloads made "while the widget's containing app is in the foreground" from
/// the daily budget of 40 to 70, so in front the watcher may ask every minute;
/// behind, every reload is paid for and it waits a quarter of an hour and only
/// for a change in the numbers. Section 2.3, and the arithmetic that forced it
/// is in `SnapshotWatcher.backgroundReloadInterval`.
///
/// So this buys a tile that follows real changes within a quarter of an hour
/// instead of within half an hour of whenever the system feels like asking —
/// and a tile that keeps up minute by minute whenever the app is in front,
/// which it could already do. Less than the first version of this comment
/// claimed, and it claimed it in the window as well.
///
/// **What it costs, and why it is off by default.** A login item is a thing
/// somebody has to trust: it runs without being asked, on every session, for
/// ever. `SPEC` 13 says asking for that before a product has shown itself is
/// premature, and being off until switched on is how that is honoured.
struct LoginItem {
    /// The three things this can be, given names of our own.
    ///
    /// **Three, not four, and the fourth is the story.** `SMAppService` reports
    /// four statuses and the first version of this type mirrored them, mapping
    /// `notFound` to "unavailable — macOS cannot find the background job" and
    /// hiding the switch in that state. Which made the feature unreachable for
    /// everybody, because `notFound` is what `mainApp` reports **before it has
    /// ever been registered** — the state every user starts in.
    ///
    /// Measured, and it contradicts the documentation: Apple's page for
    /// `notFound` says "an error occurred and the framework couldn't find this
    /// service", and a probe inside the bundle says
    ///
    ///     before:   notFound
    ///     register: succeeded
    ///     after:    enabled
    ///
    /// After unregistering, the status is `notRegistered` rather than
    /// `notFound`. So the two differ only in whether the app was ever
    /// registered, which is a distinction with no consequence for anybody, and
    /// `CLAUDE.md` says to collapse those rather than keep them. Both are off.
    ///
    /// A real failure is not a status. It arrives as a thrown error from
    /// `register()`, and the window reports what it says.
    enum State: Equatable {
        /// Not running at login. The tile is as fresh as WidgetKit feels like.
        case off
        /// Registered and allowed to run.
        case on
        /// Registered, and macOS wants the person to allow it in Settings.
        case waitingForApproval

        func detail(locale: Locale = .autoupdatingCurrent) -> String {
            var resource: LocalizedStringResource
            switch self {
            case .off:
                resource = LocalizedStringResource("off — the widget updates about every half hour")
            case .on:
                // Two numbers because there are two regimes, and saying only the
                // good one would be an advertisement. A reload is free while the
                // app is in front and comes out of a 40-to-70-a-day budget when
                // it is not, so behind your terminal the watcher waits — see
                // `SnapshotWatcher.backgroundReloadInterval` and `SPEC` 2.3.
                resource = LocalizedStringResource("on — within a minute while this app is in front, about every 15 minutes behind it")
            case .waitingForApproval:
                resource = LocalizedStringResource("waiting for your approval in System Settings")
            }
            resource.locale = locale
            return String(localized: resource)
        }

        /// Whether the person has to go somewhere else to finish this.
        var needsSettings: Bool { self == .waitingForApproval }

        /// Whether the switch reads as on. Waiting for approval counts: the
        /// registration happened, and a switch that flicked itself back would
        /// say the opposite.
        var isOn: Bool { self != .off }
    }

    /// Injected, so the states can be produced without three machines.
    /// Section 5.2 again: the live one asks `SMAppService`, a check hands over
    /// whatever it wants to see.
    var read: () -> SMAppService.Status
    var enable: () throws -> Void
    var disable: () throws -> Void

    static func live() -> LoginItem {
        LoginItem(
            read: { SMAppService.mainApp.status },
            enable: { try SMAppService.mainApp.register() },
            disable: { try SMAppService.mainApp.unregister() }
        )
    }

    var state: State {
        switch read() {
        case .enabled: return .on
        case .requiresApproval: return .waitingForApproval
        case .notRegistered, .notFound: return .off
        @unknown default:
            // Something the framework knows and this build does not. Off is the
            // safe reading: it offers the switch, and switching it on either
            // works or throws something the window can repeat.
            return .off
        }
    }

    /// Opening the Login Items pane, which `SMAppService` does itself.
    ///
    /// It used to be a hand-written `x-apple.systempreferences:` URL — an
    /// undocumented string that would break silently the day Apple renamed the
    /// pane. `openSystemSettingsLoginItems()` is on the same documentation page
    /// as everything else here and was simply not read.
    var openSettings: () -> Void = { SMAppService.openSystemSettingsLoginItems() }
}
