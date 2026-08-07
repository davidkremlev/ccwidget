import AppKit
import Foundation
import SwiftUI
import Testing

/// Does the row still contain a bar?
///
/// **The gap this closes.** Two hundred and fifteen checks passed while the
/// five-hour and weekly rows on a real tile had no bar at all. Tier 1 measures
/// the width of strings, tier 2 measures what is spoken, tier 3 compares chart
/// pictures — and not one of them asks whether the parts of a row are still on
/// screen. A row that loses its bar keeps every string it had, so every check
/// stayed green.
///
/// **What went wrong.** `DetailLine` was put into the row's `HStack` with
/// `layoutPriority(2)`, beside the bar. The bar is the only flexible element
/// there, so when the line grew — a Russian "сброс Чт 07:00 · 5 дн 20 ч" is
/// half again as wide as "resets Thu 7:00 AM · 5 days, 20 hr" — the bar was
/// what gave way, all the way to nothing.
///
/// **Why measuring rather than inspecting.** SwiftUI does not hand a test its
/// view tree, and the accessibility tree is empty in a test process (measured,
/// `Docs/rendering-checks.md`). What can be asked is the picture: render the
/// row and count pixels of the bar's tint. A bar narrower than the minimum the
/// layout promises is a defect whether it is 0 points wide or 12.
@MainActor
@Suite("Row composition")
struct RowCompositionTests {

    /// Section 9, measured: the medium tile is 344 points wide and the widget
    /// applies 14 points of padding on each side.
    private static let mediumContent: CGFloat = 344 - 2 * 14

    /// `TextMetricsTests` names the same number: below this a bar carries no
    /// information, it is a decoration beside a number.
    private static let minimumBarWidth: CGFloat = 40

    private static let languages = ["de", "en", "es", "ja", "ru", "zh-Hans"]

