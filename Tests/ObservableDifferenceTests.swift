import Foundation
import Testing

/// Every case of every enum makes an observable difference in the thing that
/// enum is responsible for.
///
/// The companion to `OutcomeCoverageTests`, which holds that every case is
/// *produced*. Being produced is not enough: `Freshness` had four cases and
/// three appearances, so two of them were the same state under two names —
/// something to maintain, a widget reload that returned an identical timeline,
/// and a reason in `SPEC` 2.3 that had quietly stopped being true.
///
/// The rule is not "all cases differ". It is: **each case produces a
/// difference in what it is responsible for**, and the area of responsibility
/// is different for each enum. `Freshness` answers to how the widget draws
/// itself; `Installer.Failure` to the message and the action it suggests;
/// `Forecast.Outcome` to the verdict on screen; `Forecast.Gate` to the
/// diagnosis. So each suite below names its area first and only then compares.
///
/// Two of them are guarded elsewhere and are not repeated here: `Freshness` by
/// `everyLevelLooksDifferent` and `Level` by `symbolsAreDistinct` and
/// `coloursAreDistinct`, both in `ThresholdsTests`. `OnboardingStep` is not
/// here at all — its consequence is which of four step views is shown, and
/// that is tier 2 of `Docs/rendering-checks.md`.
@Suite("Every case makes an observable difference")
struct ObservableDifferenceTests {

    /// A locale pinned so the comparison is about the strings differing, not
    /// about which language the runner happens to be in.
    private static let locale = Locale(identifier: "en_US_POSIX")

