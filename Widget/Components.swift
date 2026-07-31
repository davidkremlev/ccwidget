import SwiftUI
import WidgetKit

/// One measured quantity, ready to draw. The bar always matches the number
/// beside it — otherwise the eye catches the discrepancy.
struct GaugeMetric {
    let fraction: Double
    let value: String
    let auxiliary: String?
    let level: Level

    /// For VoiceOver: the fraction, not a pre-formatted string. Otherwise
    /// the voice reads "38 %" as text, with no idea it is a percentage.
    var accessibilityValue: Text { Text(fraction, format: .percent) }
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
func gaugeAnnouncement(_ caption: LocalizedStringKey, _ metric: GaugeMetric?) -> Text {
    Text(caption) + Text(verbatim: ", ") + (metric?.accessibilityValue ?? Text("no data"))
}

extension CCWidgetEntry {
    var isDimmed: Bool { freshness?.isDimmed ?? false }
    var hidesNumbers: Bool { freshness?.hidesNumbers ?? false }

    /// All three rows show consumption — see section 8. The bar fills as
    /// usage grows, just like the context's, and matches the Usage panel
    /// without subtracting from a hundred.
    func limitMetric(_ window: LimitWindow?) -> GaugeMetric? {
        guard !hidesNumbers, let window else { return nil }
        return GaugeMetric(
            fraction: Double(window.usedPercentage) / 100,
            value: CCWidgetFormat.percent(window.usedPercentage),
            auxiliary: CCWidgetFormat.countdown(window.timeUntilReset(at: date)),
            level: window.level
        )
    }

    /// The context already showed how full it was — nothing to change.
    var contextMetric: GaugeMetric? {
        guard !hidesNumbers,
              let context = snapshot?.context,
              let used = context.usedPercentage,
              let level = context.level
        else { return nil }
        return GaugeMetric(
            fraction: Double(used) / 100,
            value: CCWidgetFormat.percent(used),
            auxiliary: context.totalInputTokens.map(CCWidgetFormat.tokens),
            level: level
        )
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
    let caption: LocalizedStringKey
    /// `nil` means no data: a dash instead of digits and an empty bar.
    let metric: GaugeMetric?
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            LevelGlyph(level: metric?.level, dimmed: dimmed)

            Text(caption)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Bar(fraction: metric?.fraction ?? 0, tint: tint)

            Text(verbatim: metric?.value ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .layoutPriority(2)

            if let auxiliary = metric?.auxiliary {
                Text(verbatim: auxiliary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement(caption, metric))
    }

    private var tint: Color { metricTint(metric, dimmed: dimmed) }
}

// MARK: - Detailed row (large size)

struct DetailGaugeRow: View {
    let caption: LocalizedStringKey
    let metric: GaugeMetric?
    let detail: String?
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                LevelGlyph(level: metric?.level, dimmed: dimmed)

                Text(caption)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(verbatim: metric?.value ?? "—")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .layoutPriority(2)
            }

            Bar(fraction: metric?.fraction ?? 0, tint: metricTint(metric, dimmed: dimmed), height: 8)

            if let detail {
                Text(verbatim: detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement(caption, metric))
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

func metricTint(_ metric: GaugeMetric?, dimmed: Bool) -> Color {
    guard let metric else { return .secondary }
    return dimmed ? .secondary : metric.level.color
}

/// The snapshot's age. Section 2.4: stale data must look stale, so past an
/// hour the age gets an explicit word in front of it.
struct AgeCaption: View {
    let entry: CCWidgetEntry

    var body: some View {
        if let captured = entry.snapshot?.capturedAt {
            let age = CCWidgetFormat.relativeAge(of: captured, at: entry.date)
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
