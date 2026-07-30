import Foundation
import SwiftUI

/// Источник состояния для окна.
///
/// Раздел 5.2 требует внедрять зависимость, а не переключать поведение
/// флагом внутри типа. Здесь то же правило, но для состояния, а не для
/// путей: боевая модель читает диск и держит наблюдателя, модель для
/// картинок отдаёт заданное и не делает ничего. Окно между ними не
/// различает — у него нет ветки «если это снимок экрана».
@MainActor
class StatusModel: ObservableObject {
    @Published fileprivate(set) var snapshot: Snapshot?
    @Published fileprivate(set) var diagnostics: [ParseIssue] = []
    @Published fileprivate(set) var integrity: Installer.Integrity = .unknown
    @Published fileprivate(set) var containerExists = true
    @Published fileprivate(set) var statusLineIsOurs = true
    /// Готовая строка про наблюдателя: окну не нужно знать, откуда она.
    @Published fileprivate(set) var watcherSummary = ""
    /// Сообщение о последнем действии — установка, удаление, отказ.
    @Published var notice: String?

    let installer: Installer
    private let watcher: SnapshotWatcher
    private var observation: Task<Void, Never>?

    init(installer: Installer = .live(), watcher: SnapshotWatcher = SnapshotWatcher()) {
        self.installer = installer
        self.watcher = watcher
        watcherSummary = String(localized: "stopped")
    }

    // MARK: Жизненный цикл

    func start() {
        watcher.start()
        refresh()
        // Наблюдатель — отдельный объект со своими публикациями; окно
        // подписано на модель, поэтому переносим их сюда.
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

    // MARK: Действия

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

/// Модель с заданным состоянием — для снятия картинок.
///
/// Диск не читает и наблюдателя не заводит: у неё просто нечего запускать.
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
