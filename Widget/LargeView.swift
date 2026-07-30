import SwiftUI
import WidgetKit

/// Section 9: everything from the medium size, spelled out — every bar gets
/// its own caption with the reset moment, plus the estimate block and a wider
/// footer.
struct LargeView: View {
    let entry: CCWidgetEntry

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

    // MARK: Bars

    private func rows(_ snapshot: Snapshot) -> some View {
        // Free space is shared between the rows rather than pooling into one
        // hole above the footer.
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
                // The project name belongs here: the context is per-session,
                // while the two windows above are account-wide.
                metric: entry.contextMetric,
                detail: entry.projectName,
                dimmed: entry.isDimmed
            )
        }
    }

    private func limitDetail(_ window: LimitWindow?) -> String? {
        guard !entry.hidesNumbers, let window else { return nil }
        let moment = CCWidgetFormat.resetMoment(window.resetsAt)
        let until = CCWidgetFormat.countdown(window.timeUntilReset(at: entry.date))
        // No remaining figure here, deliberately. Section 8 forbids two
        // polarities in one column, and "35% left" under "Week used 65%" is
        // exactly that, one directly beneath the other: anyone checking
        // against the Usage panel grabbed the wrong number.
        return String(localized: "resets \(moment) · \(until)")
    }

    // MARK: Footer details

    /// Section 9: the large footer — cost, tokens, cache share. All three are
    /// per-session, so the block is labelled as a whole.
    private func details(_ snapshot: Snapshot) -> some View {
        VStack(spacing: 3) {
            // The project name is not repeated: it already sits by the
            // context row, and naming the session is enough here.
            HStack(spacing: 4) {
                Text("This session")
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            detailLine("Cost", snapshot.cost?.sessionUsd.map(CCWidgetFormat.money))
            detailLine("Tokens", tokensLine(snapshot.context))
            detailLine("Cache", snapshot.context?.cacheHitRatio.map(CCWidgetFormat.ratio))
        }
    }

    private func tokensLine(_ context: ContextInfo?) -> String? {
        guard let used = context?.totalInputTokens else { return nil }
        guard let size = context?.windowSize else { return CCWidgetFormat.tokensExact(used) }
        return "\(CCWidgetFormat.tokensExact(used)) / \(CCWidgetFormat.tokensExact(size))"
    }

    private func detailLine(_ caption: LocalizedStringKey, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(caption)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text(verbatim: value ?? "—")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(2)
        }
        .font(.caption)
    }

    // MARK: Footer

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
