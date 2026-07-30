import SwiftUI
import WidgetKit

/// Раздел 9: только недельный лимит. На 158×158 читается ровно одно число.
struct SmallView: View {
    let entry: CCWidgetEntry

    /// 34pt по разделу 9, но масштабируется вместе с системным шрифтом.
    /// Жёсткий размер выключал Dynamic Type совсем: подписи вокруг росли,
    /// а цифра нет, и макет разъезжался.
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
                // Раздел 2.4: вместо цифр приглашение запустить Claude Code.
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

    /// «израсходовано, сброс ср 3:00» — крупная цифра теперь растёт
    /// к концу недели, и подпись обязана читаться в ту же сторону.
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
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
