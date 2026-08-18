import WidgetKit
import Foundation

struct CCWidgetEntry: TimelineEntry {
    /// The moment this entry is computed for. Everything derived — the
    /// snapshot's age, the countdown to the reset — is measured from here
    /// rather than from `Date()`. Otherwise a pre-generated timeline would
    /// show the same clock in every entry.
    let date: Date
    let snapshot: Snapshot?
    let failure: String?
    /// Computed once per timeline along with the snapshot: section 2.3
    /// rules out extra trips to disk.
    var forecast: Forecast?

    var freshness: Freshness? {
        snapshot.map { Freshness(of: $0, at: date) }
    }
}

struct CCWidgetProvider: TimelineProvider {
    /// The closest two entries may sit, from Apple's guidance on keeping a
    /// widget up to date: entries should be "at least about 5 minutes apart".
    /// See `apple/widgetkit-keeping-up-to-date.md` in the reference store.
    ///
    /// This project used to place them a minute apart, thirty at a time, so
    /// that a computed countdown would tick. Nothing computes a countdown any
    /// more — SwiftUI's dynamic date does it while the extension sleeps — so
    /// entries are needed only where what is *drawn* actually changes.
    static let minimumSpacing: TimeInterval = 5 * 60

    /// How far ahead a timeline may reach, and how far apart its entries may
    /// sit. Both are upper bounds, and the project had neither.
    ///
    /// The minute grid did two jobs. It drove the countdown — which dynamic
    /// dates now do — and, as a side effect, it ran out after half an hour,
    /// which forced the system to come back and ask the provider for more.
    /// Placing entries only on thresholds kept the first job and silently
    /// dropped the second: measured on 7 August 2026, a real timeline reached
    /// **134.9 hours** ahead, so `.after(last)` meant the provider would not be
    /// asked again for five and a half days. Every entry in it carried the
    /// snapshot read when it was built, and the tile showed data two hours old
    /// while the window beside it was current.
    ///
    /// Reloads from the watcher were the only thing bridging that, and the
    /// watcher lives in the app's window — closed window, frozen tile.
    static let horizon: TimeInterval = 2 * 60 * 60
    static let maximumSpacing: TimeInterval = 30 * 60

    /// The moments the picture changes without new data — the two freshness
    /// thresholds and the moment each window closes — and `now`, which the
    /// tile needs something to draw from.
    ///
    /// **These are never dropped.** The paced grid below is thinned to keep
    /// entries about five minutes apart, as Apple asks; the thresholds are
    /// not, and that is a departure from the same guidance, made on purpose
    /// and recorded in section 2.4. Until 18 August 2026 they went through the
    /// same sieve as the grid, and a five-hour window that reset 2 min 29 s
    /// after a rebuild lost its entry: the tile stayed on the open row, and
    /// the system's relative date, past its moment, counted *up* — "8 мин
    /// 37 с" on the desktop, reading as time left, eight minutes after the
    /// window had closed. A rebuild happens whenever the snapshot changes,
    /// so a rebuild inside the last five minutes of a window is not a corner
    /// but the ordinary case. Two entries 2½ minutes apart, once, is not the
    /// density the five-minute rule is written against; a countdown that
    /// lies for up to half an hour is the thing it would cost to keep.
    ///
    /// Separate from `makeTimeline` because it is the half that can be
    /// checked: `makeTimeline` reads the store, and these are arithmetic.
    static func thresholdDates(from now: Date, snapshot: Snapshot?) -> [Date] {
        var moments: [Date] = [now]
        if let captured = snapshot?.capturedAt {
            // An hour old: the figures dim and gain the word "outdated".
            // A day old: the figures go away entirely.
            moments.append(captured.addingTimeInterval(60 * 60))
            moments.append(captured.addingTimeInterval(24 * 60 * 60))
        }
        for window in [snapshot?.limits.fiveHour, snapshot?.limits.sevenDay].compactMap({ $0 }) {
            // The row switches to "closed" here, and the countdown stops.
            moments.append(window.resetsAt)
        }
        // Only what is ahead and inside the horizon. A threshold beyond the
        // horizon is not lost — the timeline built two hours from now will
        // carry it, and by then it is closer. Deduplicated: two windows may
        // reset at the same instant, and one entry says both.
        let ceiling = now.addingTimeInterval(horizon)
        var kept: [Date] = []
        for moment in moments.sorted() where moment >= now && moment <= ceiling {
            if kept.last == moment { continue }
            kept.append(moment)
        }
        return kept
    }

