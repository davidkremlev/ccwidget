import SwiftUI
import WidgetKit

/// Section 9: header, three bar rows, footer behind a divider.
struct MediumView: View {
    let entry: CCWidgetEntry

    /// So the drawn line and the spoken one share a locale.
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
            } else if let snapshot = entry.snapshot {
                // Symmetric spacers: the block of rows sits centred in the
                // free space instead of being pinned under the header.
                Spacer(minLength: 0)
                if snapshot.limitsAvailability == .absentAfterReply {
                    // The context row still means something, so it stays and
                    // the two windows are explained rather than dashed out.
                    MessageView.noLimits(compact: true)
                    GaugeRow(caption: "Context used",
                             reading: entry.contextReading.withAuxiliary(entry.projectName),
                             dimmed: entry.isDimmed)
                } else {
                    rows(snapshot)
                }
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
                reading: entry.limitReading(snapshot.limits.fiveHour),
                dimmed: entry.isDimmed,
                detail: entry.limitDetail(snapshot.limits.fiveHour, locale: locale),
                moment: entry.date
            )
            GaugeRow(
                caption: "Week used",
                reading: entry.limitReading(snapshot.limits.sevenDay),
                dimmed: entry.isDimmed,
                detail: entry.limitDetail(snapshot.limits.sevenDay, locale: locale),
                moment: entry.date
            )
            GaugeRow(
                caption: "Context used",
                // The project name lives here: the context belongs to a
                // session.
                reading: entry.contextReading.withAuxiliary(entry.projectName),
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

            CaptureCaption(entry: entry).layoutPriority(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
