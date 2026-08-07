import AppKit
import Foundation
import SwiftUI
import Testing

/// The render tier's half of the countdown check.
///
/// Tier 1 measures strings, and the countdown is no longer a string: it is a
/// `Text(date, style: .relative)` that the system formats while the extension
/// sleeps. The code never sees the characters, so `TextMetricsTests` cannot
/// weigh them — the trap that caught two truncated German captions went blind
/// on exactly the line most likely to overflow.
///
/// This is what replaces it. Instead of measuring a string, it renders the real
/// view and measures the picture: `ImageRenderer` at scale 1 produces an image
/// as wide as the laid-out text, so the width is a fact again, just an
/// expensive one.
///
/// **What it cannot pin down.** The dynamic styles read the system clock and
/// ignore any date the surrounding view was stamped with — measured, see
/// section 2.3. So the intervals below are built from `Date()` and the exact
/// wording depends on when the check runs: "22 ч 59 мин" a moment before the
/// hour, "23 ч" a moment after. That is why every interval is offset a little
/// past a round value, and why the assertion is about fitting rather than
/// about equality.
@MainActor
@Suite("Dynamic countdown width")
struct DynamicDateWidthTests {

    /// The same geometry tier 1 uses. Section 9: measured on macOS 26.6, not
    /// taken from a table.
    private static let mediumTile: CGFloat = 344
    private static let padding: CGFloat = 14
    private static let minimumScale: CGFloat = 0.8

    private var mediumContent: CGFloat { Self.mediumTile - 2 * Self.padding }

    private static let languages = ["de", "en", "es", "ja", "ru", "zh-Hans"]

    /// Intervals a real reset can be away, deliberately off round values so the
    /// formatter has to print two units rather than one.
    ///
    /// The five-hour window gives the short end, the weekly one the long end —
    /// and the long end is where German spells out "Tg." and "Std." together.
    private static let intervals: [TimeInterval] = [
        45,                        // under a minute
        38 * 60 + 12,              // tens of minutes
        3 * 3600 + 38 * 60,        // a few hours
        22 * 3600 + 59 * 60,       // most of a day
        5 * 86_400 + 22 * 3600,    // most of a week — the widest case
        6 * 86_400 + 23 * 3600,
    ]

    private func renderedWidth(_ view: some View) -> CGFloat {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return .infinity }
        return CGFloat(image.width)
    }

    /// The whole line as the tile draws it: "resets Fri 11:50 · 3 h 38 min",
    /// where the second half is the live one.
    @Test("The countdown line fits the medium tile in every language")
    func countdownLineFits() {
        // What is left for the line once the glyph, the caption and the
        // percentage have taken their share. Derived the same way tier 1
        // derives it, from the same tile.
        let budget = mediumContent * 0.55

        for language in Self.languages {
            let locale = Locale(identifier: language)
            for interval in Self.intervals {
                let resets = Date().addingTimeInterval(interval)
                let detail = RowDetail.reset(
                    moment: CCWidgetFormat.resetMoment(resets, locale: locale),
                    at: resets)
                let width = renderedWidth(
                    DetailLine(detail: detail).environment(\.locale, locale))
                let shrunk = width * Self.minimumScale

                #expect(shrunk <= budget,
                        "\(language), \(Int(interval)) s out: the line needs \(Int(shrunk)) pt of \(Int(budget)) available")
            }
        }
    }

    /// A closed window puts a word where the countdown was, and that word is
    /// still a string — so this half could live in tier 1. It is here so that
    /// both halves of the same line are weighed by the same instrument on the
    /// same tile.
    @Test("The closed-window line fits the medium tile in every language")
    func closedLineFits() {
        let budget = mediumContent * 0.55

        for language in Self.languages {
            let locale = Locale(identifier: language)
            let ended = Date().addingTimeInterval(-3600)
            let detail = RowDetail.closed(
                moment: CCWidgetFormat.resetMoment(ended, locale: locale))
            let width = renderedWidth(DetailLine(detail: detail).environment(\.locale, locale))
            let shrunk = width * Self.minimumScale

            #expect(shrunk <= budget,
                    "\(language): the closed line needs \(Int(shrunk)) pt of \(Int(budget))")
        }
    }

    /// A render that produces nothing would pass every assertion above by
    /// measuring zero. This is the guard against that: the same instrument, on
    /// a line that certainly has content.
    @Test("The instrument actually renders something")
    func rendererProducesPixels() {
        let resets = Date().addingTimeInterval(3 * 3600)
        let detail = RowDetail.reset(moment: CCWidgetFormat.resetMoment(resets), at: resets)
        let width = renderedWidth(DetailLine(detail: detail))
        #expect(width > 20 && width.isFinite, "rendered width \(width) is not a measurement")
    }
}