    /// The whole schedule: the thresholds, and a paced grid around them.
    static func entryDates(from now: Date, snapshot: Snapshot?) -> [Date] {
        let thresholds = thresholdDates(from: now, snapshot: snapshot)

        // A paced series out to the horizon. Its only purpose is to end: the
        // last entry is what the reload policy points at, and a timeline that
        // ends in two hours is a promise that the provider is asked again in
        // two hours, whatever the watcher is doing.
        //
        // The grid is what the five-minute rule thins: a grid point that
        // lands within the minimum of a threshold — or of an earlier grid
        // point — is dropped, because the system is entitled to ignore
        // entries it considers too dense, and an ignored entry is a moment
        // that arrives late. The thresholds themselves are kept whatever the
        // grid does; see `thresholdDates`.
        var kept = thresholds
        var step = now.addingTimeInterval(maximumSpacing)
        while step <= now.addingTimeInterval(horizon) {
            let crowded = kept.contains { abs($0.timeIntervalSince(step)) < minimumSpacing }
            if !crowded { kept.append(step) }
            step = step.addingTimeInterval(maximumSpacing)
        }
        kept.sort()

        // Thinning can open a gap wider than the maximum: a threshold accepted
        // just before a grid point pushes the next one past it. Fill those back
        // in — evenly, not by stepping the maximum off the left edge, which
        // leaves a sliver against the right one and breaks the lower bound
        // instead. Both bounds have to hold on what is actually returned.
        var paced: [Date] = []
        for moment in kept {
            if let last = paced.last {
                let gap = moment.timeIntervalSince(last)
                if gap > maximumSpacing {
                    let pieces = Int((gap / maximumSpacing).rounded(.up))
                    let step = gap / Double(pieces)
                    for piece in 1..<pieces {
                        paced.append(last.addingTimeInterval(step * Double(piece)))
                    }
                }
            }
            paced.append(moment)
        }
        return paced.isEmpty ? [now] : paced
    }

