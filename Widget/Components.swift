import SwiftUI
import WidgetKit

/// One measured quantity, ready to draw. The bar always matches the number
/// beside it — otherwise the eye catches the discrepancy.
struct GaugeMetric: Equatable {
    let fraction: Double
    let value: String
    let auxiliary: String?
    let level: Level

    /// For VoiceOver: the fraction put through a percentage format, not the
    /// already-formatted `value`. Otherwise the voice reads "38 %" as text,
    /// with no idea it is a percentage.
    /// The locale is a parameter because a baseline has to be reproducible:
    /// the same run on a Russian machine and an American one must produce the
    /// same file, or the check fails for the wrong reason. Production takes
    /// the default, which is the reader's own locale.
    func spokenValue(locale: Locale = .autoupdatingCurrent) -> String {
        fraction.formatted(.percent.locale(locale))
    }
}

/// What one gauge row has to show.
///
/// Three states, because there are three different things to say and two of
/// them used to be one. A row with no metric meant "nothing arrived"; a row
/// whose window had ended was given the same nothing, plus a countdown floored
/// at zero that read as "resets any moment now". The reset was in the past.
///
/// `closed` is not a degree of staleness. The rows age at different rates: a
/// weekly percentage twelve hours old is roughly right, a five-hour one
/// describes a window that has closed twice over, and dimming the whole
/// snapshot cannot tell those apart. Section 8.
enum GaugeReading: Equatable {
    case measured(GaugeMetric)
    /// Nothing arrived for this row, or the snapshot is old enough that no
    /// digits are shown at all.
    case missing
    /// The window this row describes has ended. Something did arrive; it is
    /// simply about a period that is over, and what the current one holds is
    /// unknown.
    case closed

    var metric: GaugeMetric? {
        if case .measured(let metric) = self { return metric }
        return nil
    }

    /// The same reading with something else beside the number. Only a
    /// measured row has anything to put there — a closed one already uses that
    /// place to say so.
    func withAuxiliary(_ auxiliary: String?) -> GaugeReading {
        guard case .measured(let metric) = self else { return self }
        return .measured(GaugeMetric(fraction: metric.fraction, value: metric.value,
                                     auxiliary: auxiliary ?? metric.auxiliary,
                                     level: metric.level))
    }

    /// What sits to the right of the number. For a closed window this is the
    /// only place that says so, which is why the word is short enough for the
    /// medium tile's slot in every language — measured, see `TextMetricsTests`.
    func auxiliary(locale: Locale = .autoupdatingCurrent) -> String? {
        switch self {
        case .measured(let metric): return metric.auxiliary
        case .missing: return nil
        case .closed:
            var resource = LocalizedStringResource("closed")
            resource.locale = locale
            return String(localized: resource)
        }
    }
}

/// What VoiceOver should say for one gauge row, in one piece.
///
/// A row used to carry its caption as the accessibility label and its
/// percentage as the accessibility value. Heard, that came out backwards —
/// "30 %, five-hour used" — because VoiceOver reads a static element's value
/// before its label. Three rows in a row meant three bare numbers arriving
/// before the things they measured, which is exactly the wrong order for
/// someone who cannot glance back at the previous line.
///
/// Composing a single label is the only way to fix the order rather than hope
/// for it. Verified by listening, not by reading the modifier list.
///
/// A `String` rather than a `Text` so that the spoken form is a value the code
/// can look at. A `Text` cannot be read back — which is why the order was
/// wrong for as long as it was, and why the check that now holds it is a text
/// baseline rather than a rendering.
/// `detail` is whatever sits beside the number on screen — the countdown to
/// the reset, the project name, the line under the bar. Dropping it was a
/// regression introduced by the fix above and found by the next VoiceOver
/// pass: the order came right and the content went missing, so a listener
/// heard "five-hour used, 49 %" where a reader saw "49 % · 3 hr 59 min".
/// Whatever is on the tile is said.
/// A closed window is announced as closed rather than as "no data": something
/// did arrive for that row, and a listener told "no data" would go looking for
/// a fault that is not there.
func gaugeAnnouncement(_ caption: LocalizedStringResource,
                       _ reading: GaugeReading,
                       detail: String? = nil,
                       locale: Locale = .autoupdatingCurrent) -> String {
    func localized(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = locale
        return String(localized: copy)
    }

    let name = localized(caption)
    let value: String
    switch reading {
    case .measured(let metric): value = metric.spokenValue(locale: locale)
    case .missing: value = localized(LocalizedStringResource("no data"))
    case .closed: value = localized(LocalizedStringResource("closed"))
    }
    // A closed row carries no countdown to append, so the detail it would have
    // shown is the word itself and is already the value.
    let extra = reading == .closed ? nil : detail
    return [name, value, extra].compactMap { $0 }.joined(separator: ", ")
}

