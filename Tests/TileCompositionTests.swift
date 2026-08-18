import AppKit
import Foundation
import SwiftUI
import Testing

/// What is a tile made of?
///
/// **The gap this closes.** Until 17 August 2026 `SmallView`, `MediumView` and
/// `LargeView` were not in the test target at all — 601 lines of the 1617 that
/// no check had ever executed. `RowCompositionTests` renders one row;
/// `TextMetricsTests` weighs strings; `ChartBaselineTests` compares one block's
/// picture. Nothing rendered a whole tile, so a tile that lost a row, or drew
/// nothing at all, would have kept every check green.
///
/// **What this cannot see, and why it is still worth having.** WidgetKit
/// archives a view before drawing it, and that step is where both of 7 August's
/// defects lived — the crash in the morning, the black medium tile in the
/// evening. There is no WidgetKit in a test process, so nothing here can
/// reproduce either; `Scripts/tile-probe.swift` looks at the live tile for
/// exactly that reason. What this can do is the other half: given an entry,
/// does the view compose the parts it is supposed to compose. That half was
/// unguarded.
@MainActor
@Suite("Tile composition")
struct TileCompositionTests {

    // Section 9. The tile sizes, and the padding WidgetKit applies inside them.
    private static let small = CGSize(width: 164, height: 164)
    private static let medium = CGSize(width: 344, height: 164)
    private static let large = CGSize(width: 344, height: 344)
    private static let padding: CGFloat = 14

    // MARK: Entries

