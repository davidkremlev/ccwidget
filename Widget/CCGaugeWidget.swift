import SwiftUI
import WidgetKit

struct CCGaugeEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CCGaugeEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: MediumView(entry: entry)
        }
    }
}

struct CCGaugeWidget: Widget {
    let kind = "dev.illvminat.ccgauge.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CCGaugeProvider()) { entry in
            CCGaugeEntryView(entry: entry)
                .padding(14)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Gauge for Claude Code")
        .description("Subscription limits, context window and cost at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // Свои отступы вместо системных: раздел 9 фиксирует 14–16pt,
        // а стандартные поля виджета съедают их поверх наших.
        .contentMarginsDisabled()
    }
}

@main
struct CCGaugeWidgetBundle: WidgetBundle {
    var body: some Widget {
        CCGaugeWidget()
    }
}