/// What goes under a row's bar.
///
/// Two kinds, and they are not interchangeable. A context row's line is a
/// string the code computed — a token count, a project name — and it stays
/// whatever it was when the entry was built. A limit row's line contains a
/// countdown, and a countdown built as a string is wrong the moment after it
/// is built: the widget is redrawn on thresholds now, not every minute, so a
/// computed "3 hr 38 min" would sit on screen for hours saying the same thing.
///
/// So the countdown is not computed at all. `.reset` carries the moment, and
/// the view hands it to SwiftUI's dynamic date, which keeps counting while the
/// extension is not running. Section 2.3.
///
/// An enum rather than an optional string because the difference has to be
/// askable: a check can hold that a limit row produces `.reset` and never a
/// frozen `.text`, and that a closed window produces `.closed` rather than a
/// countdown flooring at zero.
enum RowDetail: Equatable {
    case none
    /// A line computed once: tokens, a project name.
    case text(String)
    /// "resets Fri 11:50 · <counting down>" — the moment plus a live interval.
    case reset(moment: String, at: Date)
    /// The window ended. Naming when it ended still helps; counting to it does
    /// not, because the count floors at zero and reads as a reset about to
    /// happen.
    case closed(moment: String)

    var isEmpty: Bool { self == .none }
}

extension CCWidgetEntry {
    var isDimmed: Bool { freshness?.isDimmed ?? false }
    var hidesNumbers: Bool { freshness?.hidesNumbers ?? false }

    /// The line under a limit row, as data rather than as a view.
    func limitDetail(_ window: LimitWindow?, locale: Locale = .autoupdatingCurrent) -> RowDetail {
        guard !hidesNumbers, let window else { return .none }
        let moment = CCWidgetFormat.resetMoment(window.resetsAt, locale: locale)
        return window.hasClosed(at: date)
            ? .closed(moment: moment)
            : .reset(moment: moment, at: window.resetsAt)
    }

    /// All three rows show consumption — see section 8. The bar fills as
    /// usage grows, just like the context's, and matches the Usage panel
    /// without subtracting from a hundred.
    func limitReading(_ window: LimitWindow?) -> GaugeReading {
        guard !hidesNumbers, let window else { return .missing }
        // Asked before the number is built, not after: once the window has
        // ended its percentage describes a period that is over, and the
        // current one is unknown.
        guard !window.hasClosed(at: date) else { return .closed }
        return .measured(GaugeMetric(
            fraction: Double(window.usedPercentage) / 100,
            value: CCWidgetFormat.percent(window.usedPercentage),
            // No countdown in here any more: it lives in `RowDetail.reset`
            // and is drawn by SwiftUI's dynamic date, not computed.
            auxiliary: nil,
            level: window.level
        ))
    }

    /// The context has no window of its own to close — it belongs to the
    /// session, not to a period the account resets.
    var contextReading: GaugeReading {
        guard !hidesNumbers,
              let context = snapshot?.context,
              let used = context.usedPercentage,
              let level = context.level
        else { return .missing }
        return .measured(GaugeMetric(
            fraction: Double(used) / 100,
            value: CCWidgetFormat.percent(used),
            auxiliary: context.totalInputTokens.map(CCWidgetFormat.tokens),
            level: level
        ))
    }
}

/// The line under a bar. The one place a dynamic date enters the widget.
///
/// `Text("… \(date, style: .relative)")` keeps counting while the extension is
/// asleep, which is what lets the timeline hold entries at thresholds instead
/// of one a minute. What it costs: the string is built by the system and the
/// code never sees it, so its width cannot be measured in the fast tier — that
/// check moved to the render tier, see `Docs/rendering-checks.md`.
struct DetailLine: View {
    let detail: RowDetail
    /// Whether there is room for the reset moment as well as the countdown.
    ///
    /// There is not, on a medium tile. The line sits in the row's `HStack`
    /// beside the bar there, and the bar is the only flexible thing in it — so
    /// a line carrying both "сброс Чт 07:00" and "· 5 дн 20 ч" takes the bar's
    /// width, all of it. That is exactly what shipped: 215 checks green and no
    /// bar on the tile. On the large tile the line has a row of its own under
    /// the bar and can say everything.
    var compact = false

    var body: some View {
        switch detail {
        case .none:
            EmptyView()
        case .text(let value):
            line { Text(verbatim: value) }
        case .reset(let moment, let at):
            if compact {
                line { Text(at, style: .relative) }
            } else {
                line { Text("resets \(moment) · \(at, style: .relative)") }
            }
        case .closed(let moment):
            if compact {
                line { Text("closed") }
            } else {
                line { Text("resets \(moment) · \(String(localized: "closed"))") }
            }
        }
    }

