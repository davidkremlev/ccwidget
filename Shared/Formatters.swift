import Foundation

/// Localized formatting. No hand-assembled strings — see section 10.
public enum CCWidgetFormat {
    /// "2 minutes ago". Localized out of the box.
    ///
    /// Both surfaces come through here, and everything about the resolution is
    /// decided here rather than at the call sites — that is the whole point of
    /// there being one function. Three things happen to the number on its way
    /// in:
    ///
    /// **The moment is snapped to the start of its minute.** The window's clock
    /// and the widget's differ by seconds; the minute they fall in is the same
    /// minute. `AgeClock` says why that is enough and what has to hold for it.
    ///
    /// **The age is floored to whole minutes.** A widget redraws once a minute,
    /// so "42 seconds ago" is a precision it does not have; the window sitting
    /// beside it must not claim it either. Floored rather than rounded, so the
    /// number is always something the data has actually reached — which is how
    /// the formatter already treats everything above a minute.
    ///
    /// **Anything at or below zero reads as the present.** A snapshot can be
    /// stamped after the entry currently on screen, and the numeric wording for
    /// a negative age is "in 0 seconds" — a widget promising that the data is
    /// about to arrive.
    /// The locale is a parameter for the same reason `resetMoment`'s is: a
    /// view rendering against `.environment(\.locale, …)` and a string
    /// formatted against the process locale disagree with each other. It is
    /// also the only way to measure how wide this gets in German without
    /// rebuilding the formatter in the check and hoping the two agree.
    public static func relativeAge(of date: Date, at now: Date = Date(),
                                   locale: Locale = .autoupdatingCurrent) -> String {
        let anchor = AgeClock.anchor(now)
        let minutes = max(0, (anchor.timeIntervalSince(date) / 60).rounded(.down))

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        // Under a minute there is no duration to name — the statement is "this
        // is current", and every locale we ship has a word for it. Above a
        // minute the numeric wording is the one to keep: `.named` turns a day
        // into "yesterday" and a week into "last week", which are facts about
        // the calendar rather than about how old the data is, and section 2.4
        // wants stale data to look its age.
        formatter.dateTimeStyle = minutes == 0 ? .named : .numeric
        return formatter.localizedString(for: anchor.addingTimeInterval(-minutes * 60),
                                         relativeTo: anchor)
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
    ///
    /// The locale is a parameter for the same reason the rate's is: a view
    /// that renders against `.environment(\.locale, …)` and formats against
    /// the process locale disagrees with itself, and a baseline taken on one
    /// machine then fails on another.
    public static func resetMoment(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(locale))
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
