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
/// **What it buys.** With nothing running, WidgetKit comes back on its own about
/// every half hour, so the tile can be that stale. The watcher inside this app
/// notices a new snapshot within a minute and asks for a reload — rationed, per
/// section 2.3. Registered as a login item, that happens whether or not anybody
/// has a window open.
///
/// **What it costs, and why it is off by default.** A login item is a thing
/// somebody has to trust: it runs without being asked, on every session, for
/// ever. `SPEC` 13 says asking for that before a product has shown itself is
/// premature, and being off until switched on is how that is honoured.
struct LoginItem {
    /// The four things `SMAppService` can be, given names of our own.
    ///
    /// Named rather than passed through, for the reason `CLAUDE.md` gives about
    /// observability: `SMAppService.Status` is an imported enum whose cases
    /// nothing here would ever be asked to produce, and the window has to say
    /// something different for each of them. `requiresApproval` in particular is
    /// not a failure — it means macOS is waiting for the person, and the only
    /// useful answer is to say where.
    enum State: Equatable {
        /// Not registered. The tile is as fresh as WidgetKit feels like.
        case off
        /// Registered and allowed to run.
        case on
        /// Registered, and macOS wants the person to allow it in Settings.
        case waitingForApproval
        /// macOS cannot find the job this app declares. A bundle that was
        /// assembled wrongly, or moved somewhere the system will not look.
        case unavailable

        func detail(locale: Locale = .autoupdatingCurrent) -> String {
            var resource: LocalizedStringResource
            switch self {
            case .off:
                resource = LocalizedStringResource("off — the widget updates about every half hour")
            case .on:
                resource = LocalizedStringResource("on — the widget updates within a minute")
            case .waitingForApproval:
                resource = LocalizedStringResource("waiting for your approval in System Settings")
            case .unavailable:
                resource = LocalizedStringResource("unavailable — macOS cannot find the background job")
            }
            resource.locale = locale
            return String(localized: resource)
        }

        /// Whether the window offers the switch at all. There is nothing to
        /// switch when the system cannot see the job.
        var canBeChanged: Bool { self != .unavailable }

        /// Whether the person has to go somewhere else to finish this.
        var needsSettings: Bool { self == .waitingForApproval }
    }

    /// Injected, so the four states can be produced without four machines.
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
        case .notRegistered: return .off
        case .enabled: return .on
        case .requiresApproval: return .waitingForApproval
        case .notFound: return .unavailable
        @unknown default:
            // A state this build has no words for. `.unavailable` is the honest
            // answer: something is true of the job that this app cannot explain,
            // and offering a switch for it would be pretending otherwise.
            return .unavailable
        }
    }

    /// Where macOS puts the switch when it wants the person to confirm.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}
