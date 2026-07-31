import SwiftUI
import WidgetKit

/// The app window.
///
/// Clicking the widget opens it, and macOS gives no way to refuse that, so
/// this window is seen by ordinary users rather than only by the developer.
/// Hence the state in plain language at the top, the same bars the widget
/// draws, and the diagnostics tucked under "Details".
///
/// The bars reuse `GaugeRow` from the extension unchanged: the window should
/// look like an enlarged widget, which is what makes the numbers matching
/// visible without reading anything.
struct StatusView: View {
    /// The state source comes from outside — section 5.2. There is not one
    /// "what if this is a screenshot" branch inside the type.
    @StateObject private var model: StatusModel
    @State private var showsDetails: Bool
    @State private var showsRemoval = false

    init(model: StatusModel = StatusModel(), expanded: Bool = false) {
        _model = StateObject(wrappedValue: model)
        _showsDetails = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.integrity == .changed {
                tamperBanner
            }

            if let snapshot = model.snapshot,
               state == .working || state == .outdated || state == .abandoned {
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
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .confirmationDialog("Remove ccwidget?", isPresented: $showsRemoval, titleVisibility: .visible) {
            Button("Remove, keep history", role: .destructive) { model.uninstall(removingHistory: false) }
            Button("Remove and delete history", role: .destructive) { model.uninstall(removingHistory: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.removalMessage)
        }
    }

    // MARK: State

    private enum WindowState {
        case needsWidget, needsSetup, waiting, working, outdated, abandoned
    }

    private var state: WindowState {
        if !model.containerExists { return .needsWidget }
        if !model.statusLineIsOurs { return .needsSetup }
        guard let snapshot = model.snapshot else { return .waiting }
        // `model.now` rather than the wall clock: the age has to advance on the
        // watcher's tick, so that going stale is something the window notices
        // rather than something the next redraw happens to reveal.
        switch Freshness(age: snapshot.age(at: model.now)) {
        case .fresh, .recent: return .working
        case .stale: return .outdated
        case .abandoned: return .abandoned
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Usage Widget for Claude Code")
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

    /// A hash mismatch raises the badge regardless of how fresh the data is:
    /// a tampered exporter outranks a stale snapshot.
    private var badgeText: LocalizedStringKey {
        if model.integrity == .changed { return "Check needed" }
        switch state {
        case .needsWidget, .needsSetup: return "Setup needed"
        case .waiting: return "Waiting"
        case .working: return "Working"
        case .outdated, .abandoned: return "Check needed"
        }
    }

    private var badgeColor: Color {
        if model.integrity == .changed { return .yellow }
        switch state {
        case .working: return .green
        case .waiting: return .secondary
        case .needsWidget, .needsSetup, .outdated, .abandoned: return .yellow
        }
    }

    // MARK: Tampered exporter

    /// A banner, not a line: this case must not be missable with Details
    /// collapsed or out of the corner of an eye.
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
                Button("Reinstall the exporter") { model.install() }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Bars

    /// The same captions, order and level calculation as the widget.
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

    /// One quiet line instead of two: when the reset happens and how old the
    /// snapshot is.
    @ViewBuilder
    private func quietLine(_ snapshot: Snapshot) -> some View {
        let age = CCWidgetFormat.relativeAge(of: snapshot.capturedAt, at: model.now)
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

    // MARK: When there is no data

    /// The structure stays the same: an empty window with a single line in it
    /// reads as broken, so this carries an explanation and a primary action.
    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch state {
            case .needsWidget:
                Text("Add the widget to your desktop first. Right-click the desktop, choose Edit Widgets, then come back.")
            case .needsSetup:
                Text("The status line is not pointing at this app yet, so nothing is being written.")
                Button("Set up…") { model.install() }
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

    // MARK: Bottom row

    private var bottomRow: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showsDetails.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsDetails ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        // The chevron carries no meaning a listener can use,
                        // and VoiceOver announced it: "Details, empty, button".
                        .accessibilityHidden(true)
                    Text("Details")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            // Whether the section is open is the whole point of the control,
            // and the chevron says it only to people who can see it. Folded
            // into the label rather than left as an accessibility value for
            // the same reason as the gauge rows: a value is announced before
            // the label, so a separate value would say "collapsed, Details".
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                Text("Details") + Text(verbatim: ", ")
                + Text(showsDetails ? "expanded" : "collapsed")
            )
            .accessibilityAction { withAnimation(.easeInOut(duration: 0.15)) { showsDetails.toggle() } }

            Spacer()

            Button("Remove…", role: .destructive) { showsRemoval = true }
                .controlSize(.small)
            Button("Refresh") { model.refresh() }
                .controlSize(.small)
        }
        .font(.callout)
    }

    // MARK: Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow("Exporter", exporterDescription)
            detailRow("Watcher", model.watcherSummary)
            if let snapshot = model.snapshot {
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

            if !model.diagnostics.isEmpty {
                Divider()
                Label("\(model.diagnostics.count) field(s) dropped while parsing",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                ForEach(model.diagnostics, id: \.field) { issue in
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

            if let notice = model.notice {
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
        // One item, not two. Left apart, VoiceOver read "Exporter" and
        // "matches the installed copy" as unrelated items, and the second
        // means nothing on its own.
        .accessibilityElement(children: .combine)
    }

    private var exporterDescription: String {
        switch model.integrity {
        case .matches: return String(localized: "matches the installed copy")
        case .changed: return String(localized: "modified since installation")
        case .unknown: return String(localized: "installed before checking existed")
        case .missing: return String(localized: "not installed")
        }
    }


    private func snapshotDescription(_ snapshot: Snapshot) -> String {
        let moment = snapshot.capturedAt.formatted(date: .omitted, time: .standard)
        guard let session = snapshot.sessionId else { return moment }
        return "\(moment) · \(session)"
    }




}
