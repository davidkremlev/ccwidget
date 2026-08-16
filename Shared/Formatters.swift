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
    /// When the snapshot was taken: "11:50".
    ///
    /// This replaced a ticking age ("2 minutes ago") in the batch that moved
    /// the countdown onto dynamic dates. The reason is not that Apple asked
    /// for fewer reloads — it is that a ticking age is wrong between updates
    /// and a capture moment is right forever. A widget redrawn every five
    /// minutes and printing "1 minute ago" is not imprecise, it is untrue for
    /// four minutes out of five; "11:50" stays true whenever it is read.
    ///
    /// How old that is remains visible, but in colour and in words rather than
    /// in a number: `Freshness` dims the tile past an hour and replaces the
    /// figures past a day. Section 2.4.
    ///
    /// The locale is a parameter for the same reason `resetMoment`'s is: a
    /// view rendering against `.environment(\.locale, …)` and a string
    /// formatted against the process locale disagree with each other.
    ///
    /// So is the time zone, and for the same reason again — found the hard
    /// way. See `resetMoment`.
    public static func capturedMoment(_ date: Date,
                                      locale: Locale = .autoupdatingCurrent,
                                      timeZone: TimeZone = .autoupdatingCurrent) -> String {
        date.formatted(style(.dateTime.hour().minute(), locale, timeZone))
    }

    /// Everything a formatted date takes from its surroundings, taken from
    /// arguments instead.
    ///
    /// The calendar comes from the locale rather than from the process for the
    /// same reason as the other two: a weekday is a calendar's answer, and the
    /// system's calendar can be one the locale does not imply. Taking it from
    /// the locale keeps a person's own choice in the product — a locale knows
    /// the calendar they picked — while pinning it wherever the locale is
    /// pinned.
    private static func style(_ base: Date.FormatStyle,
                              _ locale: Locale,
                              _ timeZone: TimeZone) -> Date.FormatStyle {
        var style = base
        style.locale = locale
        style.timeZone = timeZone
        style.calendar = locale.calendar
        return style
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
    ///
    /// **The time zone is a parameter because the sentence above turned out to
    /// be true of it too, and nobody had noticed.** A weekday and a time are
    /// whatever the machine's zone says they are, so `chart-runs-out.png` was
    /// carrying Asia/Tashkent inside it and failed on a CI runner running UTC
    /// — 548 pixels, 179 of 255 apart, in the one line of the picture that is
    /// text. Measured on 16 August 2026: running the built checks under
    /// `TZ=UTC` failed exactly one of 227, that one.
    ///
    /// It matters beyond the baseline. Anything that renders this string
    /// somewhere other than the moment and machine it will be read on — a
    /// screenshot, a rendered preview — has been quietly stamping its own zone
    /// on it.
    public static func resetMoment(_ date: Date,
                                   locale: Locale = .autoupdatingCurrent,
                                   timeZone: TimeZone = .autoupdatingCurrent) -> String {
        date.formatted(style(.dateTime.weekday(.abbreviated).hour().minute(), locale, timeZone))
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
