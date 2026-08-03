import Foundation

/// An estimate of when the weekly quota runs out. Section 7.
///
/// An estimate, not a prediction, and the interface says so. A lie is worse
/// than silence — but staying silent where something is actually measurable
/// is bad too. A measurement and an extrapolation carry different costs when
/// wrong, so they are kept apart.
public struct Forecast: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Too few points, too narrow a base, or the line does not describe
        /// the data.
        case notEnoughData
        /// The slope is not positive — consumption has stopped.
        case flat
        /// The rate is measured, but the end of the window is further away
        /// than the base supports. The rate is shown without a date: a rate
        /// is a measurement, a date here would be a guess.
        case rateOnly
        /// Exhaustion falls after the reset, and the reset itself is within
        /// the horizon.
        case lastsUntilReset
        /// Exhaustion falls before the reset and within the horizon.
        case runsOut(at: Date)

        public var label: String {
            switch self {
            case .notEnoughData: return "notEnoughData"
            case .flat: return "flat"
            case .rateOnly: return "rateOnly"
            case .lastsUntilReset: return "lastsUntilReset"
            case .runsOut: return "runsOut"
            }
        }
    }

    /// Why the R² gate is where it is. Section 7.
    ///
    /// The gate has two thresholds rather than one, and without this the
    /// difference is invisible: a verdict standing on a current reading and a
    /// verdict standing only on the fact that it was already on screen look
    /// exactly alike from outside.
    public enum Gate: Sendable, Equatable {
        /// R² has never reached the entry threshold in this window. Nothing
        /// has been shown and nothing has been taken back.
        case closed
        /// R² is at or above the entry threshold.
        case open
        /// R² is below the entry threshold but has not fallen to the exit
        /// threshold, and a verdict was already being shown. Hysteresis is
        /// the only reason it is still there.
        case held
        /// A verdict had been shown and R² fell below the exit threshold, so
        /// it was withdrawn. Distinct from `closed`, which never showed
        /// anything: only one of the two is a change the user saw.
        case withdrawn

        public var label: String {
            switch self {
            case .closed: return "closed"
            case .open: return "open"
            case .held: return "held"
            case .withdrawn: return "withdrawn"
            }
        }

        /// Whether a verdict may be shown at all.
        public var admitsAVerdict: Bool {
            switch self {
            case .open, .held: return true
            case .closed, .withdrawn: return false
            }
        }
    }

    public let outcome: Outcome
    /// The points of the current window used for the fit. The chart draws
    /// the same ones.
    public let points: [HistoryEntry]
    /// Percent per second. `nil` when no regression was run.
    public let slope: Double?
    /// When 100% is reached — kept even when it must not be shown.
    public let exhaustionAt: Date?
    /// Share of variance explained. `nil` when no regression was run.
    public let fitQuality: Double?
    /// Length of the observation base — the full range of the points used.
    public let observationSpan: TimeInterval

    /// The part of that base the weighting actually reaches: the interval,
    /// measured back from the newest point, that carries `weightShare` of the
    /// total weight.
    ///
    /// It exists because the horizon rule needs it and because nothing could
    /// see it before. The slope comes from a regression with a twelve-hour
    /// half-life, so on a hundred hours of history the number is made almost
    /// entirely from the last ten or so — while the horizon was being computed
    /// from all hundred. The two halves of section 7 disagreed, and the
    /// disagreement was invisible: neither quantity was exposed.
    public let effectiveSpan: TimeInterval

    /// The state of the R² gate, replayed over this window's history.
    public let gate: Gate

    // MARK: Confidence thresholds

    /// With deduplication at ten-minute intervals, ten points mean they did
    /// not all come from a single burst of activity.
    public static let minimumPoints = 10

    /// Two hours. Half an hour extrapolated three hundred times further
    /// than its own base.
    public static let minimumSpan: TimeInterval = 2 * 3600

    /// Below this the line does not describe the data, and a confident date
    /// misleads more than a dash would. This is the bar for *starting* to
    /// show a verdict, and it is unchanged: everything that argued for 0.7
    /// argued about entering, and nothing measured since argues for a
    /// different number.
    public static let minimumFitQuality = 0.7

    /// The bar for *going on* showing one. Lower than the entry bar, so that
    /// a reading which wanders across the entry threshold does not switch the
    /// block on and off.
    ///
    /// Where the number comes from — 118 hours of one real history, replayed
    /// point by point. R² crossed below 0.7 four times there while a verdict
    /// was on screen. Two of those dips reached 0.648 and 0.653 and recovered
    /// within minutes and within an hour and a half: nothing about the week
    /// had changed, the statistic had merely wobbled. The deepest, 0.507, came
    /// after a sixty-seven-hour gap in the history and did not recover — the
    /// line genuinely no longer described anything, and withdrawing the
    /// verdict there was right.
    ///
    /// So the exit threshold has to sit below 0.653 and above 0.507, and 0.58
    /// is the middle of that interval: as far as one history can put it from
    /// either mistake. The margin either way, 0.073, is about eight tenths of
    /// the standard error of R² at this operating point — 0.089, from a median
    /// effective sample size of 32 behind those fits. One history cannot buy
    /// more precision than that, and pretending otherwise by quoting more
    /// digits would be false.
    ///
    /// Measured consequence on the same 118 hours: eight state changes become
    /// five, and the three that go are exactly the three that were flicker.
    /// `Docs/estimate-review.md` carries the sweep.
    public static let minimumFitQualityToKeep = 0.58

    /// A date is named only if it lies within ten base lengths. Two hours of
    /// observation earn a twenty-hour horizon, not a week.
    public static let horizonMultiplier: Double = 10

    /// Weight half-life: yesterday's marathon must not skew today's
    /// estimate, but the history cannot be thrown away either.
    public static let weightHalfLife: TimeInterval = 12 * 3600

    /// How much of the weight has to fall inside the effective span for it to
    /// count as "the data the slope came from".
    ///
    /// Nine tenths rather than all of it, because the exponential tail never
    /// ends: with every point included the effective span is the full span
    /// again and the rule dissolves. Nine tenths keeps the two measures nearly
    /// equal where they always agreed — a base short against the half-life,
    /// where the weights are near-uniform — and separates them where they did
    /// not, which is what a fix to this ought to do.
    public static let weightShare = 0.9

    // MARK: - The regression

    /// One weighted least-squares fit. Everything the verdict is built from,
    /// and the only place the arithmetic lives: the gate replays this same
    /// function over prefixes rather than reimplementing it, so the two can
    /// never come to mean different things.
    struct Fit {
        var span: TimeInterval
        var effectiveSpan: TimeInterval
        var slope: Double
        var intercept: Double
        /// `nil` when the regression could not be run at all: a plateau, or
        /// no spread left in time after weighting.
        var quality: Double?
    }

    /// `nil` when there are too few points or the base is too narrow — the two
    /// refusals that precede any arithmetic.
    static func fit(_ points: ArraySlice<HistoryEntry>) -> Fit? {
        guard points.count >= minimumPoints,
              let first = points.first,
              let last = points.last
        else { return nil }

        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return nil }

        // A plateau is detected from the integer percentages, not from the
        // variance. With identical values the weighted mean lands a hair off,
        // the variance comes out microscopically positive, the slope
        // microscopically non-zero, and the case fell through to "not enough
        // data".
        let values = points.map(\.sevenDayUsed)
        guard let lowest = values.min(), let highest = values.max(), highest > lowest else {
            return Fit(span: span, effectiveSpan: 0, slope: 0, intercept: 0, quality: nil)
        }

        let origin = first.time
        // Computed once and reused. The gate replays this function over every
        // prefix, so a weight recomputed three times is a weight recomputed
        // three times per prefix.
        let weights = points.map { pow(0.5, last.time.timeIntervalSince($0.time) / weightHalfLife) }
        let offsets = points.map { $0.time.timeIntervalSince(origin) }
        let observed = points.map { Double($0.sevenDayUsed) }

        // How far back the weight actually reaches. Walking from the newest
        // point until nine tenths of the weight is accounted for gives the
        // interval the slope is really made of.
        let totalWeight = weights.reduce(0, +)
        var accumulated = 0.0
        var oldestWeighty = last.time
        for index in points.indices.reversed() {
            accumulated += weights[index - points.startIndex]
            oldestWeighty = points[index].time
            if accumulated >= weightShare * totalWeight { break }
        }
        let effectiveSpan = last.time.timeIntervalSince(oldestWeighty)

        var sumW = 0.0, sumWX = 0.0, sumWY = 0.0
        for i in weights.indices {
            sumW += weights[i]
            sumWX += weights[i] * offsets[i]
            sumWY += weights[i] * observed[i]
        }
        guard sumW > 0 else { return nil }
        let meanX = sumWX / sumW
        let meanY = sumWY / sumW

        var sxy = 0.0, sxx = 0.0
        for i in weights.indices {
            let dx = offsets[i] - meanX
            sxy += weights[i] * dx * (observed[i] - meanY)
            sxx += weights[i] * dx * dx
        }
        guard sxx > 0 else {
            return Fit(span: span, effectiveSpan: effectiveSpan, slope: 0, intercept: 0, quality: nil)
        }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        // How well the line describes the data at all.
        var ssResidual = 0.0, ssTotal = 0.0
        for i in weights.indices {
            let predicted = intercept + slope * offsets[i]
            ssResidual += weights[i] * (observed[i] - predicted) * (observed[i] - predicted)
            ssTotal += weights[i] * (observed[i] - meanY) * (observed[i] - meanY)
        }
        let quality = ssTotal > 0 ? max(0, 1 - ssResidual / ssTotal) : 0

        return Fit(span: span, effectiveSpan: effectiveSpan,
                   slope: slope, intercept: intercept, quality: quality)
    }

    // MARK: - The gate

    /// Replays the two-threshold gate over every prefix of this window's
    /// points, in the order the exporter wrote them.
    ///
    /// Hysteresis needs to know what was on screen a moment ago, and there are
    /// two ways to know it: remember it, or work it out again. Remembering it
    /// would mean the widget writing state — it only ever reads — and it would
    /// make the verdict depend on when the system happened to wake the
    /// provider. Working it out again makes the verdict a function of the
    /// history file and nothing else: the same file gives the same answer on
    /// any machine, at any refresh, in any replay.
    ///
    /// The cost is a fit per point. Measured on this hardware: 1.8 ms at 200
    /// points, 26 ms at 1000, 98 ms at the 2000-line truncation limit — once
    /// per timeline, which is once per half hour.
    ///
    /// A prefix that produces no R² — fewer than ten points, a base under two
    /// hours, a plateau — leaves the gate as it was. It is not evidence about
    /// the fit in either direction, and treating "consumption paused" as
    /// "the line stopped describing the data" would put the flicker back in
    /// through the other door.
    static func latchedGate(_ points: [HistoryEntry]) -> Gate {
        guard points.count >= minimumPoints else { return .closed }

        var open = false
        var everOpened = false
        var newest: Double? = nil

        for k in minimumPoints...points.count {
            guard let quality = fit(points.prefix(k))?.quality else { continue }
            newest = quality
            if open {
                if quality < minimumFitQualityToKeep { open = false }
            } else if quality >= minimumFitQuality {
                open = true
                everOpened = true
            }
        }

        guard open else { return everOpened ? .withdrawn : .closed }
        // `newest` is the last reading that existed; if the newest points are
        // a plateau it is an earlier one, and the verdict stands on the latch
        // rather than on anything current — which is what `held` says.
        return (newest ?? 0) >= minimumFitQuality ? .open : .held
    }

    // MARK: - The verdict

    public static func make(
        history: [HistoryEntry],
        window: LimitWindow,
        now: Date = Date()
    ) -> Forecast {
        // 1. Current window only. A reset drops the percentage in one step,
        //    and a regression across mixed windows produces garbage. It also
        //    starts the gate over: a new week has shown nothing yet.
        let points = history.filter { entry in
            guard let resets = entry.resetsAt else { return false }
            return abs(resets.timeIntervalSince(window.resetsAt)) < 1
        }

        let gate = latchedGate(points)

        // 2. Too few points or too narrow a base — nothing to compute.
        guard let fitted = fit(points[...]), let first = points.first, let last = points.last else {
            var span: TimeInterval = 0
            if points.count >= minimumPoints, let a = points.first, let b = points.last {
                span = b.time.timeIntervalSince(a.time)
            }
            return Forecast(outcome: .notEnoughData, points: points, slope: nil,
                            exhaustionAt: nil, fitQuality: nil, observationSpan: span,
                            effectiveSpan: 0, gate: gate)
        }

        // 3. A plateau, or no spread in time — the rate is zero, not unknown.
        guard let quality = fitted.quality else {
            return Forecast(outcome: .flat, points: points, slope: 0,
                            exhaustionAt: nil, fitQuality: nil,
                            observationSpan: fitted.span, effectiveSpan: fitted.effectiveSpan,
                            gate: gate)
        }

        // 4. Consumption has stopped — nothing to estimate.
        guard fitted.slope > 0 else {
            return Forecast(outcome: .flat, points: points, slope: fitted.slope,
                            exhaustionAt: nil, fitQuality: quality,
                            observationSpan: fitted.span, effectiveSpan: fitted.effectiveSpan,
                            gate: gate)
        }

        // 5. The line does not describe the data — stay silent. Keep the
        //    slope and R² anyway: without them the dump tool cannot show why
        //    it refused, and "not enough data" becomes indistinguishable from
        //    "the line is a poor fit".
        guard gate.admitsAVerdict else {
            return Forecast(outcome: .notEnoughData, points: points, slope: fitted.slope,
                            exhaustionAt: nil, fitQuality: quality,
                            observationSpan: fitted.span, effectiveSpan: fitted.effectiveSpan,
                            gate: gate)
        }

        // 6. Extrapolate to 100%.
        let secondsTo100 = (100 - fitted.intercept) / fitted.slope
        let exhaustion = first.time.addingTimeInterval(max(secondsTo100, 0))

        // 7. Which comes first, and can we say so?
        //
        //    Two questions, and they used to be one. The old code asked only
        //    whether the exhaustion date fell inside the horizon, and named it
        //    when it did — without ever comparing it to the reset. So a quota
        //    that comfortably outlived its window was reported, in red, as
        //    running out on a date fifteen hours after the counter drops back
        //    to zero. Observed live at 11 % used with the reset 140 hours away
        //    and exhaustion extrapolating to 156.
        //
        //    The order comes first because it decides *what* is being claimed.
        //    The horizon comes second because it decides whether that claim is
        //    supported: beyond ten base lengths nothing can be asserted —
        //    neither an exhaustion date nor that the quota lasts to the reset.
        //    The second is every bit as much an extrapolation as the first.
        // Ten times the evidence that produced the slope, not ten times the
        // range of points that happen to exist. Those were the same number
        // until somebody added a weighting, and then they were not: thirty
        // hours of points, eleven hours of weight, a horizon of two hundred
        // and ninety-eight.
        let maxHorizon = fitted.effectiveSpan * horizonMultiplier
        let toExhaustion = exhaustion.timeIntervalSince(last.time)
        let toReset = window.resetsAt.timeIntervalSince(last.time)

        let outcome: Outcome
        if exhaustion < window.resetsAt {
            // The quota runs out inside this window.
            outcome = toExhaustion <= maxHorizon ? .runsOut(at: max(exhaustion, now)) : .rateOnly
        } else {
            // The reset arrives first and takes the counter back to zero, so
            // there is no date to name — only the fact that the window is
            // survived, and only if the reset itself is close enough to claim.
            outcome = toReset <= maxHorizon ? .lastsUntilReset : .rateOnly
        }

        return Forecast(outcome: outcome, points: points, slope: fitted.slope,
                        exhaustionAt: exhaustion, fitQuality: quality,
                        observationSpan: fitted.span, effectiveSpan: fitted.effectiveSpan,
                        gate: gate)
    }

    /// Consumption in percent per hour — a measurement, not an
    /// extrapolation. Honest at any base length, which is why it is shown
    /// even when no date can be named.
    public var percentPerHour: Double? {
        slope.map { $0 * 3600 }
    }

    /// Whether there is a rate worth showing.
    public var hasRate: Bool {
        switch outcome {
        case .rateOnly, .lastsUntilReset, .runsOut: return (percentPerHour ?? 0) > 0
        case .flat, .notEnoughData: return false
        }
    }

    /// Whether to draw the projection. Not for `.rateOnly`: a dashed line
    /// running to a hundred percent is the unnamed date, only drawn.
    public var showsProjection: Bool {
        if case .runsOut = outcome { return true }
        if case .lastsUntilReset = outcome { return true }
        return false
    }
}
