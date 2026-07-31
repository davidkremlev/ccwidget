import AppKit
import Foundation
import SwiftUI
import Testing

/// Tier 1 of the rendering plan: does the text fit, measured rather than
/// rendered.
///
/// The defect class is one this project has already shipped twice — a caption
/// that fits in English and ends in an ellipsis somewhere else. German runs
/// about a third longer than English and the small tile is 158 points wide,
/// which is the whole problem in one sentence.
///
/// No images and no baselines. Every localized string is measured against the
/// width the layout can actually give it, in every language at once, and the
/// same numbers come out on macOS 14 and 26 because a few points of metric
/// drift are absorbed by the margin. A seventh language is covered the day it
/// is added, which is the property an image grid does not have.
@MainActor
@Suite("Text metrics")
struct TextMetricsTests {

    // MARK: The layout, as numbers

    /// Tile sizes are fixed by WidgetKit; the padding is ours, applied once in
    /// `CCWidgetBundle`.
    private static let padding: CGFloat = 14
    private static let smallTile: CGFloat = 158
    private static let mediumTile: CGFloat = 338

    private var smallContent: CGFloat { Self.smallTile - 2 * Self.padding }
    private var mediumContent: CGFloat { Self.mediumTile - 2 * Self.padding }

    /// A bar narrower than this conveys nothing: at 30 points a percentage
    /// point is a third of a pixel, and the row would be a number with a
    /// decoration beside it. It is the one number here that is a judgement
    /// rather than a measurement, which is why it is named and not inlined.
    private static let minimumBarWidth: CGFloat = 40

    /// `.lineLimit(1)` with `.minimumScaleFactor(0.8)` means a caption may
    /// shrink by a fifth before it truncates. Shrinking is graceful
    /// degradation; truncation is the defect. So the budget is what fits
    /// *after* the allowed shrink.
    private static let minimumScale: CGFloat = 0.8

    // MARK: Measuring

