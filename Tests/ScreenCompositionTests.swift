import AppKit
import Foundation
import SwiftUI
import Testing

/// What the window and the setup screen are made of.
///
/// **The gap this closes.** These two files are 950 of the 1024 lines that no
/// check had ever executed. `WindowState` has been fully covered for weeks —
/// but as arithmetic: which of six things is true, given four inputs. Nothing
/// asked what the window *draws* when it is one of the six, and the setup
/// screen could not be asked at all, because it read `Installer.live()` from
/// inside the view and so rendered whatever machine it was on.
///
/// The setup screen is the first thing every new user sees. It was the least
/// checked code in the project.
///
/// The instrument is the one from `TileCompositionTests`: bands of ink,
/// counted. It says how many things are drawn without asking what any of them
/// is, so a caption that changes wording or a language that changes width
/// leaves it alone, and a block that disappears does not.
@MainActor
@Suite("Screen composition")
struct ScreenCompositionTests {

    /// The window's own width — section 11 fixes it, and the checks that
    /// measure strings against it use the same number.
    private static let windowWidth: CGFloat = 460

    // MARK: The instrument

    private func render(_ view: some View, width: CGFloat, locale: String) -> NSBitmapImageRep? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.locale, Locale(identifier: locale))
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        )
        renderer.scale = 1
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg)
    }

    private func bands(_ view: some View,
                       width: CGFloat = ScreenCompositionTests.windowWidth,
                       locale: String = "en_US_POSIX") -> [Range<Int>] {
        guard let rep = render(view, width: width, locale: locale) else { return [] }
        var inked: [Bool] = []
        for y in 0..<rep.pixelsHigh {
            var any = false
            for x in 0..<rep.pixelsWide where !any {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   c.redComponent < 0.9 || c.greenComponent < 0.9 || c.blueComponent < 0.9 {
                    any = true
                }
            }
            inked.append(any)
        }
        var out: [Range<Int>] = []
        var start: Int?
        for (y, ink) in inked.enumerated() {
            switch (ink, start) {
            case (true, nil): start = y
            case (false, let s?): out.append(s..<y); start = nil
            default: break
            }
        }
        if let s = start { out.append(s..<inked.count) }
        return out
    }

    private func inkShare(_ view: some View,
                          width: CGFloat = ScreenCompositionTests.windowWidth,
                          locale: String = "en_US_POSIX") -> Double {
        guard let rep = render(view, width: width, locale: locale) else { return 0 }
        var ink = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   c.redComponent < 0.9 || c.greenComponent < 0.9 || c.blueComponent < 0.9 { ink += 1 }
            }
        }
        return Double(ink) / Double(rep.pixelsWide * rep.pixelsHigh) * 100
    }

    /// The longest horizontal run of ink on the whole screen. A gauge row's bar
    /// is tens of points wide; letters are not. Used the same way
    /// `TileCompositionTests` uses it: to ask whether bars are drawn at all.
    private func longestRun(_ view: some View, locale: String = "en_US_POSIX") -> Int {
        guard let rep = render(view, width: Self.windowWidth, locale: locale) else { return 0 }
        var widest = 0
        for y in 0..<rep.pixelsHigh {
            var run = 0
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let ink = (c?.redComponent ?? 1) < 0.9 || (c?.greenComponent ?? 1) < 0.9
                    || (c?.blueComponent ?? 1) < 0.9
                run = ink ? run + 1 : 0
                widest = max(widest, run)
            }
        }
        return widest
    }

    /// A fingerprint of the whole drawing, not of its layout.
    ///
    /// Band profiles cannot separate two states that differ only in colour, and
    /// `SPEC` 2.4 has exactly such a pair: past an hour the figures are dimmed
    /// and gain a word. Dimming moves nothing. So what is compared is the
    /// pixels, which is what "draws differently" means.
    private func fingerprint(_ view: some View, locale: String = "en_US_POSIX") -> String {
        guard let rep = render(view, width: Self.windowWidth, locale: locale),
              let data = rep.representation(using: .png, properties: [:])
        else { return "unrenderable" }
        return "\(data.count):\(data.hashValue)"
    }

    // MARK: Fixtures

    private func snapshot(age: TimeInterval = 0, limits: Bool = true) -> Snapshot {
        let now = Date()
        return Snapshot(
            schemaVersion: 1, capturedAt: now.addingTimeInterval(-age), sessionId: nil,
            claudeCodeVersion: "2.1.223",
            model: ModelInfo(id: nil, displayName: "Opus 5", effort: "high"),
            project: ProjectInfo(name: "ccwidget"),
            limits: Limits(
                fiveHour: limits ? LimitWindow(usedPercentage: 22,
                                               resetsAt: now.addingTimeInterval(5400)) : nil,
                sevenDay: limits ? LimitWindow(usedPercentage: 47,
                                               resetsAt: now.addingTimeInterval(3 * 86_400)) : nil),
            context: ContextInfo(usedPercentage: 68, totalInputTokens: 683_120,
                                 windowSize: 1_000_000, cacheHitRatio: 0.99),
            cost: CostInfo(sessionUsd: 12.4))
    }

    /// Everything at 100 %, so a measured run is the whole bar rather than a
    /// fraction of it. `RowCompositionTests` records why: at 22 % the longest
    /// run is 85 points, which is indistinguishable from a divider — measured,
    /// and it is what made the first version of the check below meaningless.
    private func fullSnapshot(age: TimeInterval = 0) -> Snapshot {
        let now = Date()
        return Snapshot(
            schemaVersion: 1, capturedAt: now.addingTimeInterval(-age), sessionId: nil,
            claudeCodeVersion: "2.1.223",
            model: ModelInfo(id: nil, displayName: "Opus 5", effort: "high"),
            project: ProjectInfo(name: "ccwidget"),
            limits: Limits(fiveHour: LimitWindow(usedPercentage: 100,
                                                 resetsAt: now.addingTimeInterval(5400)),
                           sevenDay: LimitWindow(usedPercentage: 100,
                                                 resetsAt: now.addingTimeInterval(3 * 86_400))),
            context: ContextInfo(usedPercentage: 100, totalInputTokens: 1_000_000,
                                 windowSize: 1_000_000, cacheHitRatio: 0.99),
            cost: CostInfo(sessionUsd: 12.4))
    }

    private func window(_ state: WindowState) -> StatusView {
        let model: FixedStatusModel
        switch state {
        case .needsWidget:
            model = FixedStatusModel(snapshot: nil, integrity: .missing, containerExists: false)
        case .needsSetup:
            model = FixedStatusModel(snapshot: nil, integrity: .missing, statusLineIsOurs: false)
        case .waiting:
            model = FixedStatusModel(snapshot: nil, integrity: .matches)
        case .working:
            model = FixedStatusModel(snapshot: snapshot(), integrity: .matches)
        case .outdated:
            model = FixedStatusModel(snapshot: snapshot(age: 2 * 3600), integrity: .matches)
        case .abandoned:
            model = FixedStatusModel(snapshot: snapshot(age: 26 * 3600), integrity: .matches)
        }
        return StatusView(model: model)
    }

    private static let states: [WindowState] =
        [.needsWidget, .needsSetup, .waiting, .working, .outdated, .abandoned]

    // MARK: The window

    /// Six states, six drawings. `WindowState` is covered as arithmetic and
    /// every case of it is produced by a check — but until this file, no check
    /// had ever drawn the window in any of them. A state that renders blank, or
    /// renders the same as another, was invisible.
    @Test("Every window state draws something, and they are not the same picture")
    func everyWindowStateDrawsSomethingDistinct() {
        var seen: [String: WindowState] = [:]
        for state in Self.states {
            let share = inkShare(window(state))
            #expect(share > 1, "\(state) draws almost nothing: \(share) %")

            let print = fingerprint(window(state))
            if let other = seen[print] {
                Issue.record("\(state) and \(other) draw the same picture")
            }
            seen[print] = state
        }
    }

    /// `SPEC` 2.4, in the window rather than on the tile: past a day the
    /// figures are replaced by an invitation. The window drew day-old
    /// percentages for a while after the widget stopped, and the two states
    /// were indistinguishable until `.abandoned` was given a branch — this is
    /// that branch, in pixels.
    @Test("Bars are drawn where there is data to show, and not where there is not",
          arguments: [(WindowState.working, true), (.outdated, true),
                      (.abandoned, false), (.waiting, false),
                      (.needsSetup, false), (.needsWidget, false)])
    func barsAppearOnlyWithData(state: WindowState, expected: Bool) {
        let view: StatusView
        switch state {
        case .working:   view = StatusView(model: FixedStatusModel(snapshot: fullSnapshot(),
                                                                  integrity: .matches))
        case .outdated:  view = StatusView(model: FixedStatusModel(snapshot: fullSnapshot(age: 2 * 3600),
                                                                  integrity: .matches))
        default:         view = window(state)
        }
        let bars = barCount(view)
        #expect((bars == 3) == expected,
                "\(state): \(bars) rows have a bar, three expected: \(expected)")
        #expect(state.showsData == expected,
                "and the type agrees with the picture")
    }

    /// Where the line between a bar and everything else falls, in points.
    ///
    /// Measured, not chosen. At 100 % usage the widest run in the window is
    /// **137** points — the bar. In every state that draws no bars the widest
    /// run is **87** or less, and it is a button: dividers do not count, being
    /// too light to pass the ink threshold. 110 sits between the two with about
    /// a quarter of the gap on each side.
    ///
    /// Measured at 100 % for the reason `RowCompositionTests` records: what a
    /// run measures is the *fill*, and only at 100 % is the fill the bar. At the
    /// realistic 22 % of the other checks here the widest run is 85 — the same
    /// as a button, which is what made the first version of this check
    /// meaningless in both directions.
    private static let barFloor = 110

    /// How many rows of the window contain a bar. Three, when there is data.
    ///
    /// A count rather than a maximum: "something wide is drawn" is a much
    /// weaker claim than "three rows have one", and the window has exactly
    /// three gauges.
    private func barCount(_ view: some View) -> Int {
        guard let rep = render(view, width: Self.windowWidth, locale: "en_US_POSIX") else { return 0 }
        var count = 0
        var inBar = false
        for y in 0..<rep.pixelsHigh {
            var run = 0, widest = 0
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let ink = (c?.redComponent ?? 1) < 0.9 || (c?.greenComponent ?? 1) < 0.9
                    || (c?.blueComponent ?? 1) < 0.9
                run = ink ? run + 1 : 0
                widest = max(widest, run)
            }
            if widest > Self.barFloor {
                if !inBar { count += 1; inBar = true }
            } else {
                inBar = false
            }
        }
        return count
    }

    /// The banner is the one thing in the window that must not be missable, and
    /// it now has two reasons to appear that say different things.
    @Test("Both banner states draw more than the state without one")
    func theBannerIsVisible() {
        let quiet = bands(StatusView(model: FixedStatusModel(snapshot: snapshot(),
                                                            integrity: .matches))).count
        for verdict in [Installer.Integrity.changed, .outdated] {
            let loud = bands(StatusView(model: FixedStatusModel(snapshot: snapshot(),
                                                               integrity: verdict))).count
            #expect(loud > quiet,
                    "\(verdict) drew \(loud) bands where a quiet window draws \(quiet)")
        }
    }

    // MARK: The setup screen

    /// The first screen a new user meets, in all six languages. It could not be
    /// rendered by anything until the installer was made a parameter of it.
    @Test("The setup screen draws its steps in every language",
          arguments: ["de", "en", "es", "ja", "ru", "zh-Hans"])
    func theSetupScreenDraws(language: String) throws {
        let home = sandbox()
        let inst = installer(home: home, template: makeTemplate(in: home))

        for step in [OnboardingStep.checkClaudeCode, .install, .waitingForData, .ready] {
            let view = OnboardingView(installer: inst, step: step)
            let share = inkShare(view, locale: language)
            #expect(share > 1, "\(language)/\(step): the screen is blank — \(share) %")
            #expect(bands(view, locale: language).count >= 3,
                    "\(language)/\(step): fewer than three things drawn")
        }
    }

    /// The block that tells somebody their own status line will be kept rather
    /// than replaced. It appears only when there is one, and its absence when
    /// there is none is as much the property as its presence.
    @Test("An existing status line is shown before setup, and only then")
    func anExistingStatusLineIsShown() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))

        write(#"{"theme":"dark"}"#, to: home)
        let without = bands(OnboardingView(installer: inst, step: .install)).count

        write(#"{"statusLine":{"type":"command","command":"/usr/local/bin/theirs"}}"#, to: home)
        let with = bands(OnboardingView(installer: inst, step: .install)).count

        #expect(with > without,
                "the warning about an existing status line drew nothing: \(with) bands against \(without)")
    }
}
