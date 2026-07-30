import Foundation
import SwiftUI

/// The window's source of state.
///
/// Section 5.2 requires injecting a dependency rather than switching behaviour
/// on a flag inside the type. Same rule here, applied to state instead of
/// paths: the live model reads the disk and owns the watcher, while the one
/// used for screenshots returns what it was given and starts nothing. The
/// window cannot tell them apart — it has no "if this is a screenshot" branch.
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
        watcher.start()
        refresh()
        // The watcher is a separate object with its own publications, and
        // the window subscribes to the model, so bring them across.
        observation = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.updateWatcherSummary()
            }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        watcher.stop()
        updateWatcherSummary()
    }

    func refresh() {
        snapshot = try? SnapshotStore.default().load()
        diagnostics = snapshot?.diagnostics ?? []
        integrity = installer.checkIntegrity()
        containerExists = installer.widgetContainerExists
        statusLineIsOurs = installer.statusLineState() == .ours
        updateWatcherSummary()
    }

    private func updateWatcherSummary() {
        guard watcher.isRunning else {
            watcherSummary = String(localized: "stopped")
            return
        }
        guard let last = watcher.lastReload else {
            watcherSummary = String(localized: "running · no reloads yet")
            return
        }
        let moment = last.formatted(date: .omitted, time: .shortened)
        watcherSummary = String(localized: "running · \(watcher.reloadCount) reloads · last \(moment)")
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
