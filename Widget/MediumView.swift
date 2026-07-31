import SwiftUI
import WidgetKit

/// Section 9: header, three bar rows, footer behind a divider.
struct MediumView: View {
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
                // Symmetric spacers: the block of rows sits centred in the
                // free space instead of being pinned under the header.
                Spacer(minLength: 0)
                rows(snapshot)
                Spacer(minLength: 0)
                Divider()
                footer(snapshot)
            }
        }
    }

    /// All three rows show consumption. "5-hour" rather than "Session": the
    /// word session already belongs to the Claude Code session, which is what
    /// the context and the cost describe, while the five-hour window belongs
    /// to the account as a whole.
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
                // The project name lives here: the context belongs to a
                // session.
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

    /// What the footer says, as one sentence.
    private func spokenFooter(_ snapshot: Snapshot) -> String {
        var parts = [String(localized: "this session:")]
        if let cost = snapshot.cost?.sessionUsd {
            parts.append(CCWidgetFormat.money(cost))
        }
        if let ratio = snapshot.context?.cacheHitRatio {
            parts.append(String(localized: "cache \(CCWidgetFormat.ratio(ratio))"))
        }
        return parts.joined(separator: " ")
    }

    private func footer(_ snapshot: Snapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // "this session" governs the whole footer: both the money and
            // the cache share are per-session, not account-wide. Once the
            // project name left the header, without this label the money
            // would have belonged to nobody in particular.
            HStack(spacing: 6) {
                Text("this session:")
                if let cost = snapshot.cost?.sessionUsd {
                    Text(verbatim: CCWidgetFormat.money(cost)).monospacedDigit()
                }
                if let ratio = snapshot.context?.cacheHitRatio {
                    Text("· cache \(CCWidgetFormat.ratio(ratio))").monospacedDigit()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            // One sentence rather than three fragments. Left apart, VoiceOver
            // read "this session:", then a sum, then "· cache 100 %" — with
            // the bullet, which is a separator for the eye and noise for the
            // ear.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenFooter(snapshot))

            Spacer(minLength: 4)

            AgeCaption(entry: entry).layoutPriority(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
