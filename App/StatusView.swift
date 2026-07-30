import SwiftUI
import WidgetKit

/// Окно приложения.
///
/// Его открывает клик по виджету — отменить это поведение macOS нельзя,
/// значит окно видит обычный пользователь, а не только разработчик.
/// Поэтому сверху состояние человеческим языком и те же полоски, что
/// в виджете, а диагностика убрана под «Details».
///
/// Полоски переиспользуют `GaugeRow` из расширения как есть: окно должно
/// выглядеть увеличенным виджетом, и совпадение цифр видно без чтения.
struct StatusView: View {
    @State private var snapshot: Snapshot?
    @State private var diagnostics: [ParseIssue] = []
    @State private var integrity: Installer.Integrity = .unknown
    @State private var showsDetails = false
    @State private var notice: String?
    @State private var showsRemoval = false
    @StateObject private var watcher = SnapshotWatcher()

    private let installer = Installer.live()
    /// Картинки рисуются в подставленном состоянии и не должны его
    /// перечитывать с диска при появлении.
    private let isSample: Bool

    /// Обычная точка входа.
    init() { isSample = false }

    /// Только для снятия картинок: окно рисуется в заданном состоянии,
    /// не дожидаясь `onAppear`. Тот же приём внедрения, что в разделе 5.2 —
    /// состояние приходит снаружи, а не добывается изнутри.
    init(sampleSnapshot: Snapshot?, sampleIntegrity: Installer.Integrity, expanded: Bool = false) {
        isSample = true
        _snapshot = State(initialValue: sampleSnapshot)
        _integrity = State(initialValue: sampleIntegrity)
        _showsDetails = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if integrity == .changed {
                tamperBanner
            }

            if let snapshot, state == .working || state == .outdated || state == .abandoned {
                rows(snapshot)
                quietLine(snapshot)
            } else {
                emptyState
            }

            Divider()
            bottomRow

            if showsDetails {
                details
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            guard !isSample else { return }
            reload()
            watcher.start()
        }
        .onDisappear { watcher.stop() }
        .confirmationDialog("Remove ccwidget?", isPresented: $showsRemoval, titleVisibility: .visible) {
            Button("Remove, keep history", role: .destructive) { runRemoval(history: false) }
            Button("Remove and delete history", role: .destructive) { runRemoval(history: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    // MARK: Состояние

    private enum WindowState {
        case needsWidget, needsSetup, waiting, working, outdated, abandoned
    }

    private var state: WindowState {
        if !isSample {
            if !installer.widgetContainerExists { return .needsWidget }
            if installer.statusLineState() != .ours { return .needsSetup }
        }
        guard let snapshot else { return .waiting }
        switch Freshness(age: snapshot.age()) {
        case .fresh, .recent: return .working
        case .stale: return .outdated
        case .abandoned: return .abandoned
        }
    }

    // MARK: Шапка

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Gauge for Claude Code")
                .font(.headline)
            Spacer(minLength: 8)
            badge
        }
    }

    private var badge: some View {
        Text(badgeText)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
            .lineLimit(1)
    }

    /// Несовпадение хеша поднимает метку независимо от свежести данных:
    /// подменённый экспортёр важнее того, насколько свеж снимок.
    private var badgeText: LocalizedStringKey {
        if integrity == .changed { return "Check needed" }
        switch state {
        case .needsWidget, .needsSetup: return "Setup needed"
        case .waiting: return "Waiting"
        case .working: return "Working"
        case .outdated, .abandoned: return "Check needed"
        }
    }

    private var badgeColor: Color {
        if integrity == .changed { return .yellow }
        switch state {
        case .working: return .green
        case .waiting: return .secondary
        case .needsWidget, .needsSetup, .outdated, .abandoned: return .yellow
        }
    }

    // MARK: Подменённый экспортёр

    /// Полоса, а не строка: этот случай нельзя пропустить ни при свёрнутых
    /// подробностях, ни боковым зрением.
    private var tamperBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("The exporter has been modified")
                    .font(.callout.weight(.semibold))
                Text("The file at ~/.claude/ccwidget-export.py is not the one this app installed. It runs on every status line redraw, so look at it before doing anything else, then reinstall a known copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reinstall the exporter") { runInstall() }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Полоски

    /// Те же подписи, тот же порядок, тот же расчёт уровня, что в виджете.
    private func rows(_ snapshot: Snapshot) -> some View {
        let entry = CCWidgetEntry(date: Date(), snapshot: snapshot, failure: nil, forecast: nil)
        return VStack(spacing: 8) {
            GaugeRow(caption: "5-hour used",
                     metric: entry.limitMetric(snapshot.limits.fiveHour),
                     dimmed: entry.isDimmed)
            GaugeRow(caption: "Week used",
                     metric: entry.limitMetric(snapshot.limits.sevenDay),
                     dimmed: entry.isDimmed)
            GaugeRow(caption: "Context used",
                     metric: entry.contextMetric,
                     dimmed: entry.isDimmed)
        }
    }

    /// Одна тихая строка вместо двух: когда сброс и насколько стар снимок.
    @ViewBuilder
    private func quietLine(_ snapshot: Snapshot) -> some View {
        let age = CCWidgetFormat.relativeAge(of: snapshot.capturedAt)
        Group {
            if let week = snapshot.limits.sevenDay {
                Text("Week resets \(CCWidgetFormat.resetMoment(week.resetsAt)) · updated \(age)")
            } else {
                Text("Updated \(age)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    // MARK: Когда данных нет

    /// Структура остаётся прежней: пустое окно с одной надписью выглядит
    /// сломанным, поэтому здесь объяснение и первичное действие.
    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .needsWidget:
                Text("Add the widget to your desktop first. Right-click the desktop, choose Edit Widgets, then come back.")
            case .needsSetup:
                Text("The status line is not pointing at this app yet, so nothing is being written.")
                Button("Set up…") { runInstall() }
            case .waiting:
                HStack(alignment: .top, spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Claude Code to send data. Send any message in the terminal.")
                }
            default:
                EmptyView()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Нижний ряд

    private var bottomRow: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showsDetails.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsDetails ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Details")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Remove…", role: .destructive) { showsRemoval = true }
                .controlSize(.small)
            Button("Refresh") { reload() }
                .controlSize(.small)
        }
        .font(.callout)
    }

    // MARK: Подробности

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Exporter", exporterDescription)
            detailRow("Watcher", watcherDescription)
            if let snapshot {
                detailRow("Snapshot", snapshotDescription(snapshot))
                detailRow("Claude Code", snapshot.claudeCodeVersion ?? "—")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Exchange directory")
                    .foregroundStyle(.secondary)
                Text(verbatim: SnapshotStore.default().containerURL.path(percentEncoded: false))
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !diagnostics.isEmpty {
                Divider()
                Label("\(diagnostics.count) field(s) dropped while parsing",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                ForEach(diagnostics, id: \.field) { issue in
                    Text(verbatim: issue.summary)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Reload widget") {
                WidgetCenter.shared.reloadAllTimelines()
            }
            .controlSize(.small)
            .padding(.top, 2)

            if let notice {
                Text(verbatim: notice)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(verbatim: value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var exporterDescription: String {
        switch integrity {
        case .matches: return String(localized: "matches the installed copy")
        case .changed: return String(localized: "modified since installation")
        case .unknown: return String(localized: "installed before checking existed")
        case .missing: return String(localized: "not installed")
        }
    }

    private var watcherDescription: String {
        guard watcher.isRunning else { return String(localized: "stopped") }
        guard let last = watcher.lastReload else {
            return String(localized: "running · no reloads yet")
        }
        let moment = last.formatted(date: .omitted, time: .shortened)
        return String(localized: "running · \(watcher.reloadCount) reloads · last \(moment)")
    }

    private func snapshotDescription(_ snapshot: Snapshot) -> String {
        let moment = snapshot.capturedAt.formatted(date: .omitted, time: .standard)
        guard let session = snapshot.sessionId else { return moment }
        return "\(moment) · \(session)"
    }

    // MARK: Действия

    private func reload() {
        snapshot = try? SnapshotStore.default().load()
        diagnostics = snapshot?.diagnostics ?? []
        integrity = installer.checkIntegrity()
    }

    private func runInstall() {
        do {
            let report = try installer.install()
            notice = report.backup.map {
                String(localized: "Settings backed up as \($0.lastPathComponent).")
            }
            reload()
        } catch {
            notice = error.localizedDescription
            showsDetails = true
        }
    }

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
            var parts = [String(localized: "Removed.")]
            if let backup = report.backup {
                parts.append(String(localized: "Settings backed up as \(backup.lastPathComponent)."))
            }
            notice = parts.joined(separator: " ")
            showsDetails = true
            reload()
        } catch {
            notice = error.localizedDescription
            showsDetails = true
        }
    }
}
