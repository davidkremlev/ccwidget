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

extension CCWidgetEntry {
    var isDimmed: Bool { freshness?.isDimmed ?? false }
    var hidesNumbers: Bool { freshness?.hidesNumbers ?? false }

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
            auxiliary: CCWidgetFormat.countdown(window.timeUntilReset(at: date)),
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

// MARK: - Bar

struct Bar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
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

    var body: some View {
        HStack(spacing: 6) {
            LevelGlyph(level: reading.metric?.level, dimmed: dimmed)

            Text(caption)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Bar(fraction: reading.metric?.fraction ?? 0, tint: tint)

            Text(verbatim: reading.metric?.value ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .layoutPriority(2)

            if let auxiliary = reading.auxiliary() {
                Text(verbatim: auxiliary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement(caption, reading, detail: reading.auxiliary()))
    }

    private var tint: Color { metricTint(reading, dimmed: dimmed) }
}

// MARK: - Detailed row (large size)

struct DetailGaugeRow: View {
    let caption: LocalizedStringResource
    let reading: GaugeReading
    let detail: String?
    let dimmed: Bool

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

            if let detail {
                Text(verbatim: detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement(caption, reading, detail: detail))
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

/// The snapshot's age. Section 2.4: stale data must look stale, so past an
/// hour the age gets an explicit word in front of it.
struct AgeCaption: View {
    let entry: CCWidgetEntry
    @Environment(\.locale) private var locale

    var body: some View {
        if let captured = entry.snapshot?.capturedAt {
            let age = CCWidgetFormat.relativeAge(of: captured, at: entry.date, locale: locale)
            Group {
                if entry.freshness?.isDimmed == true {
                    Text("outdated · \(age)")
                } else {
                    Text(verbatim: age)
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

    /// The snapshot is over a day old. Section 2.4: an invitation replaces
    /// the digits.
    static func abandoned(entry: CCWidgetEntry, compact: Bool = false) -> MessageView {
        MessageView(
            title: "Data is stale",
            message: "Launch Claude Code in the terminal to refresh.",
            age: entry.snapshot.map { CCWidgetFormat.relativeAge(of: $0.capturedAt, at: entry.date) },
            compact: compact
        )
    }
}