    func placeholder(in context: Context) -> CCWidgetEntry {
        CCWidgetEntry(date: Date(), snapshot: .preview, failure: nil, forecast: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CCWidgetEntry) -> Void) {
        if context.isPreview {
            completion(CCWidgetEntry(date: Date(), snapshot: .preview, failure: nil, forecast: nil))
        } else {
            completion(Self.load(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CCWidgetEntry>) -> Void) {
        completion(makeTimeline(now: Date()))
    }

    /// Kept separate from `getTimeline` because `TimelineProviderContext`
    /// cannot be constructed from outside — without this the timeline could
    /// not be checked at all.
    func makeTimeline(now: Date) -> Timeline<CCWidgetEntry> {
        // One disk read, then the moments are derived from what it holds: the
        // thresholds belong to this snapshot, not to the clock.
        let base = Self.load(at: now)
        let dates = Self.entryDates(from: now, snapshot: base.snapshot)

        // One disk read per timeline. The entries differ only in their
        // moment; the snapshot inside them is the same one.
        let entries = dates.map { date in
            CCWidgetEntry(
                date: date,
                snapshot: base.snapshot,
                failure: base.failure,
                forecast: base.forecast
            )
        }

        // .after the last entry: the system comes back for more on its own.
        // The watcher reloads it early when the snapshot actually changes.
        //
        // With entries now sitting on thresholds rather than on a minute grid,
        // the last one can be a day out — which is correct. Nothing on the tile
        // changes in between except the countdown, and the countdown is the
        // system's to redraw.
        let last = entries.last?.date ?? now
        // At `.notice`, not `.info`: the info ring buffer is gone within
        // minutes, and whether a reset had its entry is a question asked an
        // hour later, from the desktop. Offsets from now, in seconds — the
        // schedule identifies nobody.
        let thresholds = Self.thresholdDates(from: now, snapshot: base.snapshot)
        ccwidgetWidgetLog.notice(
            "timeline scheduled: \(entries.count, privacy: .public) entries, reach \(Int(last.timeIntervalSince(now)), privacy: .public)s, thresholds at \(thresholds.map { Int($0.timeIntervalSince(now)) }.description, privacy: .public)s"
        )
        return Timeline(entries: entries, policy: .after(last))
    }

    private static func load(at date: Date) -> CCWidgetEntry {
        do {
            let store = SnapshotStore.default()
            let snapshot = try store.load()
            ccwidgetWidgetLog.info(
                """
                timeline built from snapshot aged \(Int(snapshot.age(at: date)), privacy: .public)s; \
                week=\(snapshot.limits.sevenDay?.usedPercentage.description ?? "nil", privacy: .private)% used; \
                fiveHour=\(snapshot.limits.fiveHour?.usedPercentage.description ?? "nil", privacy: .private)% used; \
                context=\(snapshot.context?.usedPercentage?.description ?? "nil", privacy: .private)% used; \
                issues=\(snapshot.diagnostics.count, privacy: .public)
                """
            )
            var forecast: Forecast?
            if let week = snapshot.limits.sevenDay {
                let made = Forecast.make(
                    history: HistoryStore(store: store).load(),
                    window: week,
                    now: date
                )
                // The gate has hysteresis, so a verdict on screen can be
                // standing on a current reading or only on the fact that it
                // was already there. Those look identical from outside, and a
                // difference nobody can see is one nobody can debug.
                ccwidgetWidgetLog.info(
                    """
                    estimate: \(made.outcome.label, privacy: .public), \
                    gate \(made.gate.label, privacy: .public); \
                    R²=\(made.fitQuality.map { String(format: "%.3f", $0) } ?? "nil", privacy: .private); \
                    base=\(Int(made.observationSpan / 3600), privacy: .private)h, \
                    reach=\(Int(made.effectiveSpan / 3600), privacy: .private)h, \
                    points=\(made.points.count, privacy: .public)
                    """
                )
                forecast = made
            }
            return CCWidgetEntry(date: date, snapshot: snapshot, failure: nil, forecast: forecast)
        } catch let error as SnapshotStoreError {
            let access = SnapshotStore.default().describeAccess()
            ccwidgetWidgetLog.error(
                "snapshot unavailable: \(error.description, privacy: .private) | \(access, privacy: .private)"
            )
            return CCWidgetEntry(date: date, snapshot: nil, failure: error.description, forecast: nil)
        } catch {
            ccwidgetWidgetLog.error("snapshot unavailable: \(error.localizedDescription, privacy: .private)")
            return CCWidgetEntry(date: date, snapshot: nil, failure: "\(error)", forecast: nil)
        }
    }
}

extension Snapshot {
    /// Data for the widget gallery and previews. It does not pretend to be
    /// live.
    static let preview = Snapshot(
        schemaVersion: 1,
        capturedAt: Date(),
        sessionId: nil,
        claudeCodeVersion: "2.1.220",
        model: ModelInfo(id: nil, displayName: "Opus 5 (1M context)", effort: "high"),
        project: ProjectInfo(name: "ccwidget"),
        limits: Limits(
            fiveHour: LimitWindow(usedPercentage: 21, resetsAt: Date().addingTimeInterval(2 * 3600)),
            sevenDay: LimitWindow(usedPercentage: 62, resetsAt: Date().addingTimeInterval(19 * 3600))
        ),
        context: ContextInfo(
            usedPercentage: 6,
            totalInputTokens: 62777,
            windowSize: 1_000_000,
            cacheHitRatio: 0.9943
        ),
        cost: CostInfo(sessionUsd: 1.13)
    )
}
