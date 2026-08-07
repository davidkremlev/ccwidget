import SwiftUI
import WidgetKit

/// Section 9: everything from the medium size, spelled out — every bar gets
/// its own caption with the reset moment, plus the estimate block and a wider
/// footer.
struct LargeView: View {
    let entry: CCWidgetEntry

    /// Passed down to the rows so the drawn line and the spoken one format
    /// against the same locale.
    @Environment(\.locale) private var locale

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
            } else if let snapshot = entry.snapshot,
                      snapshot.limitsAvailability == .absentAfterReply {
                Divider()
                MessageView.noLimits()
                Divider()
                DetailGaugeRow(
                    caption: "Context used",
                    reading: entry.contextReading,
                    detail: entry.projectName.map(RowDetail.text) ?? .none,
                    dimmed: entry.isDimmed
                )
                Divider()
                details(snapshot)
                Divider()
                footer
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
                reading: entry.limitReading(snapshot.limits.fiveHour),
                detail: entry.limitDetail(snapshot.limits.fiveHour, locale: locale),
                dimmed: entry.isDimmed,
                moment: entry.date
            )
            Spacer(minLength: 6)
            DetailGaugeRow(
                caption: "Week used",
                reading: entry.limitReading(snapshot.limits.sevenDay),
                detail: entry.limitDetail(snapshot.limits.sevenDay, locale: locale),
                dimmed: entry.isDimmed,
                moment: entry.date
            )
            Spacer(minLength: 6)
            DetailGaugeRow(
                caption: "Context used",
                // The project name belongs here: the context is per-session,
                // while the two windows above are account-wide.
                reading: entry.contextReading,
                detail: entry.projectName.map(RowDetail.text) ?? .none,
                dimmed: entry.isDimmed
            )
        }
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
        // One item, not two. "Cost" and "$140.52" are separate announcements
        // otherwise, and the second means nothing on its own — the same
        // fragmentation already fixed in the app window's detail rows.
        .accessibilityElement(children: .combine)
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
            CaptureCaption(entry: entry).layoutPriority(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
