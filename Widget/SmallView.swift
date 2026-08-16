import SwiftUI
import WidgetKit

/// Section 9: the weekly limit and nothing else. At 158x158 exactly one
/// number is readable.
struct SmallView: View {
    let entry: CCWidgetEntry

    /// The drawn caption and the spoken one format the same reset moment, so
    /// they take it from the same place. Neither was doing so: both went to
    /// the process locale and the process time zone, which is right on a
    /// desktop and wrong everywhere a tile is rendered rather than lived in.
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    /// 34pt per section 9, but it scales with the system font size. A hard
    /// size switched Dynamic Type off entirely: the labels around it grew
    /// while the number did not, and the layout came apart.
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34

    private var window: LimitWindow? { entry.snapshot?.limits.sevenDay }
    private var reading: GaugeReading { entry.limitReading(window) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            Spacer(minLength: 0)

            if entry.snapshot == nil {
                MessageView.noData(compact: true)
                Spacer(minLength: 0)
            } else if entry.hidesNumbers {
                // Section 2.4: an invitation to launch Claude Code replaces
                // the digits.
                MessageView.abandoned(entry: entry, locale: locale, timeZone: timeZone, compact: true)
                Spacer(minLength: 0)
            } else if entry.snapshot?.limitsAvailability == .absentAfterReply {
                // This tile is the weekly window and nothing else, so an
                // account that is never sent one has nothing to show here. A
                // dash would read as "not yet".
                MessageView.noLimits(compact: true)
                Spacer(minLength: 0)
            } else {
                Text(verbatim: reading.metric?.value ?? "—")
                    .font(.system(size: valueSize, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(entry.isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                Bar(fraction: reading.metric?.fraction ?? 0, tint: metricTint(reading, dimmed: entry.isDimmed))

                caption
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gaugeAnnouncement("Week used", reading, detail: spokenCaption))
    }

    /// The same sentence the caption shows, as a string. Without it a listener
    /// got the percentage and nothing else, while the tile plainly says when
    /// the window resets — the one other fact it has room for.
    private var spokenCaption: String? {
        if entry.snapshot == nil { return String(localized: "no data") }
        if entry.hidesNumbers { return String(localized: "Launch Claude Code") }
        guard let window else { return String(localized: "waiting for limits") }
        // The one line this tile has for it: a window that has ended says so
        // instead of naming a reset that already happened.
        if window.hasClosed(at: entry.date) {
            return String(localized: "closed · \(CCWidgetFormat.resetMoment(window.resetsAt, locale: locale, timeZone: timeZone))")
        }
        return String(localized: "used · resets \(CCWidgetFormat.resetMoment(window.resetsAt, locale: locale, timeZone: timeZone))")
    }

    private var header: some View {
        HStack(spacing: 5) {
            LevelGlyph(level: reading.metric?.level, dimmed: entry.isDimmed, font: .caption)
            Text("Week used")
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// "used, resets Wed 3:00". The large number now grows towards the end
    /// of the week, and the caption has to read in the same direction.
    @ViewBuilder
    private var caption: some View {
        Group {
            if entry.snapshot == nil {
                Text("no data")
            } else if entry.hidesNumbers {
                Text("Launch Claude Code")
            } else if let window {
                Text("used · resets \(CCWidgetFormat.resetMoment(window.resetsAt, locale: locale, timeZone: timeZone))")
            } else {
                Text("waiting for limits")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        // Two lines, because one is an English-sized assumption. "used ·
        // resets Wed 3:00" is 22 characters; the same sentence is 30 in
        // Russian and 32 in German, and on a 158-point tile that is the
        // difference between a caption and an ellipsis. The space below the
        // bar was empty anyway.
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
