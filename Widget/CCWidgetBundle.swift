import SwiftUI
import WidgetKit

struct CCWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CCWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: MediumView(entry: entry)
        }
    }
}

struct CCWidgetExtension: Widget {
    let kind = "dev.illvminat.ccwidget.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CCWidgetProvider()) { entry in
            CCWidgetEntryView(entry: entry)
                .padding(14)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "Usage Widget for Claude Code"))
        // Begins with a verb: Apple's widget guidance asks descriptions to start
        // with an action word and to leave out phrases about the widget itself.
        .description(String(localized: "Track how much of your Claude subscription you have used, with the context window and cost."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // Our own insets instead of the system's: section 9 fixes them at
        // 14-16pt, and the default widget margins would stack on top.
        .contentMarginsDisabled()
    }
}

@main
struct CCWidgetBundle: WidgetBundle {
    var body: some Widget {
        CCWidgetExtension()
    }
}
