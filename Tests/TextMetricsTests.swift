import AppKit
import Foundation
import SwiftUI
import Testing

/// Tier 1 of the rendering plan: does the text fit, measured rather than
/// rendered.
///
/// The defect class is one this project has already shipped twice — a caption
/// that fits in English and ends in an ellipsis somewhere else. German runs
/// about a third longer than English and the small tile is 164 points wide,
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
    ///
    /// The widths are measured, not quoted. Apple publishes no widget size
    /// table for macOS, and the numbers that stood here until now — 158 and
    /// 338 — came from the iOS table for a 393-point phone. Real values from
    /// `TimelineProviderContext.displaySize` on macOS 26.6, section 9 of
    /// `SPEC.md`: 164×164 and 344×164.
    private static let padding: CGFloat = 14
    private static let smallTile: CGFloat = 164
    private static let mediumTile: CGFloat = 344
    /// 344×344 — the large tile is as wide as the medium one and only taller,
    /// which is why the panel message has room for three lines and the row
    /// captions gain nothing from the extra size.
    private static let largeTile: CGFloat = 344

    private var smallContent: CGFloat { Self.smallTile - 2 * Self.padding }
    private var mediumContent: CGFloat { Self.mediumTile - 2 * Self.padding }
    private var largeContent: CGFloat { Self.largeTile - 2 * Self.padding }

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

    private func windowStrings() throws -> [String: [String: String]] {
        try catalog("App/Resources/Localizable.xcstrings")
    }

    /// The languages the app ships in, in a fixed order so a failure names the
    /// same one twice running.
    private static let languages = ["de", "en", "es", "ja", "ru", "zh-Hans"]

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

    /// The word a closed window puts where the countdown was. It shares the
    /// slot with the countdown, so it is measured against the same budget —
    /// and it is why the wording is one word: "window closed" needs 82 pt in
    /// Russian and 81 in German against a slot of 66, while "сброшено" needs
    /// 52 and "beendet" 41. Two words do not fit in Russian either way:
    /// "период истёк" needs 69.
    @Test("The closed-window word fits where the countdown sat")
    func closedWordFitsTheAuxiliarySlot() throws {
        let strings = try widgetStrings()
        let translations = try #require(strings["closed"], "\"closed\" is not in the catalog")
        // The slot is what the widest realistic countdown occupies.
        let budget = width("5 Tg., 22 Std.", font(.caption2))

        for (language, text) in translations.sorted(by: { $0.key < $1.key }) {
            let needed = width(text, font(.caption2)) * Self.minimumScale
            #expect(needed <= budget,
                    "\(language) \"\(text)\" needs \(Int(needed)) pt of \(Int(budget)) available")
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

    // MARK: The message panels

    /// Every panel that replaces the digits — no data, stale data, no limits —
    /// is built from the same two strings, and until now neither was measured
    /// anywhere. The panels are the surface a person meets when the widget has
    /// nothing to show, which is exactly when a truncated sentence costs the
    /// most: the tile has stopped explaining itself and the explanation is the
    /// only content left on it.
    ///
    /// The two roles are measured separately because they appear on different
    /// tiles. The title shows everywhere, so it is measured against the
    /// narrowest tile that shows it; the message is dropped on the small and
    /// medium tiles (`compact`), so it is measured against the large one, the
    /// only place it is drawn.
    private var panelTitleBudget: CGFloat {
        get throws {
            // The panel's glyph, at the size the panel asks for. Measured from
            // the symbol rather than from a private-use code point, so the
            // number follows the symbol if the symbol is ever changed.
            let configuration = NSImage.SymbolConfiguration(textStyle: .caption1)
            let symbol = try #require(
                NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)?
                    .withSymbolConfiguration(configuration),
                "exclamationmark.circle is missing from the system symbol set"
            )
            return smallContent - 5 - symbol.size.width   // HStack(spacing: 5)
        }
    }

    @Test("Every panel title fits the small tile in every language")
    func panelTitlesFitSmall() throws {
        let strings = try widgetStrings()
        let budget = try panelTitleBudget
        #expect(budget > 40, "the derived budget is implausible: \(budget)")

        for key in ["Limits have not arrived", "No data yet", "Data is stale"] {
            let translations = try #require(strings[key], "\(key) is not in the catalog")
            for (language, text) in translations.sorted(by: { $0.key < $1.key }) {
                let shrunk = width(text, font(.caption1, weight: .medium)) * Self.minimumScale
                #expect(shrunk <= budget,
                        "\(language) \"\(text)\" needs \(Int(shrunk)) pt of \(Int(budget)) available")
            }
        }
    }

    @Test("A panel title that is too long is rejected")
    func overlongPanelTitleIsRejected() throws {
        let absurd = "Die Nutzungsgrenzen sind noch nicht eingetroffen"
        let shrunk = width(absurd, font(.caption1, weight: .medium)) * Self.minimumScale
        // Read before the expectation, not inside it. `#expect` puts its
        // expression in a non-throwing autoclosure, and Swift 6.0 refuses a
        // throwing property access there — Swift 6.2 allows it, which is why
        // this compiled here and not on the oldest toolchain we support.
        let budget = try panelTitleBudget
        #expect(shrunk > budget,
                "a 47-character title fits the budget, so the budget is wrong")
    }

    /// Measured at the full point size, not at the shrunk one: the panel's
    /// message carries `.lineLimit(3)` before `.minimumScaleFactor`, so SwiftUI
    /// wraps at full size first and only shrinks if three lines are not enough.
    /// Measuring the shrunk text would report the state after the fallback and
    /// call a sentence comfortable when it is in fact already degraded — today
    /// German needs two lines of the three, and at 0.8 it would look like one.
    @Test("Every panel message fits three lines of the large tile in every language")
    func panelMessagesFitLarge() throws {
        let strings = try widgetStrings()
        let caption2 = font(.caption2)
        let threeLines = NSLayoutManager().defaultLineHeight(for: caption2) * 3

        for key in [
            "Claude Code sends them to Pro and Max accounts, after the first reply.",
            "Launch Claude Code in the terminal and send a message.",
            "Launch Claude Code in the terminal to refresh.",
        ] {
            let translations = try #require(strings[key], "\(key) is not in the catalog")
            for (language, text) in translations.sorted(by: { $0.key < $1.key }) {
                let used = height(text, caption2, wrappingAt: largeContent)
                #expect(used <= threeLines,
                        "\(language) \"\(text)\" needs \(Int(used)) pt of \(Int(threeLines)) available")
            }
        }
    }

    @Test("A panel message that needs four lines is rejected")
    func overlongPanelMessageIsRejected() {
        let caption2 = font(.caption2)
        let threeLines = NSLayoutManager().defaultLineHeight(for: caption2) * 3
        let absurd = String(
            repeating: "Claude Code sendet die Nutzungsgrenzen an Pro- und Max-Konten. ",
            count: 3
        )
        #expect(height(absurd, caption2, wrappingAt: largeContent) > threeLines,
                "a four-line message fits the budget, so the budget is wrong")
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

    // MARK: The window

    /// Tier 1 stopped at the widget, and the window's catalog was measured by
    /// nobody. That is not a small omission: a clipped caption is the defect
    /// class this project has shipped twice, and both times it was found by
    /// somebody looking at a screenshot rather than by a check.
    ///
    /// Not everything in the window can clip. The explanations that stand in
    /// place of the bars carry `.fixedSize(horizontal: false, vertical: true)`
    /// — they wrap and the window grows downwards, so their width is not a
    /// budget and measuring them would be asserting a constraint the layout
    /// does not have. Two things are bounded, and both are measured below.
    private static let windowWidth: CGFloat = 340
    private static let windowPadding: CGFloat = 20
    private var windowContent: CGFloat { Self.windowWidth - 2 * Self.windowPadding }

    /// The header is the app's name, a gap of at least eight points, and the
    /// badge inside a capsule with its own horizontal padding. All of it on
    /// one line, in three hundred points.
    ///
    /// **The property is that the header renders whole, not that the badge
    /// fits.** The first version of this asked the second question — it
    /// measured the badge against what was left after the title, and allowed
    /// the badge the fifth of shrink that `minimumScaleFactor` permits. Every
    /// translation passed, and the live window showed "Usage Widget for Claude
    /// C…" beside the widest badge of the four.
    ///
    /// The mistake was assuming the shrink lands on the badge. Permission to
    /// scale is not an instruction: the layout decides which view gets less
    /// than it asked for, and it took the deficit out of the title. The header
    /// now says which one gives way — `layoutPriority` on the badge — so the
    /// allowance below is modelled on an instruction in the code rather than
    /// on a guess about how the deficit gets shared.
    ///
    /// Read it as the sum it is: the title at its smallest, the badge at full
    /// size, and everything fixed between them. If that does not fit, the
    /// title is past its shrink and into truncation, which is the defect.
    private func headerWidth(badge: String, titleScale: CGFloat) -> CGFloat {
        let title = width("Usage Widget for Claude Code", font(.headline)) * titleScale
        let gap: CGFloat = 8            // Spacer(minLength: 8)
        let capsule: CGFloat = 8 * 2    // .padding(.horizontal, 8)
        return title + gap + capsule + width(badge, font(.caption1, weight: .medium))
    }

    /// Four badge states, six languages, twenty-four headers.
    @Test("The whole window header fits on one line in every language")
    func theHeaderRendersWhole() throws {
        let strings = try windowStrings()

        for key in ["Working", "Waiting", "Setup needed", "Check needed"] {
            let translations = try #require(strings[key], "\(key) is not in the catalog")
            for (language, text) in translations.sorted(by: { $0.key < $1.key }) {
                let needed = headerWidth(badge: text, titleScale: Self.minimumScale)
                #expect(needed <= windowContent,
                        "\(language) \"\(text)\": the header needs \(Int(needed)) pt of \(Int(windowContent)) even with the title at its smallest")
            }
        }
    }

    /// How much of the shrink the worst case actually spends. A budget met by
    /// a hair is one that the next translation breaks, and the number belongs
    /// in the record rather than in somebody's head.
    @Test("The widest badge does not spend the whole shrink")
    func theWidestBadgeLeavesRoom() throws {
        let strings = try windowStrings()
        var worst: (badge: String, needed: CGFloat) = ("", 0)
        for key in ["Working", "Waiting", "Setup needed", "Check needed"] {
            for (_, text) in try #require(strings[key]) {
                let needed = headerWidth(badge: text, titleScale: 1)
                if needed > worst.needed { worst = (text, needed) }
            }
        }
        // At full size the worst header overflows — that is the defect this
        // was written for, and it has to stay true or the check is measuring
        // a case that no longer exists.
        #expect(worst.needed > windowContent,
                "\"\(worst.badge)\" fits at full size now, so the shrink is no longer what saves the header")

        let shrunk = headerWidth(badge: worst.badge, titleScale: Self.minimumScale)
        #expect(shrunk <= windowContent - 20,
                "\"\(worst.badge)\" leaves only \(Int(windowContent - shrunk)) pt of slack; a longer translation breaks the header")
    }

    /// The negative control. Without it the width is a number that has never
    /// said no to anything.
    @Test("A badge that leaves the title no room is rejected")
    func overlongBadgeIsRejected() {
        #expect(headerWidth(badge: "Einrichtung wird benötigt", titleScale: Self.minimumScale)
                    > windowContent,
                "a 25-character badge fits even with the title shrunk, so the arithmetic is wrong")
    }

    /// The quiet line under the bars: when the week resets and when the
    /// snapshot was taken, on one line, with a fifth of shrink allowed before
    /// it truncates. Both halves are substituted with what they actually
    /// produce rather than with a guess, in the language being measured.
    ///
    /// The second half used to be a relative age, whose wording varied by
    /// language and by magnitude — hence the search for the widest one below.
    /// A capture moment has one shape, so the widest case is simply the one
    /// the formatter gives.
    @Test("The quiet line fits the window in every language")
    func quietLineFitsTheWindow() throws {
        let strings = try windowStrings()
        let key = "Week resets %@ · updated at %@"
        let translations = try #require(strings[key], "\(key) is not in the catalog")

        // A Wednesday at 03:00, and the widest age the line can hold: the
        // formatter's wording is longest in the minutes and hours range.
        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 5
        components.hour = 3; components.minute = 0
        let reset = Calendar(identifier: .gregorian).date(from: components)!
        // 23:59 rather than a round hour: the widest a captured moment gets in
        // a 24-hour locale, and "11:59 PM" in a 12-hour one.
        var capturedComponents = components
        capturedComponents.hour = 23; capturedComponents.minute = 59
        let captured = Calendar(identifier: .gregorian).date(from: capturedComponents)!

        for (language, template) in translations.sorted(by: { $0.key < $1.key }) {
            let locale = Locale(identifier: language)
            let moment = CCWidgetFormat.resetMoment(reset, locale: locale)
            let widest = CCWidgetFormat.capturedMoment(captured, locale: locale)

            let line = template
                .replacingOccurrences(of: "%@", with: moment, range: template.range(of: "%@"))
                .replacingOccurrences(of: "%@", with: widest)
            let shrunk = width(line, font(.caption1)) * Self.minimumScale
            #expect(shrunk <= windowContent,
                    "\(language) \"\(line)\" needs \(Int(shrunk)) pt of \(Int(windowContent)) available")
        }
    }

    // MARK: The setup screen

    /// The setup screen is 460 points wide with 24 of padding either side, and
    /// its paragraphs wrap. The one row that cannot wrap is the buttons: two
    /// of them side by side, each as wide as its title needs.
    ///
    /// Same defect class as the window header, which is why it is measured
    /// rather than trusted — that one passed a check that asked the wrong
    /// question and was cut off on screen anyway.
    @Test("Both buttons of a setup step fit on one row in every language")
    func setupButtonsFitTheRow() throws {
        let content: CGFloat = 460 - 2 * 24
        let spacing: CGFloat = 8          // the HStack's default
        let chrome: CGFloat = 12 * 2      // a push button's own padding, each side
        // The first step pairs a `Link` with a `Button`, and a link has no
        // capsule of its own — counting one for it overstates that row by 24
        // pt. Overstating is the safe direction here, and the row it affects
        // is the roomiest of the four.
        //
        // Measured when this was written, worst first: es "Configurar
        // automáticamente + Ver instrucciones manuales" 395 pt of 412, de 354,
        // ru 348, en 334, zh-Hans 184. Seventeen points is what the widest
        // translation has left, so the next one to be reworded is worth
        // measuring rather than eyeballing.

        let strings = try windowStrings()

        // Which buttons stand side by side is the step's business; how wide
        // they are is the translation's. The first comes from the script, the
        // second from the catalog on disk — `String(localized:)` does not
        // translate inside the test bundle, which is what
        // `theCatalogIsAbsentFromTheTestBundle` pins down. A first version of
        // this measured the script's own strings and reported the same 77 pt
        // of headroom in all six languages, which is what a check that has
        // stopped looking at anything looks like.
        for step in [OnboardingStep.checkClaudeCode, .install] {
            for containerExists in [true, false] {
                let keys = step.script(claudeCodeIsPresent: false,
                                       widgetContainerExists: containerExists).actions
                guard keys.count > 1 else { continue }
                for language in Self.languages {
                    let titles = try keys.map { key -> String in
                        if language == "en" { return key }
                        let translations = try #require(strings[key],
                                                        "\(key) is not in the catalog")
                        return try #require(translations[language],
                                            "\(key) has no \(language)")
                    }
                    let needed = titles.reduce(0.0) { $0 + width($1, font(.body)) + chrome }
                        + spacing * CGFloat(titles.count - 1)
                    #expect(needed <= content,
                            "\(language) \"\(titles.joined(separator: " + "))\" needs \(Int(needed)) pt of \(Int(content))")
                }
            }
        }
    }

    /// The same absurdity guard the widget's strings have, over the window's.
    @Test("No window string is wildly longer than its English source")
    func noWindowStringIsAbsurdlyLong() throws {
        for (key, translations) in try windowStrings() {
            let english = width(key, font(.caption1))
            guard english > 0 else { continue }
            for (language, text) in translations where language != "en" {
                let ratio = width(text, font(.caption1)) / english
                #expect(ratio < 3,
                        "\(language) \"\(text)\" is \(String(format: "%.1f", ratio))× the English \"\(key)\"")
            }
        }
    }
}