    private func line(@ViewBuilder _ content: () -> Text) -> some View {
        content()
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// What the row says out loud where the dynamic date is drawn.
///
/// VoiceOver cannot be handed a `Text`, so the countdown is computed here for
/// the moment the entry was built — and drifts from the drawn one as the entry
/// ages. Accepted deliberately: a listener hearing "3 hr 38 min" when the tile
/// reads "3 hr 12 min" is told the truth about a different minute, whereas a
/// listener told nothing at all learns nothing. Section 2.4.
func spokenDetail(_ detail: RowDetail, at moment: Date,
                  compact: Bool = false,
                  locale: Locale = .autoupdatingCurrent) -> String? {
    func localized(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = locale
        return String(localized: copy)
    }
    switch detail {
    case .none: return nil
    case .text(let value): return value
    case .closed(let when):
        // A compact row draws only the word; what is spoken follows what is
        // drawn, or the listener and the reader are told different things.
        return compact
            ? localized(LocalizedStringResource("closed"))
            : localized(LocalizedStringResource("resets \(when) · \(localized(LocalizedStringResource("closed")))"))
    case .reset(let when, let at):
        let left = CCWidgetFormat.countdown(at.timeIntervalSince(moment))
        return compact
            ? left
            : localized(LocalizedStringResource("resets \(when) · \(left)"))
    }
}

// MARK: - Bar

struct Bar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    /// The fraction, clamped, and never anything but a number.
    ///
    /// `scaleEffect` traps on a non-finite scale exactly as `frame(width:)`
    /// traps on a non-finite width, so the guard outlived the geometry it was
    /// written for. A percentage arriving as NaN would take the extension down
    /// on every render, and the extension going down is invisible from the
    /// desktop — the system keeps showing the last frame that worked.
    private var fill: CGFloat {
        min(max(fraction.isFinite ? fraction : 0, 0), 1)
    }

    /// **No `GeometryReader` here, and that is the whole point.**
    ///
    /// The extension crashed on every render for five hours on 7 August 2026 —
    /// `assertionFailure` inside `LayoutSubview.place`, called from
    /// `GeometryReaderLayout.placeSubviews`. A reader reports whatever the
    /// layout proposes, and WidgetKit archives a widget's states with proposals
    /// no screenshot tool makes: eighty-one renders through `ImageRenderer`,
    /// every view and every state, came back clean while the tile crashed each
    /// time. Clamping the width the reader returned did not help; removing the
    /// reader did.
    ///
    /// A scaled capsule needs no geometry: the fill is laid out at full width
    /// and squeezed from the leading edge. `RowCompositionTests` fails if a
    /// reader comes back, and `Scripts/check-widget-health.sh` is what would
    /// notice if something else of the same kind arrives.
    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: height)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(tint)
                    .scaleEffect(x: fill, y: 1, anchor: .leading)
            }
    }
}

// MARK: - Header

/// The header carries the model and nothing else.
///
/// The project name was deliberately moved out. The exporter is global, every
/// session writes into the same snapshot, and the project belongs to whichever
/// session redrew last — not to the widget as a whole. In the header it read
/// as "this widget is about project X", which is false. It now sits next to
/// the context row, which is what it actually describes (section 13, option A).
struct WidgetHeader: View {
    let entry: CCWidgetEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: entry.snapshot?.model.map(Self.caption)
                ?? String(localized: "Usage Widget for Claude Code"))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
        }
    }

    static func caption(_ model: ModelInfo) -> String {
        [model.displayName, model.effort].compactMap { $0 }.joined(separator: " · ")
    }
}

extension CCWidgetEntry {
    /// The project name of whichever session redrew last.
    var projectName: String? { snapshot?.project?.name }
}

// MARK: - Compact row (medium size)

struct GaugeRow: View {
    let caption: LocalizedStringResource
    /// Anything but `.measured` draws a dash and an empty bar; what stands to
    /// the right of it is what tells the two apart.
    let reading: GaugeReading
    let dimmed: Bool
    /// The line beside the number. `.none` keeps the old behaviour — whatever
    /// the reading itself carries.
    var detail: RowDetail = .none
    /// The moment the entry was stamped with. Only the spoken form needs it:
    /// the drawn countdown asks the system clock, the announcement cannot.
    var moment: Date = Date()

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 6) {
            LevelGlyph(level: reading.metric?.level, dimmed: dimmed)

            Text(caption)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            // The floor `TextMetricsTests` has always assumed when working out
            // what is left for the caption — now stated to the layout instead
            // of hoped for. Below forty points a bar is a decoration beside a
            // number; the caption, unlike the bar, can shrink and still be
            // read.
            Bar(fraction: reading.metric?.fraction ?? 0, tint: tint)
                .frame(minWidth: 40)

            Text(verbatim: reading.metric?.value ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .layoutPriority(2)

            if case .none = detail {
                if let auxiliary = reading.auxiliary() {
                    Text(verbatim: auxiliary)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(2)
                }
            } else {
                // No layoutPriority here, deliberately. Giving the line
                // priority is what squeezed the bar to nothing; the bar is the
                // one element in this row that cannot be replaced by reading
                // the number beside it.
                DetailLine(detail: detail, compact: true)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement(
            caption, reading,
            detail: spokenDetail(detail, at: moment, compact: true, locale: locale)
                ?? reading.auxiliary(locale: locale),
            locale: locale))
    }

    private var tint: Color { metricTint(reading, dimmed: dimmed) }
}