    /// Distinctness stated once. `subject` names the enum in the failure, and
    /// `describe` prints the collision rather than just its count.
    private func allDistinct<Case, Effect: Hashable>(
        _ subject: String,
        _ cases: [Case],
        _ effect: (Case) -> Effect,
        line: SourceLocation = #_sourceLocation
    ) {
        var seen: [Effect: Int] = [:]
        for (index, value) in cases.enumerated() {
            let produced = effect(value)
            if let first = seen[produced] {
                Issue.record(
                    "\(subject): case \(first) and case \(index) both produce \(produced)",
                    sourceLocation: line)
            }
            seen[produced] = index
        }
        #expect(seen.count == cases.count, "\(subject): \(cases.count) cases, \(seen.count) outcomes",
                sourceLocation: line)
    }

    // MARK: Forecast.Outcome — the verdict on screen

    /// Responsible for what the estimate block says: the caption, how loudly
    /// it says it, whether the chart is drawn and whether the projection is.
    ///
    /// This is the enum the rule was written for. Its cases used to differ
    /// only inside a `@ViewBuilder`, so on everything a check could reach —
    /// `hasRate` and `showsProjection` — `.notEnoughData` equalled `.flat` and
    /// `.lastsUntilReset` equalled `.runsOut`. The `.runsOut` defect lived in
    /// exactly that blind spot for weeks.
    ///
    /// The five forecasts are produced by `Forecast.make` rather than
    /// assembled by hand: a check that constructs a state the code cannot
    /// reach asserts that an unreachable state is handled.
    @Test("Every estimate outcome says something different")
    func estimateOutcomesDiffer() throws {
        let statements = try Self.oneForecastPerOutcome().map {
            estimateStatement($0.forecast, locale: Self.locale)
        }
        allDistinct("Forecast.Outcome", statements) { statement in
            Fingerprint(parts: [statement.caption,
                                statement.emphasis.rawValue,
                                "\(statement.drawsChart)",
                                "\(statement.drawsProjection)"])
        }
    }

    /// And the pairs that were indistinguishable before, named so the check
    /// says what it is for rather than only that a set was small.
    @Test("The two pairs that used to be indistinguishable are not")
    func theOldBlindSpotIsClosed() throws {
        let byName = Dictionary(uniqueKeysWithValues: try Self.oneForecastPerOutcome()
            .map { ($0.forecast.outcome.label, estimateStatement($0.forecast, locale: Self.locale)) })

        let silent = try #require(byName["notEnoughData"])
        let flat = try #require(byName["flat"])
        #expect(silent.caption != flat.caption, "\(silent.caption)")
        #expect(silent.drawsChart != flat.drawsChart,
                "the chart is drawn for both, so nothing on screen separates them")

        let lasts = try #require(byName["lastsUntilReset"])
        let runsOut = try #require(byName["runsOut"])
        #expect(lasts.caption != runsOut.caption)
        #expect(lasts.emphasis != runsOut.emphasis,
                "one says the quota lasts and the other that it does not, in the same colour")
    }

    /// Fixtures that reach each of the five, through the real entry point.
    private struct Produced {
        let forecast: Forecast
    }

    private static func oneForecastPerOutcome() throws -> [Produced] {
        let now = Date(timeIntervalSince1970: 1_785_000_000)

        func series(count: Int, stepMinutes: Double, from start: Int, per step: Double,
                    resets: Date, noise: (Int) -> Double = { _ in 0 }) -> [HistoryEntry] {
            (0..<count).map { i in
                HistoryEntry(
                    time: now.addingTimeInterval(-Double(count - 1 - i) * stepMinutes * 60),
                    sevenDayUsed: Int((Double(start) + step * Double(i) + noise(i)).rounded()),
                    resetsAt: resets)
            }
        }

        func made(_ history: [HistoryEntry], used: Int, resets: Date) -> Forecast {
            Forecast.make(history: history,
                          window: LimitWindow(usedPercentage: used, resetsAt: resets),
                          now: now)
        }

        let soon = now.addingTimeInterval(20 * 3600)
        let far = now.addingTimeInterval(6.9 * 24 * 3600)
        let week = now.addingTimeInterval(140 * 3600)
        let saw: (Int) -> Double = { $0 % 2 == 0 ? -18 : 18 }

        let produced = [
            // Noise a straight line does not describe.
            made(series(count: 30, stepMinutes: 10, from: 30, per: 0.2, resets: soon, noise: saw),
                 used: 60, resets: soon),
            // A plateau.
            made(series(count: 20, stepMinutes: 15, from: 55, per: 0, resets: soon),
                 used: 55, resets: soon),
            // Just after a weekly reset: a rate, no date.
            made(series(count: 13, stepMinutes: 10, from: 1, per: 0.15, resets: far),
                 used: 3, resets: far),
            // A quota that outlives its window.
            made(series(count: 40, stepMinutes: 40, from: 1, per: 0.25, resets: week),
                 used: 11, resets: week),
            // A quota that does not.
            made(series(count: 15, stepMinutes: 20, from: 60, per: 1.4, resets: soon),
                 used: 80, resets: soon),
        ].map(Produced.init)

        let names = produced.map(\.forecast.outcome.label).sorted()
        #expect(names == ["flat", "lastsUntilReset", "notEnoughData", "rateOnly", "runsOut"],
                "the fixtures no longer produce one of each: \(names)")
        return produced
    }

    // MARK: Forecast.Gate — the diagnosis

    /// Responsible for the diagnosis, not for the verdict.
    ///
    /// On the verdict the gate has two outcomes, not four: `admitsAVerdict` is
    /// true for `open` and `held`, false for `closed` and `withdrawn`. That is
    /// deliberate and recorded in `SPEC` 7 — the four exist to answer *why*,
    /// which is a question the log and `ccwidget-replay` ask and a screen does
    /// not. Diagnostics are a surface: the replay tool's per-state breakdown is
    /// what found the estimate showing a false date 58.8 % of the time.
    ///
    /// So the area compared here is what a maintainer can read back.
    @Test("Every gate state is a different diagnosis")
    func gateStatesDiffer() {
        let gates: [Forecast.Gate] = [.closed, .open, .held, .withdrawn]
        allDistinct("Forecast.Gate", gates) { $0.label }
    }

    /// And the split the verdict does see, stated so that it is a decision on
    /// the record rather than an accident of the mapping.
    @Test("On the verdict the gate has exactly two answers")
    func gateVerdictIsBinary() {
        #expect(Forecast.Gate.open.admitsAVerdict)
        #expect(Forecast.Gate.held.admitsAVerdict)
        #expect(!Forecast.Gate.closed.admitsAVerdict)
        #expect(!Forecast.Gate.withdrawn.admitsAVerdict)
    }

    // MARK: WindowState — what the window says

    /// Responsible for the badge, its tone, whether the bars are drawn and
    /// what stands in their place.
    ///
    /// `.outdated` and `.abandoned` used to be identical here: same badge,
    /// same colour, bars drawn in both. Section 2.4 replaces day-old numbers
    /// with an invitation, the widget did it and the window did not.
    @Test("Every window state says something different")
    func windowStatesDiffer() {
        let states: [WindowState] = [.needsWidget, .needsSetup, .waiting,
                                     .working, .outdated, .abandoned]
        allDistinct("WindowState", states) { state in
            Fingerprint(parts: [state.badge(locale: Self.locale),
                                state.tone.rawValue,
                                "\(state.showsData)",
                                state.explanation(locale: Self.locale) ?? "—"])
        }
    }

    /// The branch that was missing, named.
    @Test("A day-old snapshot is not drawn as though it were current")
    func abandonedReplacesTheNumbers() {
        #expect(!WindowState.abandoned.showsData,
                "the window still draws bars for data over a day old")
        let explanation = WindowState.abandoned.explanation(locale: Self.locale)
        #expect(explanation != nil, "and it puts nothing in their place")
        #expect(WindowState.outdated.showsData,
                "an hour-old snapshot is dimmed, not withheld — that boundary did not move")
    }

    // MARK: Installer.Integrity — the warning in the window

    /// Responsible for the line the window prints about the exporter, and for
    /// whether the tamper banner is raised at all.
    @Test("Every integrity verdict warns differently")
    func integrityVerdictsDiffer() {
        let cases: [Installer.Integrity] = [.matches, .changed, .unknown, .missing]
        allDistinct("Installer.Integrity", cases) { verdict in
            Fingerprint(parts: [verdict.detail(locale: Self.locale),
                                "\(verdict.raisesBanner)"])
        }
    }

    // MARK: Installer.Failure — the message and the action it suggests

    /// Responsible for what the person is told to do next. Telling someone to
    /// add a widget when the real problem is a missing interpreter wastes
    /// their afternoon.
    @Test("Every installer failure suggests something different")
    func installerFailuresDiffer() {
        let cases: [Installer.Failure] = [
            .widgetContainerMissing,
            .templateMissing,
            .pythonMissing,
            .writeFailed(URL(filePath: "/tmp/settings.json"), CocoaError(.fileWriteNoPermission)),
        ]
        allDistinct("Installer.Failure", cases) { $0.errorDescription ?? "" }
    }

    // MARK: Installer.StatusLineState — whether setup is needed, and the warning

    /// Responsible for two things: whether the app considers itself installed,
    /// and whether onboarding warns before overwriting somebody else's key.
    @Test("Every status-line state leads somewhere different")
    func statusLineStatesDiffer() {
        let cases: [Installer.StatusLineState] = [.absent, .ours, .foreign("/opt/other.sh")]
        allDistinct("Installer.StatusLineState", cases) { state in
            var foreignCommand = "—"
            if case .foreign(let command) = state { foreignCommand = command }
            return Fingerprint(parts: ["\(state == .ours)", foreignCommand])
        }
    }

    // MARK: SnapshotStoreError — the reason nothing is shown

    /// Responsible for the sentence that reaches the widget in place of the
    /// numbers, and the log line beside it. "Permission denied" and "no such
    /// file" look identical from the outside unless this says otherwise.
    @Test("Every snapshot failure explains itself differently")
    func snapshotErrorsDiffer() {
        let url = URL(filePath: "/tmp/snapshot.json")
        let cases: [SnapshotStoreError] = [
            .fileMissing(url),
            .unreadable(url, CocoaError(.fileReadNoPermission)),
            .malformed(CocoaError(.propertyListReadCorrupt)),
            .unsupportedSchema(found: 2, supported: 1),
        ]
        allDistinct("SnapshotStoreError", cases) { $0.description }
    }

    // MARK: SettingsEditor.Outcome — the warning before the button

    /// Responsible for whether the setup screen says the file was rebuilt.
    @Test("A surgical edit and a rebuild are not the same news")
    func settingsOutcomesDiffer() {
        let value: [String: Any] = ["type": "command", "command": "/x.py"]
        // A file that exists and can be patched in place, and no file at all —
        // the two ways this actually happens.
        let cases = [SettingsEditor.setting("statusLine", to: value, in: #"{"theme":"dark"}"#),
                     SettingsEditor.setting("statusLine", to: value, in: nil)]
        allDistinct("SettingsEditor.Outcome", cases) { outcome in
            if case .surgical = outcome { return true } else { return false }
        }
    }

    // MARK: SettingsEditor.RemovalOutcome — what removal reports

    /// Responsible for whether the key went, and for whether the person is
    /// told their formatting did too. Installation has said so since section
    /// 11 asked; removal now says it as well.
    @Test("Removal reports the three outcomes differently")
    func removalOutcomesDiffer() {
        let tidy = """
        {
          "theme": "dark",
          "statusLine": { "type": "command", "command": "/x.py" }
        }
        """
        // Spelled with an escape: `\u004C` is `L`, so a JSON parser reads
        // the name as `statusLine` while a search through the text for
        // `"statusLine"` finds nothing. Ordinary output from a generator that
        // escapes, and exactly what the surgical path must refuse to guess at.
        let awkward = #"{"status\u004Cine":{"type":"command"},"theme":"dark"}"#
        let without = #"{"theme":"dark"}"#

        let cases = [SettingsEditor.removing("statusLine", from: tidy),
                     SettingsEditor.removing("statusLine", from: awkward),
                     SettingsEditor.removing("statusLine", from: without)]
        allDistinct("SettingsEditor.RemovalOutcome", cases) { outcome in
            switch outcome {
            case .surgical: return "removed, formatting kept"
            case .rewritten: return "removed, file rebuilt"
            case .absent: return "nothing to remove"
            }
        }
    }

    // MARK: GaugeReading — what one row shows and says

    /// Responsible for what a row draws and what it announces.
    ///
    /// The case for the third state was that two of them used to be one:
    /// a row whose window had ended drew exactly like a row that never got
    /// data, and said the same thing out loud. Those are different facts —
    /// something did arrive, it is simply about a period that is over — and a
    /// listener told "no data" would go hunting a fault that is not there.
    @Test("Every row state shows and says something different")
    func rowStatesDiffer() {
        let metric = GaugeMetric(fraction: 0.19, value: "19 %", auxiliary: "3 hr", level: .healthy)
        let readings: [GaugeReading] = [.measured(metric), .missing, .closed]

        allDistinct("GaugeReading", readings) { reading in
            Fingerprint(parts: [reading.metric?.value ?? "—",
                                reading.auxiliary(locale: Self.locale) ?? "—",
                                gaugeAnnouncement("Week used", reading, locale: Self.locale)])
        }
    }

    /// And the pair that used to collide, named.
    @Test("A closed window does not read as missing data")
    func closedIsNotMissing() {
        let missing = gaugeAnnouncement("5-hour used", .missing, locale: Self.locale)
        let closed = gaugeAnnouncement("5-hour used", .closed, locale: Self.locale)
        #expect(missing != closed, "both announce as \"\(missing)\"")
        #expect(GaugeReading.closed.auxiliary(locale: Self.locale) != nil,
                "a closed row has nothing beside the dash, so nothing on screen says why")
        #expect(GaugeReading.missing.auxiliary(locale: Self.locale) == nil)
    }

    // MARK: JSONValue — what the log says the field was

    /// Responsible for the text in the parse diagnostics. A field that arrived
    /// as the string "1" and one that arrived as the number 1 are a different
    /// bug report, and the log has to be able to tell them apart.
    @Test("Every JSON node prints differently")
    func jsonValuesDiffer() {
        let cases: [JSONValue] = [
            .null,
            .bool(true),
            .number(1),
            .string("1"),
            .array([.number(1)]),
            .object(["a": .number(1)]),
        ]
        allDistinct("JSONValue", cases) { $0.compactDescription }
    }

    /// A hashable tuple of strings, so a collision prints as itself.
    private struct Fingerprint: Hashable, CustomStringConvertible {
        let parts: [String]
        var description: String { "(" + parts.joined(separator: " | ") + ")" }
    }
}