    /// Real time, not a fixed instant. The countdown in the row is a dynamic
    /// date: it measures from the system clock and ignores the date the entry
    /// carries (measured, `SPEC` 2.3). Pinning `now` to 2023 made the row print
    /// "2 г. 8 мес" — a string the tile will never show — so the check would
    /// have been measuring a case that does not exist.
    private func entry(resetsIn seconds: TimeInterval) -> CCWidgetEntry {
        let now = Date()
        let snapshot = Snapshot(
            schemaVersion: 1, capturedAt: now, sessionId: nil, claudeCodeVersion: nil,
            model: nil, project: ProjectInfo(name: "ccwidget"),
            // Everything at 100 %: the measurement below counts pixels of the
            // bar's tint, and only a full bar has tint across its whole width.
            // The first version of this check used realistic percentages and
            // was therefore measuring the fill, not the bar — it caught the
            // defect by luck, because a bar squeezed to nothing has no fill
            // either. A check that measures a symptom of the thing it names is
            // the class of mistake CLAUDE.md warns about.
            limits: Limits(
                fiveHour: LimitWindow(usedPercentage: 100, resetsAt: now.addingTimeInterval(seconds)),
                sevenDay: LimitWindow(usedPercentage: 100, resetsAt: now.addingTimeInterval(seconds))),
            context: ContextInfo(usedPercentage: 100, totalInputTokens: 1_000_000,
                                 windowSize: 1_000_000, cacheHitRatio: 1),
            cost: CostInfo(sessionUsd: 146.1))
        return CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: nil)
    }

    /// The width of the bar in the rendered row, in points.
    ///
    /// Measured by shape rather than by colour, and that took two wrong turns
    /// worth recording. Counting pixels of the bar's tint measured the *fill*,
    /// which at 25 % usage is a quarter of the bar — the check then caught the
    /// defect only because a bar squeezed to nothing has no fill either.
    /// Rendering at 100 % to make fill and bar the same width moved the level
    /// to `depleted`, whose colour is grey, and the colour filter found
    /// nothing at all.
    ///
    /// What is stable is the geometry: the bar is the only long horizontal run
    /// of non-background pixels in the row. Letters make short runs, the bar
    /// makes one run tens of points wide. So the measurement is "the longest
    /// horizontal run of anything that is not the background", which holds
    /// whatever colour the level happens to be.
    private func barWidth(_ view: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return 0 }
        let rep = NSBitmapImageRep(cgImage: cg)

        var widest: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            var run = 0
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // The renderer draws on transparency; anything with alpha is
                // ink, and the bar is the widest continuous stretch of it.
                let ink = c.alphaComponent > 0.15
                if ink {
                    run += 1
                    widest = max(widest, CGFloat(run))
                } else {
                    run = 0
                }
            }
        }
        return widest
    }

    /// Where the ink sits in the row: the bar, and how much is drawn on either
    /// side of it.
    ///
    /// The bar alone is not enough to describe the row, and finding that out
    /// cost a second report from the desktop. With `minWidth` the bar survives
    /// whatever the line does — so a row can pass "the bar is 40 points wide"
    /// while the caption beside it has been squeezed out of existence, which is
    /// exactly what shipped: `25 %` and a full reset line, and no caption at
    /// all. What the row is made of is three quantities, not one.
    private func inkProfile(_ view: some View, width: CGFloat)
        -> (caption: CGFloat, bar: CGFloat, trailing: CGFloat) {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return (0, 0, 0) }
        let rep = NSBitmapImageRep(cgImage: cg)

        func isInk(_ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return c.alphaComponent > 0.15
        }

        // The bar is the longest horizontal run of ink anywhere in the row.
        var bar = (length: 0, start: 0)
        for y in 0..<rep.pixelsHigh {
            var run = 0
            for x in 0..<rep.pixelsWide {
                if isInk(x, y) {
                    run += 1
                    if run > bar.length { bar = (run, x - run + 1) }
                } else {
                    run = 0
                }
            }
        }
        guard bar.length > 0 else { return (0, 0, 0) }

        // Everything left of the bar is the glyph and the caption; everything
        // right of it is the percentage and the line. Measured as extent, not
        // as pixel count: a caption is letters with gaps between them.
        func extent(_ range: Range<Int>) -> CGFloat {
            var first = -1, last = -1
            for x in range {
                var any = false
                for y in 0..<rep.pixelsHigh where isInk(x, y) { any = true; break }
                if any {
                    if first < 0 { first = x }
                    last = x
                }
            }
            return first < 0 ? 0 : CGFloat(last - first + 1)
        }

        let leading = extent(0..<bar.start)
        let trailing = extent((bar.start + bar.length)..<rep.pixelsWide)
        // The glyph is a fixed 13 points or so; the caption is what is left.
        return (caption: max(0, leading - 16), bar: CGFloat(bar.length), trailing: trailing)
    }

    /// A limit row at full usage, in every language, with a reset far enough
    /// out that the line beside it is at its longest.
    @Test("A limit row keeps its bar in every language")
    func limitRowKeepsItsBar() {
        let entry = entry(resetsIn: 5 * 86_400 + 20 * 3600)

        for language in Self.languages {
            let locale = Locale(identifier: language)
            let row = GaugeRow(
                caption: "Week used",
                reading: entry.limitReading(entry.snapshot?.limits.sevenDay),
                dimmed: false,
                detail: entry.limitDetail(entry.snapshot?.limits.sevenDay, locale: locale),
                moment: entry.date
            )
            .environment(\.locale, locale)

            let ink = inkProfile(row, width: Self.mediumContent)
            #expect(ink.bar >= Self.minimumBarWidth,
                    "\(language): the bar is \(Int(ink.bar)) pt wide, below the \(Int(Self.minimumBarWidth)) pt minimum")
            // The caption is the row's name. Squeezed below this it is an
            // abbreviation nobody asked for; gone entirely, as it was on the
            // tile, the row says a percentage about nothing.
            #expect(ink.caption >= 40,
                    "\(language): the caption is \(Int(ink.caption)) pt wide — squeezed out")
            // The compact line plus the percentage. A full "сброс Чт 07:00 ·
            // 5 дн 18 ч" runs past this, which is how a row that draws the
            // uncompacted line is caught even when the bar holds its minimum.
            #expect(ink.trailing <= 120,
                    "\(language): \(Int(ink.trailing)) pt to the right of the bar — the line is not compact")
        }
    }

    /// The bar is not the only thing that was wrong on the tile. The row also
    /// printed **both** the reset moment and the countdown — "сброс Чт 07:00 ·
    /// 5 дн 18 ч" — where the compact form prints only the countdown. Width
    /// alone cannot see that: a row can hold its bar and still say twice as
    /// much as it should.
    ///
    /// So this asks the compact form directly. `spokenDetail` is the same
    /// switch `DetailLine` draws from, and it returns a `String`, which is the
    /// whole reason the spoken form is not a `Text`.
    @Test("The compact row says the countdown and not the moment")
    func compactRowOmitsTheMoment() {
        let entry = entry(resetsIn: 5 * 86_400 + 18 * 3600)

        for language in Self.languages {
            let locale = Locale(identifier: language)
            let detail = entry.limitDetail(entry.snapshot?.limits.sevenDay, locale: locale)
            guard case .reset(let moment, _) = detail else {
                Issue.record("\(language): an open window must produce .reset"); continue
            }

            let compact = spokenDetail(detail, at: entry.date, compact: true, locale: locale)
            let full = spokenDetail(detail, at: entry.date, compact: false, locale: locale)

            #expect(compact?.contains(moment) == false,
                    "\(language): the compact row still names the reset moment: \(compact ?? "nil")")
            #expect(full?.contains(moment) == true,
                    "\(language): the large tile's line lost the moment: \(full ?? "nil")")
            #expect(compact != full, "\(language): compact and full forms are identical")
        }
    }

    /// The same for a window that has already closed — the case the five-hour
    /// row was in when the defect was reported, and the reason that row kept
    /// its bar while the weekly one did not: "closed" is short in any language,
    /// so it never squeezed anything.
    @Test("A closed window says one word when compact")
    func compactClosedRowIsOneWord() {
        let entry = entry(resetsIn: -3600)

        for language in Self.languages {
            let locale = Locale(identifier: language)
            let detail = entry.limitDetail(entry.snapshot?.limits.fiveHour, locale: locale)
            guard case .closed(let moment) = detail else {
                Issue.record("\(language): a past window must produce .closed"); continue
            }
            let compact = spokenDetail(detail, at: entry.date, compact: true, locale: locale)
            #expect(compact?.contains(moment) == false,
                    "\(language): the compact closed row names the moment: \(compact ?? "nil")")
        }
    }

    /// A structural check, and it is here for want of a better instrument.
    ///
    /// The row must not read geometry. `GeometryReader` reports whatever the
    /// layout proposes, and WidgetKit proposes things a test process never
    /// sees: the extension crashed on every render for five hours inside
    /// `GeometryReaderLayout.placeSubviews` while every check here stayed
    /// green. Clamping the width the reader returned did not help; removing
    /// the reader did.
    ///
    /// Checking the source text is crude — it cannot tell a legitimate reader
    /// from a dangerous one, and `ForecastChart` still has one on purpose. But
    /// the alternative is nothing: this process cannot render the way WidgetKit
    /// renders, which is the whole reason the crash survived 221 checks. When
    /// the bar's implementation changes, this fails and asks the question
    /// again.
    @Test("The bar does not read geometry")
    func barDoesNotUseGeometryReader() throws {
        let source = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Widget/Components.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        let start = try #require(text.range(of: "struct Bar: View {"),
                                 "Bar has been renamed; this check needs updating")
        let end = text.range(of: "\n}", range: start.upperBound..<text.endIndex)?.lowerBound
            ?? text.endIndex
        let body = String(text[start.lowerBound..<end])

        // `GeometryReader {` — the opening of one, not the word. The comment
        // above `Bar` explains why there is no reader, and a check that trips
        // over its own explanation is a check nobody keeps.
        #expect(!body.contains("GeometryReader {"),
                "Bar reads geometry again — see the crash of 7 August 2026, SPEC 5.1")
    }

    /// The context row was never affected — it carries a plain string, not a
    /// countdown — and it is here as the control. If this one fails too, the
    /// instrument is wrong rather than the layout.
    @Test("The context row keeps its bar, as it always did")
    func contextRowKeepsItsBar() {
        let entry = entry(resetsIn: 3600)

        for language in Self.languages {
            let locale = Locale(identifier: language)
            let row = GaugeRow(
                caption: "Context used",
                reading: entry.contextReading.withAuxiliary(entry.projectName),
                dimmed: false
            )
            .environment(\.locale, locale)

            let width = barWidth(row, width: Self.mediumContent)
            #expect(width >= Self.minimumBarWidth,
                    "\(language): control row's bar is \(Int(width)) pt")
        }
    }
}
