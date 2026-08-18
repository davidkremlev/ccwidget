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
            badge

            if model.integrity.raisesBanner {
                tamperBanner
            }

            if let snapshot = model.snapshot, state.showsData {
                rows(snapshot)
                quietLine(snapshot)
            } else {
                emptyState
            }

            if showsDetails {
                Divider()
                details
            }
        }
        .padding(20)
        .frame(width: 460)
        // Neither started nor stopped here any more. The app owns the
        // watcher's lifetime now, because a login item has to keep watching
        // with no window in sight — and a window that stopped it on the way out
        // would turn the background item into a process that does nothing.
        .onAppear { model.refresh() }
        .toolbar { toolbar }
        .confirmationDialog("Remove ccwidget?", isPresented: $showsRemoval, titleVisibility: .visible) {
            Button("Remove, keep history", role: .destructive) { model.uninstall(removingHistory: false) }
            Button("Remove and delete history", role: .destructive) { model.uninstall(removingHistory: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.removalMessage)
        }
    }

    // MARK: Toolbar

    /// The window's actions live in its toolbar, not in a row of buttons at the
    /// foot of the content.
    ///
    /// This is where the platform puts them, and on macOS 26 it is also where
    /// the platform draws them in Liquid Glass without being asked: the title
    /// bar and its items take the material on their own when the app is built
    /// with the macOS 26 SDK — `apple/liquid-glass-adopting.md`, "Leverage
    /// system frameworks to adopt Liquid Glass automatically". On macOS 14 and
    /// 15 the same toolbar draws in the style of the system it runs on. Nothing
    /// here is gated on a version, and nothing here should be: the whole point
    /// is that the system decides what a toolbar looks like.
    ///
    /// Two groups rather than one, and the destructive action alone in the
    /// second: the adoption guide asks for items to be grouped by what they
    /// affect, and on macOS 26 a group shares one glass background, so the
    /// grouping is visible rather than notional. `Remove…` uninstalls the
    /// product; it does not belong under the same pane of glass as "look
    /// again" and "tell me more".
    ///
    /// Icons, with a label on every one: also from the guide — "Provide an
    /// accessibility label for every icon". The label is what VoiceOver reads,
    /// what the toolbar's overflow menu shows, and what the tooltip says, so
    /// each action carries one string for all three. The actions themselves
    /// are `StatusAction`, a list a check can read; this builder only places
    /// them.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $showsDetails.animation(.easeInOut(duration: 0.15))) {
                StatusAction.details.label
            }
            .toggleStyle(.button)
            .help(StatusAction.details.title)
            // The two buttons beside it take their accessibility description
            // from their label; the toggle does not. Measured on 26.6.2 through
            // System Events: `Обновить`, `Удалить…`, and for this one
            // "кнопка переключения" — a toggle button with no name. Said
            // explicitly, then.
            .accessibilityLabel(StatusAction.details.title)
            Button { model.refresh() } label: { StatusAction.refresh.label }
                .help(StatusAction.refresh.title)
        }
        if #available(macOS 26, *) {
            // The gap that makes two groups two panes of glass rather than one.
            // Without it the system merges adjacent groups of the same
            // placement into a single background — measured on 26.6.2, all
            // three icons under one capsule — and the grouping this comment's
            // neighbour describes existed only in the source.
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(role: .destructive) { showsRemoval = true } label: { StatusAction.remove.label }
                .help(StatusAction.remove.title)
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

    // MARK: Badge

    /// The state, in one word, at the top of the window.
    ///
    /// It used to share a line with the application's name, and the two of
    /// them fought over the width until `layoutPriority` settled it. The name
    /// is gone from the content now: the window's title bar says it, and a
    /// window that says its own name twice was exactly what the repeated-band
    /// check exists to catch — it did not, because the title bar is not part
    /// of what `ImageRenderer` draws, which is a reason to remove the
    /// duplicate rather than a reason to keep it.
    ///
    /// On macOS 26 the capsule is Liquid Glass, tinted with the tone. This is
    /// the one custom use of the material in the window, kept deliberately
    /// small: the adoption guide says to apply it to custom elements
    /// "sparingly", and the toolbar above already carries the material where
    /// the platform wants it. Earlier systems draw the flat tinted capsule
    /// they always drew — the modifier does not exist there, and this is what
    /// the `#available` is for.
    private var badge: some View {
        Text(verbatim: badgeText)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(badgeColor)
            .lineLimit(1)
            .fixedSize()
            .modifier(BadgeSurface(tone: badgeColor))
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

// MARK: - The toolbar's actions

/// What the toolbar offers, as a list rather than as three buttons written
/// out in a builder.
///
/// A toolbar is the one part of this window that `ImageRenderer` cannot draw,
/// so the composition checks that hold the rest of the window to account see
/// nothing of it. What they can hold to account is this: that every action has
/// a symbol the system actually ships and a title for the label, the tooltip
/// and the overflow menu — the three places an icon-only item needs words.
/// `CaseIterable`, so that a check walks all of them and a fourth action
/// cannot be added without being walked.
enum StatusAction: CaseIterable {
    case details, refresh, remove

    /// The strings are the ones the buttons at the foot of the window used, so
    /// the catalogue already carries them in every language.
    var title: LocalizedStringKey {
        switch self {
        case .details: "Details"
        case .refresh: "Refresh"
        case .remove: "Remove…"
        }
    }

    var symbol: String {
        switch self {
        case .details: "info.circle"
        case .refresh: "arrow.clockwise"
        case .remove: "trash"
        }
    }

    var label: some View { Label(title, systemImage: symbol) }
}

// MARK: - The badge's surface

/// Liquid Glass where there is Liquid Glass, the flat capsule everywhere else.
///
/// A modifier rather than an `if` inside the badge so that the two branches
/// cannot drift apart in padding or shape: both receive the same view and
/// differ only in what is behind it. `glassEffect(_:in:)` —
/// `apple/swiftui-glasseffect.md` — is macOS 26 and later; the tint is the
/// tone at the strength the flat capsule used, so the two look like the same
/// badge in two materials rather than two badges.
private struct BadgeSurface: ViewModifier {
    let tone: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tone.opacity(0.18)), in: .capsule)
        } else {
            content.background(tone.opacity(0.18), in: Capsule())
        }
    }
}
