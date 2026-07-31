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
        snapshot.map { Freshness(age: $0.age(at: date)) }
    }
}

struct CCWidgetProvider: TimelineProvider {
    /// Timeline step and length from section 2.3: thirty entries a minute
    /// apart. The countdown ticks for half an hour without touching disk.
    static let step: TimeInterval = 60
    static let count = 30

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
        let base = Self.load(at: now)

        // One disk read per timeline. The entries differ only in their
        // moment; the snapshot inside them is the same one.
        let entries = (0..<Self.count).map { index in
            CCWidgetEntry(
                date: now.addingTimeInterval(Double(index) * Self.step),
                snapshot: base.snapshot,
                failure: base.failure,
                forecast: base.forecast
            )
        }

        // .after the last entry: the system comes back for more on its own.
        // The watcher reloads it early when the snapshot actually changes.
        let last = entries.last?.date ?? now
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
                forecast = Forecast.make(
                    history: HistoryStore(store: store).load(),
                    window: week,
                    now: date
                )
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
