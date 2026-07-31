import SwiftUI
import WidgetKit

/// Section 9: the weekly limit and nothing else. At 158x158 exactly one
/// number is readable.
struct SmallView: View {
    let entry: CCWidgetEntry

    /// 34pt per section 9, but it scales with the system font size. A hard
    /// size switched Dynamic Type off entirely: the labels around it grew
    /// while the number did not, and the layout came apart.
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34

    private var window: LimitWindow? { entry.snapshot?.limits.sevenDay }
    private var metric: GaugeMetric? { entry.limitMetric(window) }

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
                MessageView.abandoned(entry: entry, compact: true)
                Spacer(minLength: 0)
            } else {
                Text(verbatim: metric?.value ?? "—")
                    .font(.system(size: valueSize, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(entry.isDimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                Bar(fraction: metric?.fraction ?? 0, tint: metricTint(metric, dimmed: entry.isDimmed))

                caption
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Week used")
        .accessibilityValue(metric?.accessibilityValue ?? Text("no data"))
    }

    private var header: some View {
        HStack(spacing: 5) {
            LevelGlyph(level: metric?.level, dimmed: entry.isDimmed, font: .caption)
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
                Text("used · resets \(CCWidgetFormat.resetMoment(window.resetsAt))")
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
