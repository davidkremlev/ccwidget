import Foundation

/// Localized formatting. No hand-assembled strings — see section 10.
public enum CCWidgetFormat {
    /// "2 minutes ago". Localized out of the box.
    public static func relativeAge(of date: Date, at now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Countdown to the window reset. Two largest units, abbreviated.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days, .hours, .minutes],
            width: .abbreviated,
            maximumUnitCount: 2
        )
        return Duration.seconds(max(0, seconds)).formatted(style)
    }

    /// Reset moment: "Wed 3:00". Weekday without a date — a reset is never
    /// far away.
    public static func resetMoment(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    public static func percent(_ value: Int) -> String {
        value.formatted(.percent)
    }

    /// Cache share: 0.9943 becomes "99%".
    public static func ratio(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    public static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Compact tokens: 62777 becomes "62.8K", 1000000 becomes "1M".
    public static func tokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// Exact tokens with digit grouping — for the large size, where there is
    /// room and rounding would only throw information away.
    public static func tokensExact(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
