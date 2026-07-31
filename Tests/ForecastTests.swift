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

    // MARK: The verdict, not the arithmetic

    /// The defect these were written for. Observed live: 11 % of the week
    /// used, the reset 140 hours away, consumption extrapolating to 100 % in
    /// 156 hours — and the widget saying, in red, "runs out ~Thu 22:40",
    /// fifteen hours after the counter resets itself to zero.
    ///
    /// Eighteen checks on this file missed it because all eighteen tested the
    /// arithmetic. The verdict is a separate claim, and this is where it is
    /// made.
    @Test("A quota that survives the reset is never reported as running out")
    func exhaustionAfterResetLastsUntilReset() {
        let now = Date()
        // Six days to the reset, a day-wide base, and a rate that reaches
        // 100 % well after the reset but well inside the horizon.
        let resets = now.addingTimeInterval(140 * 3600)
        let window = LimitWindow(usedPercentage: 11, resetsAt: resets)
        let f = Forecast.make(history: series(count: 40, stepMinutes: 40, from: 1, per: 0.25,
                                              resets: resets, now: now), window: window, now: now)

        let exhaustion = try! #require(f.exhaustionAt)
        #expect(exhaustion > resets,
                "the fixture is wrong: exhaustion must fall after the reset")
        #expect(exhaustion.timeIntervalSince(now) <= f.observationSpan * Forecast.horizonMultiplier,
                "the fixture is wrong: exhaustion must be inside the horizon")

        #expect(describe(f.outcome) == "lastsUntilReset",
                "got \(describe(f.outcome)) for a quota that outlives its window")
        #expect(f.showsProjection, "lastsUntilReset draws the dashed line")
        #expect(f.hasRate, "lastsUntilReset shows a rate")
    }

    /// The other half of the same boundary: exhaustion before the reset is a
    /// date, and it must not be swallowed by the reset comparison.
    @Test("A quota that does not survive the reset is reported as running out")
    func exhaustionBeforeResetRunsOut() {
        let now = Date()
        let resets = now.addingTimeInterval(120 * 3600)
        let window = LimitWindow(usedPercentage: 80, resetsAt: resets)
        let f = Forecast.make(history: series(count: 15, stepMinutes: 20, from: 60, per: 1.4,
                                              resets: resets, now: now), window: window, now: now)

        let exhaustion = try! #require(f.exhaustionAt)
        #expect(exhaustion < resets, "the fixture is wrong: exhaustion must precede the reset")
        #expect(describe(f.outcome) == "runsOut", "got \(describe(f.outcome))")
    }

    /// What the user can do in their head must not contradict what the widget
    /// says. Both numbers are on screen — the percentage in its row, the rate
    /// under the chart — so anyone can divide one by the other. If that
    /// arithmetic says the quota lasts and the widget says it runs out, the
    /// estimate has spent its credibility, whatever the regression thinks.
    ///
    /// Stated as a direction rather than a tolerance: the two need not agree
    /// to the hour, because the row shows the latest raw sample while the
    /// estimate uses the fitted line, and forcing them to agree exactly would
    /// let one noisy sample move the date. They must not disagree about
    /// whether there is a problem.
    @Test("The napkin arithmetic and the verdict never disagree",
          arguments: [10, 25, 40, 55, 70, 85])
    func rateAndVerdictAgree(used: Int) {
        let now = Date()
        let resets = now.addingTimeInterval(100 * 3600)
        let window = LimitWindow(usedPercentage: used, resetsAt: resets)
        let f = Forecast.make(history: series(count: 30, stepMinutes: 30, from: used - 8,
                                              per: 0.3, resets: resets, now: now),
                              window: window, now: now)

        guard let rate = f.percentPerHour, rate > 0 else { return }
        let hoursByHand = Double(100 - used) / rate
        let hoursToReset = resets.timeIntervalSince(now) / 3600

        if hoursByHand > hoursToReset {
            #expect(describe(f.outcome) != "runsOut",
                    "by hand the quota lasts \(Int(hoursByHand)) h against \(Int(hoursToReset)) h to the reset, but the widget names a date")
        }
    }

    /// "The slope is not positive" covers falling as well as level. A value
    /// that goes down — a corrected reading, or a window that reset between
    /// two writes — must not extrapolate to a date in the past.
    @Test("A falling series is flat, not a date behind us")
    func fallingSeriesIsFlat() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 40, resetsAt: resets)
        let f = Forecast.make(history: series(count: 20, stepMinutes: 15, from: 60, per: -1,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "flat", "got \(describe(f.outcome))")
        #expect(!f.hasRate, "a falling series has no rate worth showing")
        #expect(f.exhaustionAt == nil, "and no exhaustion date")
    }

    // MARK: What survives a refusal

    /// The dump tool exists to say *why* the estimate refused, and it cannot
    /// if the numbers behind the refusal are thrown away. Without this,
    /// "not enough data" and "the line does not fit" are the same message.
    @Test("A rejected fit keeps its slope and its R²")
    func rejectedFitKeepsItsNumbers() {
        let now = Date()
        let resets = now.addingTimeInterval(20 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let saw: (Int) -> Double = { i in i % 2 == 0 ? -18 : 18 }
        let f = Forecast.make(history: series(count: 30, stepMinutes: 10, from: 30, per: 0.2,
                                              resets: resets, now: now, noise: saw),
                              window: window, now: now)

        #expect(describe(f.outcome) == "notEnoughData")
        #expect(f.slope != nil, "the slope is kept so the refusal can be explained")
        #expect(f.fitQuality != nil, "and so is R²")
        #expect((f.fitQuality ?? 1) < Forecast.minimumFitQuality,
                "R² = \(f.fitQuality ?? -1)")
    }

    /// Kept but not shown. `.rateOnly` means the horizon does not support a
    /// date, not that none was computed — and the distinction is what lets
    /// the diagnostics say which of the two happened.
    @Test("A rate-only estimate still carries the date it will not name")
    func rateOnlyKeepsItsExhaustion() {
        let now = Date()
        let resets = now.addingTimeInterval(6.9 * 24 * 3600)
        let window = LimitWindow(usedPercentage: 3, resetsAt: resets)
        let f = Forecast.make(history: series(count: 13, stepMinutes: 10, from: 1, per: 0.15,
                                              resets: resets, now: now), window: window, now: now)
        #expect(describe(f.outcome) == "rateOnly")
        #expect(f.exhaustionAt != nil, "the date was computed, only withheld")
    }

    // MARK: Recency weighting

    /// The weighting could be deleted outright and every other check here
    /// would still pass — which means it could already have stopped working
    /// and nothing would say so.
    ///
    /// Two series with the same endpoints and different middles: one that
    /// raced early and slowed down, one that idled and then accelerated. An
    /// unweighted fit gives them the same slope. A fit that weights recent
    /// points more heavily must call the accelerating one faster.
    @Test("Recent points weigh more than old ones")
    func recencyWeightingChangesTheSlope() {
        let now = Date()
        let resets = now.addingTimeInterval(40 * 3600)
        let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
        let count = 25
        let step = 60.0   // minutes — a day of base, comparable to the half-life

        func made(_ shape: (Int) -> Int) -> [HistoryEntry] {
            (0..<count).map { i in
                HistoryEntry(
                    time: now.addingTimeInterval(-Double(count - 1 - i) * step * 60),
                    sevenDayUsed: shape(i),
                    resetsAt: resets)
            }
        }

        // Both run from 20 % to 60 %. The first spends its budget early, the
        // second late.
        let earlyRush = made { i in
            let t = Double(i) / Double(count - 1)
            return 20 + Int((40 * sqrt(t)).rounded())
        }
        let lateRush = made { i in
            let t = Double(i) / Double(count - 1)
            return 20 + Int((40 * t * t).rounded())
        }

        let a = Forecast.make(history: earlyRush, window: window, now: now)
        let b = Forecast.make(history: lateRush, window: window, now: now)

        let slopeEarly = try! #require(a.percentPerHour)
        let slopeLate = try! #require(b.percentPerHour)

        #expect(slopeLate > slopeEarly,
                "the accelerating series must read faster: \(slopeLate) vs \(slopeEarly)")
    }
}