    private func entry(limits: Bool = true,
                       context: Bool = true,
                       age: TimeInterval = 0) -> CCWidgetEntry {
        let now = Date()
        let captured = now.addingTimeInterval(-age)
        let snapshot = Snapshot(
            schemaVersion: 1, capturedAt: captured, sessionId: nil,
            claudeCodeVersion: "2.1.223",
            model: ModelInfo(id: nil, displayName: "Opus 5", effort: "high"),
            project: ProjectInfo(name: "ccwidget"),
            limits: Limits(
                fiveHour: limits ? LimitWindow(usedPercentage: 21,
                                               resetsAt: now.addingTimeInterval(2 * 3600)) : nil,
                sevenDay: limits ? LimitWindow(usedPercentage: 62,
                                               resetsAt: now.addingTimeInterval(19 * 3600)) : nil),
            context: context ? ContextInfo(usedPercentage: 40, totalInputTokens: 400_000,
                                           windowSize: 1_000_000, cacheHitRatio: 0.99) : nil,
            cost: CostInfo(sessionUsd: 1.13))
        return CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: nil)
    }

    /// Everything at 100 %, so a measured fill is the whole bar. See
    /// `everyRowHasABar`.
    private var full100: CCWidgetEntry {
        let now = Date()
        let snapshot = Snapshot(
            schemaVersion: 1, capturedAt: now, sessionId: nil, claudeCodeVersion: "2.1.223",
            model: ModelInfo(id: nil, displayName: "Opus 5", effort: "high"),
            project: ProjectInfo(name: "ccwidget"),
            limits: Limits(
                fiveHour: LimitWindow(usedPercentage: 100, resetsAt: now.addingTimeInterval(2 * 3600)),
                sevenDay: LimitWindow(usedPercentage: 100, resetsAt: now.addingTimeInterval(19 * 3600))),
            context: ContextInfo(usedPercentage: 100, totalInputTokens: 1_000_000,
                                 windowSize: 1_000_000, cacheHitRatio: 0.99),
            cost: CostInfo(sessionUsd: 1.13))
        return CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: nil)
    }

    /// The same number `RowCompositionTests` and `TextMetricsTests` use: below
    /// this a bar carries no information.
    private static let minimumBarWidth: CGFloat = 40

    private var empty: CCWidgetEntry {
        CCWidgetEntry(date: Date(), snapshot: nil, failure: nil, forecast: nil)
    }

    // MARK: The instrument

    /// The horizontal bands of ink in a rendered tile, top to bottom.
    ///
    /// A tile is a stack of lines with gaps between them, so what it is made of
    /// shows up as bands: rows of pixels that contain ink, separated by rows
    /// that do not. Counting bands says how many things are drawn without
    /// asking what any of them is — which is the point. A caption that changes
    /// wording, a percentage that changes value and a language that changes
    /// width all leave the band count alone; a row that disappears does not.
    ///
    /// Ink is alpha, as in `RowCompositionTests`: the renderer draws on
    /// transparency, so anything opaque is something the view drew.
    private func render(_ view: some View, size: CGSize, locale: String) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width - 2 * Self.padding,
                       height: size.height - 2 * Self.padding)
                .padding(Self.padding)
                .environment(\.colorScheme, .dark)
                .environment(\.locale, Locale(identifier: locale))
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        )
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg)
    }

    private func reader(_ view: some View, size: CGSize, locale: String) -> PixelReader? {
        guard let rep = render(view, size: size, locale: locale) else { return nil }
        return PixelReader(rep)
    }

    private func bands(_ view: some View, size: CGSize,
                       locale: String = "en_US_POSIX") -> [Range<Int>] {
        guard let px = reader(view, size: size, locale: locale) else { return [] }
        return px.bands(px.inkByAlpha)
    }

    private func inkShare(_ view: some View, size: CGSize,
                          locale: String = "en_US_POSIX") -> Double {
        guard let px = reader(view, size: size, locale: locale) else { return 0 }
        return px.inkShare(px.inkByAlpha)
    }

    /// The longest horizontal run of ink inside each band.
    ///
    /// In a gauge row that run is the bar: letters make runs of a dozen points,
    /// a bar makes one of tens. Measured band by band so the answer is "which
    /// rows have a bar", not "does this tile have a bar somewhere".
    private func rowRuns(_ view: some View, size: CGSize) -> [Int] {
        guard let px = reader(view, size: size, locale: "en_US_POSIX") else { return [] }
        return px.bands(px.inkByAlpha).map { px.longestRun(in: $0, px.inkByAlpha) }
    }

    // MARK: What each size is made of

    /// The numbers are measured, not chosen, and they are the same in all six
    /// languages — measured too, because a layout that fits in English can come
    /// apart in Russian and German, and this project has shipped that twice.
    ///
    /// medium: header, three gauge rows, footer. Five.
    /// small:  header, the number, the bar, and the caption — which is allowed
    ///         two lines, so four or five.
    /// large:  fifteen, which is the medium's parts plus the estimate block and
    ///         the two extra detail lines the height affords.
    ///
    /// **The small tile's count used to be exactly four, and that was the check
    /// asserting something the view does not promise.** The caption under the
    /// bar has `lineLimit(2)` on purpose — `SmallView` says why, and
    /// `TextMetricsTests` holds it to fitting in two lines in every language.
    /// Whether it takes one line or two depends on the wording of the moment,
    /// and in English the moment matters: "used · resets Tue 11:47 PM" fits on
    /// one line at the minimum scale and "used · resets Wed 12:28 AM" does
    /// not, by less than a point. So the check passed at 09:47 on 18 August
    /// 2026 and failed at 10:25 with nothing changed but the clock. A count of
    /// four was not the property; a caption that is drawn, on the lines it is
    /// allowed, is.
    @Test("Each size draws the parts section 9 says it draws",
          arguments: ["de", "en", "es", "ja", "ru", "zh-Hans"])
    func eachSizeDrawsItsParts(language: String) {
        let full = entry()
        #expect(bands(MediumView(entry: full), size: Self.medium, locale: language).count == 5,
                "\(language): the medium tile is a header, three rows and a footer")
        #expect((4...5).contains(bands(SmallView(entry: full), size: Self.small, locale: language).count),
                "\(language): the small tile is a header, a number, a bar and a caption of one or two lines")
        #expect(bands(LargeView(entry: full), size: Self.large, locale: language).count >= 12,
                "\(language): the large tile lost most of what it draws")
    }

    /// The property the black tile of 7 August broke, stated where it can be
    /// stated. This cannot see that defect — it lived in WidgetKit's archiving
    /// step, which no test process has — but a view that draws nothing for a
    /// reason this process *can* reach would be caught here.
    ///
    /// Measured: 8.3 % of the small tile is ink, 7.0 % of the medium and the
    /// large. The emptiest state a tile has — a day-old snapshot, digits
    /// replaced by an invitation — is 3.2 %. A blank tile is 0.
    @Test("No size renders blank")
    func nothingRendersBlank() {
        let full = entry()
        #expect(inkShare(SmallView(entry: full), size: Self.small) > 2)
        #expect(inkShare(MediumView(entry: full), size: Self.medium) > 2)
        #expect(inkShare(LargeView(entry: full), size: Self.large) > 2)
        #expect(inkShare(MediumView(entry: empty), size: Self.medium) > 2,
                "even with no data the tile has a message to draw")
    }

    /// Three rows, three bars. `RowCompositionTests` asks this of one row in
    /// isolation; a tile can assemble three rows and still lose a bar in one of
    /// them, and nothing was asking that.
    ///
    /// Everything at 100 % for the reason recorded in `RowCompositionTests`:
    /// the run measured is the fill, and only at 100 % is the fill the bar.
    /// At the realistic percentages of the other checks here the three rows
    /// measure 33, 96 and 66 points — proportional to their values, which is
    /// how it was established that this measures fill.
    @Test("Every gauge row on the medium tile still has a bar")
    func everyRowHasABar() {
        let runs = rowRuns(MediumView(entry: full100), size: Self.medium)
        try? #require(runs.count == 5)
        for (index, run) in runs.enumerated() where (1...3).contains(index) {
            #expect(CGFloat(run) >= Self.minimumBarWidth,
                    "row \(index) has \(run) points of bar, and the layout promises \(Int(Self.minimumBarWidth))")
        }
    }

    /// `SPEC` 2.4: past a day the figures are replaced by an invitation. The
    /// window drew them for a day longer than the tile did once, and the two
    /// states were indistinguishable until `WindowState.abandoned` was given a
    /// branch of its own. This is the tile half of that, in pixels: no bars.
    @Test("A day-old snapshot draws no bars at all")
    func staleDataDrawsNoBars() {
        let runs = rowRuns(MediumView(entry: entry(age: 26 * 3600)), size: Self.medium)
        #expect(runs.allSatisfy { CGFloat($0) < Self.minimumBarWidth },
                "something bar-shaped survived into the stale state: \(runs)")
        #expect(bands(MediumView(entry: entry(age: 26 * 3600)), size: Self.medium).count == 4,
                "the stale tile is a header, a title, a message and an age")
    }

    /// No snapshot at all: a message, not three empty rows.
    @Test("With no snapshot the tile draws a message instead of rows")
    func noSnapshotDrawsAMessage() {
        let runs = rowRuns(MediumView(entry: empty), size: Self.medium)
        #expect(bands(MediumView(entry: empty), size: Self.medium).count == 3,
                "the no-data tile is a header, a title and a message")
        #expect(runs.allSatisfy { CGFloat($0) < Self.minimumBarWidth },
                "a bar was drawn for data that does not exist: \(runs)")
    }

    /// The one thing the small tile exists for. Section 9: at 164 points
    /// exactly one number is readable, so it is set at 34 points and everything
    /// else is a caption. Measured: the tallest band is 26 pixels; the next
    /// tallest is 11.
    @Test("The small tile still has one big number on it")
    func theSmallTileHasItsNumber() {
        let heights = bands(SmallView(entry: entry()), size: Self.small).map(\.count)
        #expect((heights.max() ?? 0) >= 20,
                "nothing on the small tile is large enough to be the number: \(heights)")
    }
}
