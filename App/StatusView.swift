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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gauge for Claude Code")
                .font(.title2.weight(.semibold))

            GroupBox("Exchange directory") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(containerPath)
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
                Text(status)
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
                            Text(issue.summary)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Watcher") {
                Text(watcherStatus)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Refresh") { reload() }
                Button("Reload widget") {
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            reload()
            watcher.start()
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
        // Усечение делает приложение, а не виджет: виджет только читает.
        HistoryStore(store: store).truncateIfNeeded()
        do {
            let snapshot = try store.load()
            diagnostics = snapshot.diagnostics
            let week = snapshot.limits.sevenDay.map { "\($0.remainingPercentage)% left" } ?? "—"
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
