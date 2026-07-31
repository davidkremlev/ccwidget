import Foundation
import Testing

/// The estimate is the one part of this widget that can be confidently wrong,
/// so most of these checks are about it refusing to answer rather than about
/// the answer being right. Thresholds and their reasoning: section 7.
@Suite("Forecast")
struct ForecastTests {

    /// A synthetic history: `count` points, `stepMinutes` apart, rising by
    /// `step` percent each. `noise` perturbs individual points.
    private func series(
        count: Int, stepMinutes: Double, from start: Int, per step: Double,
        resets: Date, now: Date, noise: (Int) -> Double = { _ in 0 }
    ) -> [HistoryEntry] {
        (0..<count).map { i in
            HistoryEntry(
                time: now.addingTimeInterval(-Double(count - 1 - i) * stepMinutes * 60),
                sevenDayUsed: Int((Double(start) + step * Double(i) + noise(i)).rounded()),
                resetsAt: resets
            )
        }
    }

    private func describe(_ outcome: Forecast.Outcome) -> String {
        switch outcome {
        case .notEnoughData: return "notEnoughData"
        case .flat: return "flat"
        case .rateOnly: return "rateOnly"
        case .lastsUntilReset: return "lastsUntilReset"
        case .runsOut: return "runsOut"
        }
    }

    @Test("A perfect straight line over four hours")
    func namesADateOnACleanSeries() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let f = Forecast.make(history: series(count: 25, stepMinutes: 10, from: 20, per: 1.6,
                                              resets: resets, now: now), window: window, now: now)
        #expect((f.fitQuality ?? 0) > 0.99, "a perfect line gives an R² of about one")
        #expect(describe(f.outcome) == "runsOut", "a wide enough base names a date")
        #expect(f.showsProjection, "the dashed line is drawn")
    }

    @Test("Fewer than ten points")
    func rejectsTooFewPoints() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let f = Forecast.make(history: series(count: 9, stepMinutes: 30, from: 20, per: 4,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "notEnoughData", "nine points are rejected")
    }

    @Test("A base shorter than two hours")
    func rejectsShortBase() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let f = Forecast.make(history: series(count: 20, stepMinutes: 5, from: 20, per: 2,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "notEnoughData",
                "a base of an hour and a half is rejected")
    }

    @Test("Noise a straight line does not describe")
    func rejectsPoorFit() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let saw: (Int) -> Double = { i in i % 2 == 0 ? -18 : 18 }
        let f = Forecast.make(history: series(count: 30, stepMinutes: 10, from: 30, per: 0.2,
                                              resets: resets, now: now, noise: saw),
                              window: window, now: now)
        #expect(describe(f.outcome) == "notEnoughData",
                "a line that does not describe the data is rejected on R²")
    }

    /// The case the third state was added for. Right after the weekly reset
    /// the base is hours and the reset is nearly seven days out, so the
    /// horizon rule forbids naming a date — but staying silent for seventeen
    /// hours reads as broken. A rate with no date is the honest answer.
    @Test("Right after the weekly reset")
    func showsRateWithoutDate() {
        let now = Date()
        let resets = now.addingTimeInterval(6.9 * 24 * 3600)
        let window = LimitWindow(usedPercentage: 3, resetsAt: resets)
        let f = Forecast.make(history: series(count: 13, stepMinutes: 10, from: 1, per: 0.15,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "rateOnly", "after a weekly reset — a rate without a date")
        #expect(f.hasRate, "and there is a rate to show")
        #expect(!f.showsProjection, "the dashed line is not drawn")
        #expect((f.percentPerHour ?? 0) > 0, "the rate is positive")
    }

    @Test("A base of a day reaches across the week")
    func widerBaseNamesADate() {
        let now = Date()
        let resets = now.addingTimeInterval(6 * 24 * 3600)
        let window = LimitWindow(usedPercentage: 10, resetsAt: resets)
        let f = Forecast.make(history: series(count: 40, stepMinutes: 40, from: 1, per: 0.22,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) != "rateOnly", "a day-wide base reaches across the week")
    }

    /// Detected from the integer percentages, not from the variance: with
    /// identical values the weighted mean lands a hair off, the variance comes
    /// out microscopically positive and the slope microscopically non-zero, so
    /// a flat series used to fall through to "not enough data".
    @Test("A plateau")
    func recognisesPlateau() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 55, resetsAt: resets)
        let f = Forecast.make(history: series(count: 20, stepMinutes: 15, from: 55, per: 0,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "flat", "a plateau is recognised")
        #expect(!f.hasRate, "no rate is shown on a plateau")
    }

    @Test("Points belonging to a previous window")
    func discardsPointsFromAnotherWindow() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let other = series(count: 30, stepMinutes: 10, from: 20, per: 1.5,
                           resets: resets.addingTimeInterval(-604800), now: now)
        let f = Forecast.make(history: other, window: window, now: now)
        #expect(f.points.isEmpty, "points from a past window are discarded")
        #expect(describe(f.outcome) == "notEnoughData", "and no estimate is built from them")
    }

    @Test("Running out inside the horizon")
    func namesANearDate() {
        let now = Date()
        let resets = now.addingTimeInterval(5 * 24 * 3600)
        let window = LimitWindow(usedPercentage: 80, resetsAt: resets)
        let f = Forecast.make(history: series(count: 15, stepMinutes: 20, from: 60, per: 1.4,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "runsOut", "running out soon is named with a date")

        guard case .runsOut(let date) = f.outcome else { return }
        #expect(date >= now, "the date is not in the past")
        #expect(date.timeIntervalSince(now) <= f.observationSpan * Forecast.horizonMultiplier + 60,
                "the date is within ten base lengths")
    }
}
