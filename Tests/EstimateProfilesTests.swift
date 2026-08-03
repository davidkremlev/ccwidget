import Foundation
import Testing

/// Eight synthetic weeks, replayed through the estimate point by point.
///
/// These exist because the one real history there is never ran out of quota,
/// so it can measure false alarms and nothing else — a scheme that never warns
/// would score perfectly on it. Four of the eight weeks below do run out, and
/// what they measure is the opposite quantity: **how long before exhaustion the
/// date first appears.**
///
/// That number is a floor, not a record. Anything that makes the estimate
/// steadier, quieter or prettier and shortens it is a bad trade — the whole
/// point of the block is the warning, and a week of warning is worth more than
/// a week of not flickering. So the measured lead times are written down here
/// and a change that shortens any of them fails.
///
/// What they are not: real. A profile is a hypothesis about how someone works,
/// and these eight are one person's hypotheses. They were chosen to include the
/// shapes that ought to be hardest — an acceleration, a week that stays quiet
/// and then surges, work in bursts — but a second real history would be worth
/// more than all eight. `Docs/estimate-review.md` says so at greater length.
@Suite("Estimate: synthetic weeks")
struct EstimateProfilesTests {

    // MARK: - Building a week

    /// Deterministic noise. The same profile has to be the same week on every
    /// machine and every run, or the lead times below mean nothing.
    struct Pseudo {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 2862933555777941757 &+ 3037000493 }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) % 1_000_000) / 1_000_000
        }
    }

    /// A week of work is not a straight line even when its average is one:
    /// sessions come in unequal lumps with pauses in them. Without the lumps
    /// every profile fits a straight line to three decimal places and none of
    /// them says anything about a gate on R².
    ///
    /// Half-hour multipliers, some of them zero.
    struct Lumps: Sendable {
        let blocks: [Double]
        static let block = 0.5   // hours

        init(seed: UInt64, pauseShare: Double = 0.18, spread: Double = 0.85) {
            var rng = Pseudo(seed: seed)
            var made: [Double] = []
            for _ in 0...(Int(Profile.windowHours / Self.block) + 2) {
                made.append(rng.next() < pauseShare ? 0 : 1 - spread + 2 * spread * rng.next())
            }
            blocks = made
        }

        func callAsFunction(_ hour: Double) -> Double {
            blocks[min(blocks.count - 1, max(0, Int(hour / Self.block)))]
        }
    }

    struct Profile: Sendable {
        let name: String
        /// Whether Claude Code is running `hour` hours into the window.
        let active: @Sendable (Double) -> Bool
        /// Consumption intensity while it is, before the lumps.
        let intensity: @Sendable (Double) -> Double
        let lumps: Lumps
        /// The curve is scaled so that it reaches `reaches` per cent at
        /// `target` hours. For a week that runs out, a hundred.
        let reaches: Double
        let target: Double

        static let windowHours = 168.0
        static let minute = 1.0 / 60.0

        /// Per cent used at every minute of the week, and when 100 % is hit.
        func trace() -> (usage: [Double], exhaustedAt: Double?) {
            var raw: [Double] = []
            var running = 0.0
            for step in 0...Int(Self.windowHours / Self.minute) {
                let hour = Double(step) * Self.minute
                if active(hour) { running += intensity(hour) * lumps(hour) * Self.minute }
                raw.append(running)
            }
            let at = raw[min(raw.count - 1, Int(target / Self.minute))]
            let usage = raw.map { at > 0 ? $0 * reaches / at : 0 }
            // A hair under a hundred, because the scaling above lands on a
            // hundred by construction and floating point does not always
            // agree. Without the slack the week runs out at the next minute
            // of work instead, which on a bursty profile is an hour later —
            // a fixture that moves with the last bit of a division.
            return (usage, usage.firstIndex { $0 >= 100 - 1e-9 }.map { Double($0) * Self.minute })
        }

        /// What the exporter would have written: a line every ten minutes
        /// while Claude Code runs, and nothing at all while it does not. The
        /// gaps matter more than the lines — they are what a weighted fit has
        /// to survive.
        func history(start: Date, resets: Date) -> [HistoryEntry] {
            let (usage, exhausted) = trace()
            let stop = min(exhausted ?? Self.windowHours, Self.windowHours)
            var entries: [HistoryEntry] = []
            var hour = 0.0
            while hour <= stop {
                if active(hour) {
                    let value = min(100, usage[min(usage.count - 1, Int(hour / Self.minute))])
                    entries.append(HistoryEntry(time: start.addingTimeInterval(hour * 3600),
                                                sevenDayUsed: Int(value.rounded()),
                                                resetsAt: resets))
                }
                hour += 1.0 / 6.0
            }
            return entries
        }
    }

    static func officeHours(_ from: Double, _ to: Double, days: Range<Int> = 0..<7) -> @Sendable (Double) -> Bool {
        { hour in
            let day = Int(hour / 24)
            return days.contains(day) && hour - Double(day) * 24 >= from && hour - Double(day) * 24 < to
        }
    }

    /// Work in bursts that do not line up with the day at all: an hour or
    /// three on, a few hours off, at whatever intensity.
    static func bursts(seed: UInt64) -> (@Sendable (Double) -> Bool, @Sendable (Double) -> Double) {
        var rng = Pseudo(seed: seed)
        var spans: [(start: Double, end: Double, heat: Double)] = []
        var t = 0.0
        while t < Profile.windowHours {
            let on = 0.7 + 3.5 * rng.next()
            spans.append((t, t + on, 0.2 + 2.6 * rng.next()))
            t += on + 0.5 + 6.0 * rng.next()
        }
        let table = spans
        return ({ hour in table.contains { hour >= $0.start && hour < $0.end } },
                { hour in table.first { hour >= $0.start && hour < $0.end }?.heat ?? 0 })
    }

    static let profiles: [Profile] = {
        let (burstA, heatA) = bursts(seed: 20260803)
        let (burstB, heatB) = bursts(seed: 771)
        return [
            Profile(name: "steady, survives",
                    active: officeHours(9, 19), intensity: { _ in 1 }, lumps: Lumps(seed: 11),
                    reaches: 70, target: 168),
            Profile(name: "steady, exhausts",
                    active: officeHours(9, 19), intensity: { _ in 1 }, lumps: Lumps(seed: 22),
                    reaches: 100, target: 134),
            Profile(name: "accelerating, exhausts",
                    active: officeHours(9, 19), intensity: { 1 + 4 * ($0 / 135) }, lumps: Lumps(seed: 33),
                    reaches: 100, target: 135),
            Profile(name: "quiet then a surge",
                    active: { $0 < 120 ? officeHours(10, 14)($0) : officeHours(8, 24)($0) },
                    intensity: { $0 < 120 ? 1 : 9 }, lumps: Lumps(seed: 44),
                    reaches: 100, target: 160),
            Profile(name: "weekdays only, survives",
                    active: officeHours(9, 19, days: 0..<5), intensity: { _ in 1 }, lumps: Lumps(seed: 55),
                    reaches: 60, target: 168),
            Profile(name: "decelerating, survives",
                    active: officeHours(9, 19), intensity: { 1 / (1 + $0 / 40) }, lumps: Lumps(seed: 66),
                    reaches: 55, target: 168),
            Profile(name: "bursty, survives",
                    active: burstA, intensity: heatA, lumps: Lumps(seed: 77),
                    reaches: 65, target: 168),
            Profile(name: "bursty, exhausts",
                    active: burstB, intensity: heatB, lumps: Lumps(seed: 88),
                    reaches: 100, target: 128),
        ]
    }()

    // MARK: - Replaying one

    /// What one moment of the replay looked like. The whole `Forecast` is not
    /// kept: it carries every point it was built from, and a week's worth of
    /// those times a week's worth of moments is tens of megabytes for two
    /// numbers.
    struct Sample: Sendable {
        let fitQuality: Double?
        let gate: Forecast.Gate
    }

    struct Run: Sendable {
        /// Hours between the date first appearing and the quota actually
        /// running out. `nil` if no date was ever shown.
        var warningHours: Double?
        /// Share of the week a date was on screen.
        var dateShare: Double
        /// Every fit, so a property can be checked at each of them.
        var samples: [Sample]
    }

    /// Replaying a week is a fit per point per point, and each of the checks
    /// below wants the same eight weeks. Once each.
    static let runs: [String: Run] = Dictionary(
        uniqueKeysWithValues: profiles.map { ($0.name, replay($0)) })

    /// Replays a profile the way the widget would have seen it: a verdict is
    /// computed when a line is written and stays on screen until the next one.
    static func replay(_ profile: Profile) -> Run {
        let start = Date(timeIntervalSince1970: 1_785_000_000)
        let resets = start.addingTimeInterval(Profile.windowHours * 3600)
        let (_, exhausted) = profile.trace()
        let points = profile.history(start: start, resets: resets)
        let endsAt = start.addingTimeInterval((exhausted ?? Profile.windowHours) * 3600)

        var samples: [Sample] = []
        var firstDate: Date? = nil
        var dated: TimeInterval = 0
        var total: TimeInterval = 0

        for k in 1...points.count {
            let last = points[k - 1]
            let forecast = Forecast.make(
                history: Array(points.prefix(k)),
                window: LimitWindow(usedPercentage: last.sevenDayUsed, resetsAt: resets),
                now: last.time)
            samples.append(Sample(fitQuality: forecast.fitQuality, gate: forecast.gate))

            let until = k < points.count ? points[k].time : endsAt
            let held = max(0, until.timeIntervalSince(last.time))
            total += held
            if case .runsOut = forecast.outcome {
                dated += held
                if firstDate == nil { firstDate = last.time }
            }
        }

        var warning: Double? = nil
        if let exhausted, let firstDate {
            warning = start.addingTimeInterval(exhausted * 3600).timeIntervalSince(firstDate) / 3600
        }
        return Run(warningHours: warning,
                   dateShare: total > 0 ? dated / total : 0,
                   samples: samples)
    }

    // MARK: - The lead time, which may not shrink

    /// Measured on the profiles above, with the estimate as it stands.
    ///
    /// All four were measured twice, once with the exit threshold set equal to
    /// the entry threshold — which is the rule as it was before hysteresis —
    /// and once as it ships. The four numbers came out the same both times, to
    /// the sample: 118.83, 48.33, 4.67, 114.15 hours. That is not a
    /// coincidence and not luck, it is `hysteresisOnlyEverAdds` below: the
    /// entry threshold did not move, so the moment a date first appears cannot
    /// move either.
    ///
    /// A new number here is only allowed to be larger. If a change makes one
    /// smaller, the change is wrong, not the number.
    struct LeadTime: Sendable, CustomStringConvertible {
        let name: String
        let exhaustsAt: Double
        let warning: Double
        var description: String { name }
    }

    static let leadTimes: [LeadTime] = [
        LeadTime(name: "steady, exhausts", exhaustsAt: 134.00, warning: 118.83),
        LeadTime(name: "accelerating, exhausts", exhaustsAt: 135.00, warning: 48.33),
        LeadTime(name: "quiet then a surge", exhaustsAt: 160.00, warning: 4.66),
        LeadTime(name: "bursty, exhausts", exhaustsAt: 126.98, warning: 114.15),
    ]

    @Test("The date arrives no later than it used to", arguments: leadTimes)
    func leadTimeIsNotLost(expected: LeadTime) throws {
        let profile = try #require(Self.profiles.first { $0.name == expected.name })
        let exhausted = try #require(profile.trace().exhaustedAt,
                                     "the fixture is wrong: \(expected.name) has to run out of quota")
        #expect(abs(exhausted - expected.exhaustsAt) < 0.05,
                "the fixture drifted: \(expected.name) now runs out at \(exhausted) h, not \(expected.exhaustsAt)")

        let run = try #require(Self.runs[expected.name])
        let warning = try #require(run.warningHours,
                                   "no date was ever shown on \(expected.name) — the warning is gone entirely")
        // Ten minutes is the sampling step; anything real moves by at least
        // that. The tolerance is a twentieth of it.
        #expect(warning >= expected.warning - 0.05,
                "\(expected.name): the date now appears \(warning) h before exhaustion, against \(expected.warning) h recorded")
    }

    /// The other side of the same trade. Steadiness bought by naming dates
    /// more eagerly is not steadiness, it is the false-date defect coming
    /// back, and that one was measured at 58.8 % of four real days before the
    /// horizon was fixed.
    ///
    /// Two of these did move when hysteresis went in, and upwards: a date the
    /// gate would have taken away is now held a little longer, so
    /// `decelerating` went from 10.06 % to 10.17 % and `steady, exhausts` from
    /// 92.27 % to 92.67 % of its week. That is the cost side of the trade,
    /// stated rather than rounded away. The ceiling below allows a percentage
    /// point of drift and no more.
    struct FalseDates: Sendable, CustomStringConvertible {
        let name: String
        let share: Double
        var description: String { name }
    }

    static let falseDateShares: [FalseDates] = [
        FalseDates(name: "steady, survives", share: 0.000),
        FalseDates(name: "weekdays only, survives", share: 0.095),
        FalseDates(name: "decelerating, survives", share: 0.102),
        FalseDates(name: "bursty, survives", share: 0.000),
    ]

    @Test("A week that survives is not told it will not", arguments: falseDateShares)
    func falseDatesDoNotGrow(expected: FalseDates) throws {
        let profile = try #require(Self.profiles.first { $0.name == expected.name })
        #expect(profile.trace().exhaustedAt == nil,
                "the fixture is wrong: \(expected.name) has to survive the week")

        let run = try #require(Self.runs[expected.name])
        #expect(run.dateShare <= expected.share + 0.01,
                "\(expected.name): a date is now shown \(run.dateShare * 100)% of the week, against \(expected.share * 100)% recorded")
    }

    // MARK: - What hysteresis is allowed to do

    /// The guarantee behind the lead times, stated so it cannot be argued
    /// about: hysteresis may keep a verdict on screen longer, and it may never
    /// keep one off. Whenever R² is at or above the entry threshold the gate
    /// admits a verdict, exactly as the single-threshold rule did.
    ///
    /// What this does and does not cover, since the difference matters. It
    /// covers the latch: no arrangement of the exit threshold, and no bug in
    /// the replay, can make the gate refuse something a single threshold at
    /// the same bar would have allowed. It does not cover the *value* of the
    /// entry bar — it is written against `minimumFitQuality`, so raising that
    /// constant moves this check along with it. The recorded lead times above
    /// are what guards the value, and they do: at an entry threshold of 0.80
    /// the surge week loses 4.67 hours of warning down to 3.83 and
    /// `leadTimeIsNotLost` fails on it. Checked by doing it.
    @Test("Hysteresis never withholds what one threshold would have shown")
    func hysteresisOnlyEverAdds() {
        for profile in Self.profiles {
            for forecast in (Self.runs[profile.name]?.samples ?? []) {
                guard let quality = forecast.fitQuality, quality >= Forecast.minimumFitQuality else { continue }
                #expect(forecast.gate.admitsAVerdict,
                        "\(profile.name): R² = \(quality) is above the entry threshold and the gate is \(forecast.gate.label)")
            }
        }
    }

    /// And the profiles have to reach the gate at all, or none of the above
    /// measures anything. A week whose R² never goes near 0.7 would pass every
    /// check here with the gate deleted.
    @Test("The profiles actually exercise the gate")
    func theGateIsReached() {
        var held = 0, open = 0, closed = 0
        for profile in Self.profiles {
            for forecast in (Self.runs[profile.name]?.samples ?? []) {
                switch forecast.gate {
                case .held: held += 1
                case .open: open += 1
                case .closed, .withdrawn: closed += 1
                }
            }
        }
        #expect(open > 0, "no profile ever opened the gate")
        #expect(closed > 0, "no profile was ever refused by the gate")
        #expect(held > 0, "no profile ever landed between the two thresholds, so hysteresis is untested here")
    }
}