// MARK: - Detailed row (large size)

struct DetailGaugeRow: View {
    let caption: LocalizedStringResource
    let reading: GaugeReading
    let detail: RowDetail
    let dimmed: Bool
    /// See `GaugeRow.moment`.
    var moment: Date = Date()

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                LevelGlyph(level: reading.metric?.level, dimmed: dimmed)

                Text(caption)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(verbatim: reading.metric?.value ?? "—")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .layoutPriority(2)
            }

            Bar(fraction: reading.metric?.fraction ?? 0,
                tint: metricTint(reading, dimmed: dimmed), height: 8)

            DetailLine(detail: detail)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement(
            caption, reading,
            detail: spokenDetail(detail, at: moment, locale: locale),
            locale: locale))
    }
}

// MARK: - Small pieces

/// Colour is not the only carrier of meaning: the glyph's shape changes with
/// the level.
struct LevelGlyph: View {
    let level: Level?
    let dimmed: Bool
    var font: Font = .caption2

    var body: some View {
        Image(systemName: level?.symbolName ?? "minus.circle")
            .font(font)
            .foregroundStyle(dimmed || level == nil ? Color.secondary : level!.color)
            .layoutPriority(1)
    }
}

func metricTint(_ reading: GaugeReading, dimmed: Bool) -> Color {
    guard let metric = reading.metric else { return .secondary }
    return dimmed ? .secondary : metric.level.color
}

/// When the snapshot was taken. Section 2.4.
///
/// This printed a ticking age until the batch that moved countdowns onto
/// dynamic dates. Two reasons it does not any more, and the second is the one
/// that matters. The widget is now redrawn on thresholds rather than every
/// minute, so a computed age would be stale between redraws — but more than
/// that, an age is only ever true at the instant it is computed, while a
/// capture moment is true whenever it is read. How old it is still shows: the
/// tile dims past an hour and drops its figures past a day.
struct CaptureCaption: View {
    let entry: CCWidgetEntry
    @Environment(\.locale) private var locale

    var body: some View {
        if let captured = entry.snapshot?.capturedAt {
            let moment = CCWidgetFormat.capturedMoment(captured, locale: locale)
            Group {
                if entry.freshness?.isDimmed == true {
                    Text("outdated · updated at \(moment)")
                } else {
                    Text("updated at \(moment)")
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

/// One panel for every case where digits must not be shown.
struct MessageView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// The snapshot's age, when there is one. In the abandoned state it is
    /// the only honest number left on the widget.
    var age: String?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if !compact {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let age {
                Text(age)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MessageView {
    /// No snapshot at all — the exporter has never run.
    static func noData(compact: Bool = false) -> MessageView {
        MessageView(
            title: "No data yet",
            message: "Launch Claude Code in the terminal and send a message.",
            compact: compact
        )
    }

    /// The subscription windows have not arrived, and a reply already has.
    ///
    /// **States the observation and the rule; does not draw the conclusion.**
    /// The likely reason is a plan that is not sent them, and that is a
    /// statement about the reader's own subscription made from an indirect
    /// signal — the context figures being filled in. If a Pro subscriber is
    /// missing their windows for some other reason, a confident sentence about
    /// their plan is simply false, and told to the person best placed to know
    /// it is false. So the panel says what did not arrive and what the rule is,
    /// and the reader, who knows which plan they are on, draws the rest.
    ///
    /// Not the same panel as `noData`, and the difference is the reason it
    /// exists: `noData` asks the person to do something, and here there may be
    /// nothing they can do. What is on the tile is still worth reading — the
    /// context and the cost come from the same snapshot and are unaffected.
    static func noLimits(compact: Bool = false) -> MessageView {
        MessageView(
            title: "Limits have not arrived",
            message: "Claude Code sends them to Pro and Max accounts, after the first reply.",
            compact: compact
        )
    }

    /// The snapshot is over a day old. Section 2.4: an invitation replaces
    /// the digits.
    static func abandoned(entry: CCWidgetEntry, compact: Bool = false) -> MessageView {
        MessageView(
            title: "Data is stale",
            message: "Launch Claude Code in the terminal to refresh.",
            age: entry.snapshot.map {
                String(localized: "updated at \(CCWidgetFormat.capturedMoment($0.capturedAt))")
            },
            compact: compact
        )
    }
}
