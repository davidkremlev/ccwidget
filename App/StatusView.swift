import SwiftUI
import WidgetKit

/// Этап 2: окно приложения нужно ровно для двух вещей — зарегистрировать
/// расширение виджета в системе и показать путь контейнера, который
/// подставляется в шаблон экспортёра. Онбординг из раздела 11 — этап 6.
struct StatusView: View {
    @State private var containerPath = "—"
    @State private var status = "—"
    @State private var diagnostics: [ParseIssue] = []
    @StateObject private var watcher = SnapshotWatcher()
    @State private var showsRemoval = false
    @State private var removesHistory = false
    @State private var removalNote: String?
    private let installer = Installer.live()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gauge for Claude Code")
                .font(.title2.weight(.semibold))

            GroupBox("Exchange directory") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: containerPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)

                    // Раздел 2.2: контейнер заводит система при первом
                    // запуске расширения, сами мы его не создаём.
                    if !SnapshotStore.widgetContainerExists {
                        Label(
                            "Add the widget to your desktop first, then run setup again.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Snapshot") {
                Text(verbatim: status)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Единственное место, где отброшенное при разборе поле видно
            // без Console.app. В норме этого блока нет вовсе.
            if !diagnostics.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            "\(diagnostics.count) field(s) dropped while parsing",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)

                        ForEach(diagnostics, id: \.field) { issue in
                            Text(verbatim: issue.summary)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Раздел 7 отчёта: приложение кладёт исполняемый файл
            // в автозапуск и обязано замечать его подмену.
            integrityNote

            GroupBox("Watcher") {
                Text(verbatim: watcherStatus)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Refresh") { reload() }
                Button("Reload widget") {
                    WidgetCenter.shared.reloadAllTimelines()
                }
                Spacer()
                Button("Remove…", role: .destructive) { showsRemoval = true }
            }

            if let removalNote {
                Text(verbatim: removalNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            reload()
            watcher.start()
        }
        // Без этого источники DispatchSource переживают закрытие окна,
        // а два дескриптора O_EVTONLY остаются открытыми навсегда.
        .onDisappear { watcher.stop() }
        .confirmationDialog("Remove ccwidget?", isPresented: $showsRemoval, titleVisibility: .visible) {
            Button("Remove, keep history", role: .destructive) { runRemoval(history: false) }
            Button("Remove and delete history", role: .destructive) { runRemoval(history: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    @ViewBuilder
    private var integrityNote: some View {
        switch installer.checkIntegrity() {
        case .changed:
            Label("The exporter on disk differs from the one this app installed. Something else changed it.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .missing:
            Label("The exporter is missing. Run setup again.", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .unknown, .matches:
            EmptyView()
        }
    }

    /// Что именно исчезнет — до того, как пользователь подтвердит.
    private var removalMessage: String {
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

    private func runRemoval(history: Bool) {
        do {
            let report = try installer.uninstall(removingHistory: history)
            var note = [String(localized: "Removed.")]
            if let backup = report.backup {
                note.append(String(localized: "Settings backed up as \(backup.lastPathComponent)."))
            }
            removalNote = note.joined(separator: " ")
            reload()
        } catch {
            removalNote = error.localizedDescription
        }
    }

    private var watcherStatus: String {
        let last = watcher.lastReload.map { $0.formatted(date: .omitted, time: .standard) } ?? "—"
        let fresh = watcher.freshness.map { String(describing: $0) } ?? "—"
        return """
            running   \(watcher.isRunning)
            reloads   \(watcher.reloadCount), last at \(last)
            freshness \(fresh)
            """
    }

    private func reload() {
        let store = SnapshotStore.default()
        containerPath = store.containerURL.path
        do {
            let snapshot = try store.load()
            diagnostics = snapshot.diagnostics
            let week = snapshot.limits.sevenDay.map { "\($0.usedPercentage)% used" } ?? "—"
            status = """
                captured  \(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))
                week      \(week)
                context   \(snapshot.context?.usedPercentage.map { "\($0)%" } ?? "—")
                project   \(snapshot.project?.name ?? "—")
                """
        } catch {
            status = "\(error)"
        }
    }
}
