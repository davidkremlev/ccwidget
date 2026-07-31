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
    /// Length of the observation base.
    public let observationSpan: TimeInterval

    // MARK: Confidence thresholds

    /// With deduplication at ten-minute intervals, ten points mean they did
    /// not all come from a single burst of activity.
    public static let minimumPoints = 10

    /// Two hours. Half an hour extrapolated three hundred times further
    /// than its own base.
    public static let minimumSpan: TimeInterval = 2 * 3600

    /// Below this the line does not describe the data, and a confident date
    /// misleads more than a dash would.
    public static let minimumFitQuality = 0.7

    /// A date is named only if it lies within ten base lengths. Two hours of
    /// observation earn a twenty-hour horizon, not a week.
    public static let horizonMultiplier: Double = 10

    /// Weight half-life: yesterday's marathon must not skew today's
    /// estimate, but the history cannot be thrown away either.
    public static let weightHalfLife: TimeInterval = 12 * 3600

    public static func make(
        history: [HistoryEntry],
        window: LimitWindow,
        now: Date = Date()
    ) -> Forecast {
        // 1. Current window only. A reset drops the percentage in one step,
        //    and a regression across mixed windows produces garbage.
        let points = history.filter { entry in
            guard let resets = entry.resetsAt else { return false }
            return abs(resets.timeIntervalSince(window.resetsAt)) < 1
        }

        func giveUp(_ span: TimeInterval = 0) -> Forecast {
            Forecast(outcome: .notEnoughData, points: points, slope: nil,
                     exhaustionAt: nil, fitQuality: nil, observationSpan: span)
        }

        // 2. Too few points or too narrow a base — nothing to compute.
        guard points.count >= minimumPoints,
              let first = points.first,
              let last = points.last
        else { return giveUp() }

        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return giveUp(span) }

        // A plateau is detected from the integer percentages, not from the
        // variance. With identical values the weighted mean lands a hair off,
        // the variance comes out microscopically positive, the slope
        // microscopically non-zero, and the case fell through to "not enough
        // data".
        let values = points.map(\.sevenDayUsed)
        guard let lowest = values.min(), let highest = values.max(), highest > lowest else {
            return Forecast(outcome: .flat, points: points, slope: 0,
                            exhaustionAt: nil, fitQuality: nil, observationSpan: span)
        }

        // 3. Weighted least-squares regression.
        let origin = first.time
        func weight(_ point: HistoryEntry) -> Double {
            pow(0.5, last.time.timeIntervalSince(point.time) / weightHalfLife)
        }

        var sumW = 0.0, sumWX = 0.0, sumWY = 0.0
        for p in points {
            let w = weight(p)
            sumW += w
            sumWX += w * p.time.timeIntervalSince(origin)
            sumWY += w * Double(p.sevenDayUsed)
        }
        guard sumW > 0 else { return giveUp(span) }
        let meanX = sumWX / sumW
        let meanY = sumWY / sumW

        var sxy = 0.0, sxx = 0.0
        for p in points {
            let w = weight(p)
            let dx = p.time.timeIntervalSince(origin) - meanX
            sxy += w * dx * (Double(p.sevenDayUsed) - meanY)
            sxx += w * dx * dx
        }
        guard sxx > 0 else {
            return Forecast(outcome: .flat, points: points, slope: 0,
                            exhaustionAt: nil, fitQuality: nil, observationSpan: span)
        }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        // 4. How well the line describes the data at all.
        var ssResidual = 0.0, ssTotal = 0.0
        for p in points {
            let w = weight(p)
            let x = p.time.timeIntervalSince(origin)
            let y = Double(p.sevenDayUsed)
            let predicted = intercept + slope * x
            ssResidual += w * (y - predicted) * (y - predicted)
            ssTotal += w * (y - meanY) * (y - meanY)
        }
        let quality = ssTotal > 0 ? max(0, 1 - ssResidual / ssTotal) : 0

        // 5. Consumption has stopped — nothing to estimate.
        guard slope > 0 else {
            return Forecast(outcome: .flat, points: points, slope: slope,
                            exhaustionAt: nil, fitQuality: quality, observationSpan: span)
        }

        // 6. The line does not describe the data — stay silent. Keep the
        //    slope and R² anyway: without them the dump tool cannot show why
        //    it refused, and "not enough data" becomes indistinguishable from
        //    "the line is a poor fit".
        guard quality >= minimumFitQuality else {
            return Forecast(outcome: .notEnoughData, points: points, slope: slope,
                            exhaustionAt: nil, fitQuality: quality, observationSpan: span)
        }

        // 7. Extrapolate to 100%.
        let secondsTo100 = (100 - intercept) / slope
        let exhaustion = origin.addingTimeInterval(max(secondsTo100, 0))

        // 8. Which comes first, and can we say so?
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
        let maxHorizon = span * horizonMultiplier
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

        return Forecast(outcome: outcome, points: points, slope: slope,
                        exhaustionAt: exhaustion, fitQuality: quality,
                        observationSpan: span)
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
