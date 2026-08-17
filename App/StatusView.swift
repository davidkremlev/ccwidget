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
    @ObservedObject private var model: StatusModel
    @State private var showsDetails: Bool
    @State private var showsRemoval = false

    /// The window formats the same two moments the tile does, so it takes them
    /// from the same two places. The process default is what it used to use,
    /// and on a desktop that is the same answer — until something renders this
    /// view somewhere else, which is exactly how the tile's version was found
    /// to be wrong.
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    init(model: StatusModel = StatusModel(), expanded: Bool = false) {
        _model = ObservedObject(wrappedValue: model)
        _showsDetails = State(initialValue: expanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if model.integrity.raisesBanner {
                tamperBanner
            }

            if let snapshot = model.snapshot, state.showsData {
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
        // Neither started nor stopped here any more. The app owns the
        // watcher's lifetime now, because a login item has to keep watching
        // with no window in sight — and a window that stopped it on the way out
        // would turn the background item into a process that does nothing.
        .onAppear { model.refresh() }
        .confirmationDialog("Remove ccwidget?", isPresented: $showsRemoval, titleVisibility: .visible) {
            Button("Remove, keep history", role: .destructive) { model.uninstall(removingHistory: false) }
            Button("Remove and delete history", role: .destructive) { model.uninstall(removingHistory: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.removalMessage)
        }
    }

    // MARK: State

    /// Lives in `WindowState` rather than here. `model.now` rather than the
    /// wall clock: the age has to advance on the watcher's tick, so that going
    /// stale is something the window notices rather than something the next
    /// redraw happens to reveal.
    private var state: WindowState {
        WindowState(containerExists: model.containerExists,
                    statusLineIsOurs: model.statusLineIsOurs,
                    snapshot: model.snapshot,
                    now: model.now)
    }

    // MARK: Header

    /// The name gives way, the badge does not.
    ///
    /// Both are text in an `HStack`, and with nothing said about priorities
    /// the layout decides which one gets less than it asked for. It decided on
    /// the title, and truncated it: "Usage Widget for Claude C…" beside the
    /// widest of the four badges, seen in the window at an hour's age.
    ///
    /// Which one should give way is not a layout question. The badge is the
    /// thing that changed and the thing to act on; the name of the application
    /// is something the reader already knows, being inside its window. So the
    /// badge keeps its size and the title is allowed to shrink — section 9's
    /// three tools, none of which this header used.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Usage Widget for Claude Code")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            badge
                .layoutPriority(1)
        }
    }

    private var badge: some View {
        Text(verbatim: badgeText)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
            .lineLimit(1)
            // No shrink allowance on purpose: the badge is what the header is
            // for. An earlier version gave it one, on the assumption that the
            // layout would take the deficit out of the badge — permission to
            // scale is not an instruction, and it took the deficit out of the
            // title instead. `layoutPriority` above is what actually decides
            // it; this stays at full size.
    }

    /// A hash mismatch raises the badge regardless of how fresh the data is:
    /// a tampered exporter outranks a stale snapshot.
    private var badgeText: String {
        if model.integrity.raisesBanner { return WindowState.outdated.badge() }
        return state.badge()
    }

    private var badgeColor: Color {
        if model.integrity.raisesBanner { return .yellow }
        switch state.tone {
        case .good: return .green
        case .quiet: return .secondary
        case .attention: return .yellow
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
                // Two states raise this banner and they are not the same
                // sentence. A modified file is something to look at before
                // touching anything; an old one is a button to press. The
                // second one had no words at all until 17 August, and no way
                // to reach this button either: installing a new app does not
                // rewrite the exporter, and once configured the app showed no
                // route back to setup.
                if model.integrity == .outdated {
                    Text("The exporter is from an older version")
                        .font(.callout.weight(.semibold))
                    Text("Installing a new version of this app does not rewrite ~/.claude/ccwidget-export.py — that happens at setup. Until you do, the exporter that runs on every redraw is the old one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("The exporter has been modified")
                        .font(.callout.weight(.semibold))
                    Text("The file at ~/.claude/ccwidget-export.py is not the one this app installed. It runs on every status line redraw, so look at it before doing anything else, then reinstall a known copy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// The same captions, order, level calculation **and countdown** as the
    /// widget — the rows are literally the same type, and the countdown is a
    /// dynamic date inside it.
    ///
    /// That last part replaced an agreement rather than implementing one. The
    /// two surfaces used to compute an age each and were held to printing the
    /// same characters by a check; now neither computes anything and both hand
    /// the same instant to the system. Agreement by construction beats
    /// agreement by assertion — see section 2.4.
    private func rows(_ snapshot: Snapshot) -> some View {
        let entry = CCWidgetEntry(date: Date(), snapshot: snapshot, failure: nil, forecast: nil)
        return VStack(spacing: 8) {
            GaugeRow(caption: "5-hour used",
                     reading: entry.limitReading(snapshot.limits.fiveHour),
                     dimmed: entry.isDimmed,
                     detail: entry.limitDetail(snapshot.limits.fiveHour),
                     moment: entry.date)
            GaugeRow(caption: "Week used",
                     reading: entry.limitReading(snapshot.limits.sevenDay),
                     dimmed: entry.isDimmed,
                     detail: entry.limitDetail(snapshot.limits.sevenDay),
                     moment: entry.date)
            GaugeRow(caption: "Context used",
                     reading: entry.contextReading,
                     dimmed: entry.isDimmed)
        }
    }

    /// One quiet line instead of two: when the reset happens and when the
    /// snapshot was taken.
    ///
    /// A capture moment rather than an age, for the reason in section 2.4: an
    /// age is true only at the instant it is computed, and this window
    /// recomputes on a timer while the widget beside it does not.
    @ViewBuilder
    private func quietLine(_ snapshot: Snapshot) -> some View {
        let captured = CCWidgetFormat.capturedMoment(snapshot.capturedAt,
                                                     locale: locale,
                                                     timeZone: timeZone)
        Group {
            if let week = snapshot.limits.sevenDay {
                let resets = CCWidgetFormat.resetMoment(week.resetsAt,
                                                        locale: locale,
                                                        timeZone: timeZone)
                Text("Week resets \(resets) · updated at \(captured)")
            } else {
                Text("Updated at \(captured)")
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
            if let explanation = state.explanation() {
                // The words come from `WindowState`; what stays here is the
                // furniture around them, which differs by case and carries no
                // meaning of its own.
                if state == .waiting {
                    HStack(alignment: .top, spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(verbatim: explanation)
                    }
                } else {
                    Text(verbatim: explanation)
                }
                if state == .needsSetup {
                    Button("Set up…") { model.install() }
                }
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

    /// The switch that decides whether the tile is a minute behind or half an
    /// hour behind.
    ///
    /// A line in Details rather than anything louder, deliberately: it is off
    /// until somebody turns it on, and a widget nagging for permission to launch
    /// itself at every login is the behaviour this project would complain about
    /// in somebody else's app.
    @ViewBuilder
    private var backgroundUpdates: some View {
        let state = model.loginItem.state
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Background updates")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { state.isOn },
                    set: { model.setBackgroundUpdates($0) }
                ))
                .labelsHidden()
                .controlSize(.mini)
            }
            Text(verbatim: state.detail(locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if state.needsSettings {
                Button("Open Login Items in System Settings") {
                    model.loginItem.openSettings()
                }
                .controlSize(.small)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First, because every other row is about something this app is
            // looking at and this one is about the app doing the looking. A
            // report that starts "the exporter says" is worth less than one
            // that starts by naming which build made it.
            detailRow("This app", AppBuild.current.text())
            detailRow("Exporter", exporterDescription)
            detailRow("Watcher", model.watcherSummary)
            backgroundUpdates
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

    private var exporterDescription: String { model.integrity.detail() }


    private func snapshotDescription(_ snapshot: Snapshot) -> String {
        let moment = snapshot.capturedAt.formatted(date: .omitted, time: .standard)
        guard let session = snapshot.sessionId else { return moment }
        return "\(moment) · \(session)"
    }




}
