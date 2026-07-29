import SwiftUI
import WidgetKit

/// Раздел 9: шапка, три строки-полоски, подвал через разделитель.
struct MediumView: View {
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
                // Симметричные распорки: блок строк стоит по центру
                // свободного места, а не прижат к шапке.
                Spacer(minLength: 0)
                rows(snapshot)
                Spacer(minLength: 0)
                Divider()
                footer(snapshot)
            }
        }
    }

    /// Все три строки — израсходовано. «5-hour» вместо «Session»: слово
    /// «сессия» занято сессией Claude Code, к которой относятся контекст
    /// и стоимость, а пятичасовое окно принадлежит аккаунту целиком.
    private func rows(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 7) {
            GaugeRow(
                caption: "5-hour used",
                metric: entry.limitMetric(snapshot.limits.fiveHour),
                dimmed: entry.isDimmed
            )
            GaugeRow(
                caption: "Week used",
                metric: entry.limitMetric(snapshot.limits.sevenDay),
                dimmed: entry.isDimmed
            )
            GaugeRow(
                caption: "Context used",
                // Имя проекта стоит здесь: контекст принадлежит сессии.
                metric: entry.contextMetric.map {
                    GaugeMetric(
                        fraction: $0.fraction,
                        value: $0.value,
                        auxiliary: entry.projectName ?? $0.auxiliary,
                        level: $0.level
                    )
                },
                dimmed: entry.isDimmed
            )
        }
    }

    private func footer(_ snapshot: Snapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // «this session» относится ко всему подвалу: и деньги, и доля
            // кеша посессионные, а не общие для аккаунта. Без этой подписи
            // после переноса проекта из шапки они остались бы деньгами
            // непонятной принадлежности.
            HStack(spacing: 6) {
                Text("this session:")
                if let cost = snapshot.cost?.sessionUsd {
                    Text(verbatim: CCGaugeFormat.money(cost)).monospacedDigit()
                }
                if let ratio = snapshot.context?.cacheHitRatio {
                    Text("· cache \(CCGaugeFormat.ratio(ratio))").monospacedDigit()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            AgeCaption(entry: entry).layoutPriority(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
