import Foundation
import SwiftUI

/// The window's source of state.
///
/// Section 5.2 requires injecting a dependency rather than switching behaviour
/// on a flag inside the type. Same rule here, applied to state instead of
/// paths: the live model follows the watcher and owns it, while the one used
/// for screenshots returns what it was given and starts nothing. The window
/// cannot tell them apart — it has no "if this is a screenshot" branch.
///
/// The model does not read the snapshot itself. The watcher already reads it
/// on every change, and a second reader would only add a second answer to a
/// question that has one.
@MainActor
class StatusModel: ObservableObject {
    @Published fileprivate(set) var snapshot: Snapshot?
    @Published fileprivate(set) var diagnostics: [ParseIssue] = []
    @Published fileprivate(set) var integrity: Installer.Integrity = .unknown
    @Published fileprivate(set) var containerExists = true
    @Published fileprivate(set) var statusLineIsOurs = true
    /// A ready-made line about the watcher: the window need not know where
    /// it came from.
    @Published fileprivate(set) var watcherSummary = ""
    /// The moment the window should treat as "now" when it renders an age.
    /// It advances on the watcher's tick, which reads nothing.
    @Published fileprivate(set) var now = Date()
    /// The outcome of the last action — install, remove, or a failure.
    @Published var notice: String?

    let installer: Installer
    private let watcher: SnapshotWatcher
    private var observation: Task<Void, Never>?

    init(installer: Installer = .live(), watcher: SnapshotWatcher = SnapshotWatcher()) {
        self.installer = installer
        self.watcher = watcher
        watcherSummary = String(localized: "stopped")
    }

    // MARK: Lifecycle

    func start() {
        // Subscribe before starting: the watcher publishes its first read from
        // inside start(), and a subscriber attached afterwards would sit on an
        // empty window until the next write — which, if Claude Code is idle,
        // may be hours.
        observation = Task { @MainActor [weak self] in
            guard let watcher = self?.watcher else { return }
            for await state in watcher.$state.values {
                guard let self else { return }
                self.adopt(state)
            }
        }
        watcher.start()
        refreshInstallState()
    }

    func stop() {
        observation?.cancel()
        observation = nil
        watcher.stop()
        adopt(watcher.state)
    }

    /// The Refresh button. A manual duplicate of what the watcher does on its
    /// own — kept because the install state has no file to watch, and because
    /// a button that visibly does something is worth more than an explanation
    /// of why it is unnecessary.
    func refresh() {
        watcher.handleChange(reason: "manual refresh", force: false)
        refreshInstallState()
    }

    private func refreshInstallState() {
        integrity = installer.checkIntegrity()
        containerExists = installer.widgetContainerExists
        statusLineIsOurs = installer.statusLineState() == .ours
    }

    private func adopt(_ state: WatcherState) {
        snapshot = state.snapshot
        diagnostics = state.snapshot?.diagnostics ?? []
        now = state.now
        watcherSummary = summarize(state)
    }

    private func summarize(_ state: WatcherState) -> String {
        guard state.isRunning else {
            return String(localized: "stopped")
        }
        guard let last = state.lastReload else {
            return String(localized: "running · no reloads yet")
        }
        let moment = last.formatted(date: .omitted, time: .shortened)
        return String(localized: "running · \(state.reloadCount) reloads · last \(moment)")
    }

    // MARK: Actions

    func install() {
        do {
            let report = try installer.install()
            notice = report.backup.map {
                String(localized: "Settings backed up as \($0.lastPathComponent).")
            }
            refresh()
        } catch {
            notice = error.localizedDescription
        }
    }

    func uninstall(removingHistory: Bool) {
        do {
            let report = try installer.uninstall(removingHistory: removingHistory)
            var parts = [String(localized: "Removed.")]
            if let backup = report.backup {
                parts.append(String(localized: "Settings backed up as \(backup.lastPathComponent)."))
            }
            if report.statusLineRestored != nil {
                // Said out loud because it is the opposite of what removal used
                // to do, and because a person who installed this on top of an
                // existing status line has been waiting to get it back.
                parts.append(String(localized: "The status line you had before is back."))
            }
            if report.editWasSurgical == false {
                // The same sentence installation shows, for the same reason:
                // the file was rebuilt and somebody's formatting is gone.
                parts.append(String(localized: "settings.json had to be rewritten, so key order and indentation changed. The backup has the original."))
            }
            notice = parts.joined(separator: " ")
            refresh()
        } catch {
            notice = error.localizedDescription
        }
    }

    var removalMessage: String {
        let plan = installer.removalPlan()
        var lines: [String] = []
        if plan.removesStatusLine {
            lines.append(String(localized: "The statusLine key is removed from settings.json. Other keys are untouched."))
        }
        if let restored = plan.restoresStatusLine {
            lines.append(String(localized: "Your previous status line goes back: \(restored)"))
        }
        if plan.removesExporter {
            lines.append(String(localized: "~/.claude/ccwidget-export.py is deleted."))
        }
        if plan.historyLineCount > 0 {
            lines.append(String(localized: "\(plan.historyLineCount) history points exist; deleting them resets the forecast."))
        }
        lines.append(String(localized: "These have to be removed by hand: \(plan.manualLeftovers.joined(separator: ", "))"))
        return lines.joined(separator: "\n\n")
    }
}

/// A model with fixed state, for taking screenshots.
///
/// It reads no disk and starts no watcher: there is simply nothing to run.
@MainActor
final class FixedStatusModel: StatusModel {
    init(snapshot: Snapshot?, integrity: Installer.Integrity,
         containerExists: Bool = true, statusLineIsOurs: Bool = true,
         watcherSummary: String = "running · 3 reloads · last 14:02") {
        super.init()
        self.snapshot = snapshot
        self.diagnostics = snapshot?.diagnostics ?? []
        self.integrity = integrity
        self.containerExists = containerExists
        self.statusLineIsOurs = statusLineIsOurs
        self.watcherSummary = watcherSummary
    }

    override func start() {}
    override func stop() {}
    override func refresh() {}
}
