import SwiftUI
import WidgetKit

/// Раздел 9: всё из среднего размера, но развёрнуто — у каждой полоски
/// своя подпись с моментом сброса, блок прогноза и расширенный подвал.
struct LargeView: View {
    let entry: CCGaugeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(entry: entry)

            if entry.snapshot == nil || entry.hidesNumbers {
                Spacer(minLength: 0)
                if entry.snapshot == nil {
                    MessageView.noData()
                } else {
                    MessageView.abandoned(entry: entry)
                }
                Spacer(minLength: 0)
            } else if let snapshot = entry.snapshot {
                Divider()
                rows(snapshot)
                if let forecast = entry.forecast, let week = snapshot.limits.sevenDay {
                    Divider()
                    ForecastBlock(forecast: forecast, window: week)
                }
                Divider()
                details(snapshot)
                Divider()
                footer
            }
        }
    }

    // MARK: Полоски

    private func rows(_ snapshot: Snapshot) -> some View {
        // Свободное место раздаётся между строками, а не копится одной дырой
        // над подвалом. Прогноз этапа 4 заберёт его обратно.
        VStack(alignment: .leading, spacing: 0) {
            DetailGaugeRow(
                caption: "5-hour used",
                metric: entry.limitMetric(snapshot.limits.fiveHour),
                detail: limitDetail(snapshot.limits.fiveHour),
                dimmed: entry.isDimmed
            )
            Spacer(minLength: 6)
            DetailGaugeRow(
                caption: "Week used",
                metric: entry.limitMetric(snapshot.limits.sevenDay),
                detail: limitDetail(snapshot.limits.sevenDay),
                dimmed: entry.isDimmed
            )
            Spacer(minLength: 6)
            DetailGaugeRow(
                caption: "Context used",
                // Имя проекта здесь: контекст принадлежит сессии,
                // а два окна выше — аккаунту целиком.
                metric: entry.contextMetric,
                detail: entry.projectName,
                dimmed: entry.isDimmed
            )
        }
    }

    private func limitDetail(_ window: LimitWindow?) -> String? {
        guard !entry.hidesNumbers, let window else { return nil }
        let left = CCGaugeFormat.percent(window.remainingPercentage)
        let moment = CCGaugeFormat.resetMoment(window.resetsAt)
        let until = CCGaugeFormat.countdown(window.timeUntilReset(at: entry.date))
        // Крупная цифра — расход; остаток остаётся здесь, подписанным словом,
        // чтобы полярность нельзя было спутать.
        return "\(left) left · resets \(moment) · \(until)"
    }

    // MARK: Подробности

    /// Раздел 9: подвал большого размера — стоимость, токены, доля кеша.
    /// Все три величины посессионные, поэтому блок подписан целиком.
    private func details(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 3) {
            // Имя проекта не повторяем: оно уже стоит у строки контекста,
            // здесь достаточно указать принадлежность сессии.
            HStack(spacing: 4) {
                Text("This session")
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            detailLine("Cost", snapshot.cost?.sessionUsd.map(CCGaugeFormat.money))
            detailLine("Tokens", tokensLine(snapshot.context))
            detailLine("Cache", snapshot.context?.cacheHitRatio.map(CCGaugeFormat.ratio))
        }
    }

    private func tokensLine(_ context: ContextInfo?) -> String? {
        guard let used = context?.totalInputTokens else { return nil }
        guard let size = context?.windowSize else { return CCGaugeFormat.tokensExact(used) }
        return "\(CCGaugeFormat.tokensExact(used)) / \(CCGaugeFormat.tokensExact(size))"
    }

    private func detailLine(_ caption: LocalizedStringKey, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(caption)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(value ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(2)
        }
        .font(.caption)
    }

    // MARK: Подвал

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let version = entry.snapshot?.claudeCodeVersion {
                Text("Claude Code \(version)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            AgeCaption(entry: entry).layoutPriority(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
