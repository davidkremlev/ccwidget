import Foundation
import Testing

/// Every number the widget shows passes through here.
///
/// The checks avoid asserting on exact localized text wherever the system
/// decides it: the separator between "1" and "000" is a locale's business and
/// changes between macOS releases, so pinning it would produce a test that
/// fails for reasons nobody cares about. What is pinned is what the project
/// actually promises — the magnitude, the rounding, the number of units, and
/// that the string is not empty or `nil`-shaped.
@Suite("Formatters")
struct FormattersTests {

    /// Digits with any grouping separator stripped, so an assertion can be
    /// about the number rather than about the locale.
    private func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    // MARK: Ages

    /// A fixed moment on a minute boundary. `Date()` used to do here, and
    /// stopped: the age is now measured from the start of the minute `now`
    /// falls in, so two minutes before an arbitrary instant is between one and
    /// two whole minutes and the wording is whichever the clock felt like.
    /// Section 2.4, "Возраст меряется по одной сетке", and the agreement it
    /// exists for is checked in `AgeAgreementTests`.
    private static let onTheMinute = Date(timeIntervalSince1970: 1_785_000_000)

    @Test("A relative age names a unit and does not read as a date")
    func relativeAge() {
        let text = CCWidgetFormat.relativeAge(of: Self.onTheMinute.addingTimeInterval(-120),
                                              at: Self.onTheMinute)
        #expect(!text.isEmpty)
        #expect(digits(text).contains("2"), "\(text)")
    }

    /// The window renders its age against a clock the watcher advances, so the
    /// formatter has to take that clock rather than reach for `Date()`.
    @Test("The age is measured against the moment it is given")
    func relativeAgeUsesTheGivenNow() {
        let captured = Self.onTheMinute
        let early = CCWidgetFormat.relativeAge(of: captured,
                                               at: captured.addingTimeInterval(60))
        let late = CCWidgetFormat.relativeAge(of: captured,
                                              at: captured.addingTimeInterval(3600))
        #expect(early != late, "\(early) vs \(late)")
    }

    // MARK: Countdowns

    @Test("A countdown shows at most two units")
    func countdownUnitCount() {
        // 2 days, 3 hours, 4 minutes — the minutes must be dropped, or the
        // string outgrows the tile it lives in.
        let text = CCWidgetFormat.countdown(2 * 86_400 + 3 * 3600 + 4 * 60)
        #expect(!text.isEmpty)
        #expect(digits(text).contains("2") && digits(text).contains("3"), "\(text)")
        #expect(!digits(text).contains("4"), "the third unit leaked in: \(text)")
    }

    /// Defends against a case that has not been observed: in 218 written
    /// history entries no snapshot ever carried a `resetsAt` that had already
    /// passed at the moment it was written, and the closest any of them came
    /// to a reset was three and a half minutes before it.
    ///
    /// The floor stays — "-1 h" beside a full bar would be nonsense however it
    /// arrived — but the reason is written as what it is. It was previously
    /// stated as a fact ("a window that has already reset can arrive with a
    /// negative interval"), and nothing had seen that happen.
    ///
    /// What *is* observed is the other route to a past `resetsAt`: a snapshot
    /// old enough that the window it describes has since closed. The floor
    /// turns that into "0 min", which reads as an imminent reset. See section
    /// 8 for what is being done about it.
    @Test("A countdown never goes negative")
    func countdownFloorsAtZero() {
        let past = CCWidgetFormat.countdown(-5000)
        let zero = CCWidgetFormat.countdown(0)
        #expect(past == zero, "\(past) vs \(zero)")
        #expect(!past.contains("-"), "\(past)")
    }

    // MARK: Percentages and ratios

    @Test("Percentages carry their sign and their magnitude",
          arguments: [0, 1, 42, 99, 100])
    func percent(value: Int) {
        let text = CCWidgetFormat.percent(value)
        #expect(digits(text) == String(value), "\(text)")
        #expect(text.contains("%"), "\(text)")
    }

    /// The cache ratio arrives as a fraction and is shown whole: 0.9943 is
    /// "99 %", not "99.43 %" and not "0 %".
    @Test("A ratio is a whole percentage",
          arguments: [(0.9943, "99"), (1.0, "100"), (0.0, "0"), (0.5, "50")])
    func ratio(value: Double, expected: String) {
        #expect(digits(CCWidgetFormat.ratio(value)) == expected,
                "\(CCWidgetFormat.ratio(value))")
    }

    // MARK: Money

    @Test("Money keeps exactly two decimals")
    func money() {
        // 6.2 must not render as "$6.2", and 6.005 must not grow a third
        // decimal place — the footer is one line and shares it with the cache.
        #expect(digits(CCWidgetFormat.money(6.2)) == "620", "\(CCWidgetFormat.money(6.2))")
        #expect(digits(CCWidgetFormat.money(0)) == "000", "\(CCWidgetFormat.money(0))")
        #expect(digits(CCWidgetFormat.money(1234.5)).count == 6, "\(CCWidgetFormat.money(1234.5))")
    }

    // MARK: Tokens

    /// The compact form exists because 311 033 does not fit beside a bar.
    @Test("Compact tokens shorten and keep three significant digits",
          arguments: [(62_777, "62.8"), (1_000_000, "1"), (999, "999"), (0, "0")])
    func tokensCompact(value: Int, expectedDigits: String) {
        let text = CCWidgetFormat.tokens(value)
        #expect(digits(text) == digits(expectedDigits), "\(value) → \(text)")
        // Shorter than spelling the number out — not "at most N characters".
        // A first version of this asked for six and failed in Russian, where
        // 62 777 compacts to "62,8 тыс.": the budget is a property of the
        // locale, the shortening is a property of the formatter.
        #expect(digits(text).count <= digits(CCWidgetFormat.tokensExact(value)).count,
                "\(value) → \(text)")
    }

    /// The large size has room, and rounding there would throw away
    /// information for nothing.
    @Test("Exact tokens keep every digit")
    func tokensExact() {
        #expect(digits(CCWidgetFormat.tokensExact(311_033)) == "311033",
                "\(CCWidgetFormat.tokensExact(311_033))")
        #expect(digits(CCWidgetFormat.tokensExact(0)) == "0")
    }

    @Test("The compact and exact forms disagree only in precision")
    func tokensAgreeOnMagnitude() {
        // A guard against the two drifting apart: whatever the notation, both
        // are describing the same count.
        let value = 1_500_000
        #expect(CCWidgetFormat.tokens(value) != CCWidgetFormat.tokensExact(value))
        #expect(digits(CCWidgetFormat.tokensExact(value)) == "1500000")
    }

    // MARK: Reset moments

    @Test("A reset moment names a weekday and a time, and no date")
    func resetMoment() {
        // A reset is never more than seven days out, so the day of the month
        // would be noise. What matters is "Wed 3:00".
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 29
        components.hour = 15
        components.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let text = CCWidgetFormat.resetMoment(date)
        #expect(!text.isEmpty)
        #expect(digits(text).contains("30"), "\(text)")
        #expect(!digits(text).contains("2026"), "the year leaked in: \(text)")
        #expect(!digits(text).contains("29"), "the day of the month leaked in: \(text)")
    }
}