    private func font(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: style)
        guard let weight else { return base }
        return NSFont.systemFont(ofSize: base.pointSize, weight: weight)
    }

    private func width(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString)
            .size(withAttributes: [.font: font])
            .width
    }

    private func height(_ text: String, _ font: NSFont, wrappingAt limit: CGFloat) -> CGFloat {
        (text as NSString).boundingRect(
            with: CGSize(width: limit, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
    }

    // MARK: The strings under test

    /// Read from the catalogs in the repository rather than from a copy. A
    /// `.xcstrings` in a resources phase is compiled into `.lproj`, so the
    /// checks would be reading the build's output instead of the file a
    /// translator edits.
    private static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func catalog(_ path: String) throws -> [String: [String: String]] {
        let url = Self.repositoryRoot.appending(path: path)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = try #require((json as? [String: Any])?["strings"] as? [String: Any])

        var result: [String: [String: String]] = [:]
        for (key, entry) in strings {
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]
            // English is the source language and has no entry of its own
            // unless it needs plural forms; the key is the string.
            var byLanguage: [String: String] = ["en": key]
            for (language, value) in localizations {
                if let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any],
                   let text = unit["value"] as? String {
                    byLanguage[language] = text
                }
                // Plural variations are measured at their longest form: that
                // is the one that has to fit.
                if let variations = (value as? [String: Any])?["variations"] as? [String: Any],
                   let plural = variations["plural"] as? [String: Any] {
                    let forms = plural.values.compactMap {
                        (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                    }
                    if let longest = forms.max(by: { $0.count < $1.count }) {
                        byLanguage[language] = longest
                    }
                }
            }
            result[key] = byLanguage
        }
        return result
    }

    private func widgetStrings() throws -> [String: [String: String]] {
        try catalog("Widget/Resources/Localizable.xcstrings")
    }

    // MARK: The medium row

    /// What is left for the caption once everything fixed has taken its share.
    /// Derived by measuring, not by guessing: the glyph, the percentage and
    /// the countdown beside it are all rendered text whose width is a fact.
    private var mediumCaptionBudget: CGFloat {
        let spacing: CGFloat = 6 * 4             // glyph, caption, bar, value, auxiliary
        let glyph = width("􀁣", font(.caption2))  // a filled SF Symbol circle
        // The widest realistic pair: a three-digit percentage, and a countdown
        // in the language that spells its units out.
        let value = width("100 %", font(.caption1))
        let auxiliary = width("5 Tg., 22 Std.", font(.caption2))
        return mediumContent - spacing - glyph - Self.minimumBarWidth - value - auxiliary
    }

    /// The three row captions, in six languages, against the space a medium
    /// tile can give them.
    @Test("Every row caption fits the medium tile in every language")
    func rowCaptionsFitMedium() throws {
        let strings = try widgetStrings()
        let budget = mediumCaptionBudget
        #expect(budget > 40, "the derived budget is implausible: \(budget)")

        for key in ["5-hour used", "Week used", "Context used"] {
            let translations = try #require(strings[key], "\(key) is not in the catalog")
            for (language, text) in translations.sorted(by: { $0.key < $1.key }) {
                let shrunk = width(text, font(.caption1)) * Self.minimumScale
                #expect(shrunk <= budget,
                        "\(language) \"\(text)\" needs \(Int(shrunk)) pt of \(Int(budget)) available")
            }
        }
    }

    /// The negative control. Without it the budget is a number that has never
    /// said no to anything, and a check that cannot fail is decoration.
    @Test("A caption that is too long is rejected")
    func overlongCaptionIsRejected() {
        let absurd = String(repeating: "Verbrauchsanzeige ", count: 3)
        let shrunk = width(absurd, font(.caption1)) * Self.minimumScale
        #expect(shrunk > mediumCaptionBudget,
                "a 54-character caption fits the budget, so the budget is wrong")
    }

    // MARK: The small tile

    /// The header is the whole label of the tile: glyph plus one caption, and
    /// nothing else competing for the width.
    @Test("The small tile's header fits in every language")
    func smallHeaderFits() throws {
        let strings = try widgetStrings()
        let translations = try #require(strings["Week used"])
        let budget = smallContent - 5 - width("􀁣", font(.caption1))

        for (language, text) in translations.sorted(by: { $0.key < $1.key }) {
            let shrunk = width(text, font(.caption1, weight: .medium)) * Self.minimumScale
            #expect(shrunk <= budget,
                    "\(language) \"\(text)\" needs \(Int(shrunk)) pt of \(Int(budget)) available")
        }
    }

    /// The footer is the string that actually broke. It was capped at one line
    /// when English needs 22 characters and German 32, so German and Russian
    /// ended in an ellipsis; it now gets two lines. Two is the budget, and
    /// three would overflow the tile.
    @Test("The small tile's footer fits two lines in every language")
    func smallFooterFitsTwoLines() throws {
        let strings = try widgetStrings()
        let translations = try #require(strings["used · resets %@"])
        let caption2 = font(.caption2)
        let twoLines = caption2.boundingRectForFont.height * 2.2   // leading included

        for (language, template) in translations.sorted(by: { $0.key < $1.key }) {
            // The substitution is a weekday and a time — measured at a wide
            // realistic value rather than at the placeholder.
            let text = template.replacingOccurrences(of: "%@", with: "Mittwoch 07:00")
            let used = height(text, caption2, wrappingAt: smallContent)
            #expect(used <= twoLines,
                    "\(language) \"\(text)\" needs \(Int(used)) pt of \(Int(twoLines)) available")
        }
    }

    @Test("A footer that needs three lines is rejected")
    func overlongFooterIsRejected() {
        let caption2 = font(.caption2)
        let twoLines = caption2.boundingRectForFont.height * 2.2
        let absurd = "verbraucht · Zurücksetzung am Mittwoch um sieben Uhr morgens Ortszeit"
        #expect(height(absurd, caption2, wrappingAt: smallContent) > twoLines,
                "a three-line footer fits the budget, so the budget is wrong")
    }

    // MARK: Everything else the widget shows

    /// The rest of the widget's strings are less constrained — the large tile
    /// gives a caption its own line — but nothing stops a translation from
    /// being absurd, and an absurd one should be caught here rather than by
    /// somebody's screenshot.
    @Test("No widget string is wildly longer than its English source")
    func noStringIsAbsurdlyLong() throws {
        for (key, translations) in try widgetStrings() {
            let english = width(key, font(.caption1))
            guard english > 0 else { continue }

            for (language, text) in translations where language != "en" {
                let ratio = width(text, font(.caption1)) / english
                // German averages about a third longer; Japanese is shorter.
                // Three times is not a translation, it is an explanation.
                #expect(ratio < 3,
                        "\(language) \"\(text)\" is \(String(format: "%.1f", ratio))× the English \"\(key)\"")
            }
        }
    }
}
