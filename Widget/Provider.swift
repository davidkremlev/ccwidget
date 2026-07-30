import WidgetKit
import Foundation

struct CCWidgetEntry: TimelineEntry {
    /// Момент, на который рассчитана запись. Все производные величины —
    /// возраст снимка, обратный отсчёт до сброса — считаются от него,
    /// а не от `Date()`. Иначе таймлайн из предгенерированных записей
    /// показывал бы одно и то же время.
    let date: Date
    let snapshot: Snapshot?
    let failure: String?
    /// Считается один раз на весь таймлайн вместе со снимком:
    /// раздел 2.3 запрещает лишние обращения к диску.
    var forecast: Forecast?

    var freshness: Freshness? {
        snapshot.map { Freshness(age: $0.age(at: date)) }
    }
}

struct CCWidgetProvider: TimelineProvider {
    /// Шаг и длина таймлайна из раздела 2.3: тридцать записей по минуте.
    /// Обратный отсчёт тикает полчаса без единого обращения к диску.
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

    /// Отдельно от `getTimeline`, потому что `TimelineProviderContext`
    /// снаружи не создаётся — иначе таймлайн нечем проверить.
    func makeTimeline(now: Date) -> Timeline<CCWidgetEntry> {
        let base = Self.load(at: now)

        // Одно чтение диска на весь таймлайн. Записи отличаются только
        // моментом, снимок во всех один и тот же.
        let entries = (0..<Self.count).map { index in
            CCWidgetEntry(
                date: now.addingTimeInterval(Double(index) * Self.step),
                snapshot: base.snapshot,
                failure: base.failure,
                forecast: base.forecast
            )
        }

        // .after последней записи: система сама придёт за новой порцией.
        // Досрочно таймлайн перезагрузит демон при изменении снимка.
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
                week=\(snapshot.limits.sevenDay?.remainingPercentage.description ?? "nil", privacy: .private)% left; \
                session=\(snapshot.limits.fiveHour?.remainingPercentage.description ?? "nil", privacy: .private)% left; \
                context=\(snapshot.context?.usedPercentage?.description ?? "nil", privacy: .private)%; \
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
    /// Данные для галереи виджетов и превью. Живыми не притворяются.
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
