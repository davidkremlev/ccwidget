import Foundation
import SwiftUI
import Testing

/// Tier 2 of the rendering plan: what the widget says out loud, as text.
///
/// The defect this exists for took a real VoiceOver pass to find and could not
/// have been found any other way: the three rows announced their percentage
/// before their caption — "30 %, five-hour used" — so a listener got three
/// bare numbers ahead of the things they measured. Nothing about that is
/// visible, and no image would ever have shown it.
///
/// **What this checks and what it does not.** It checks the strings the views
/// compose, against a baseline committed beside them. It does not read the
/// platform accessibility tree: SwiftUI builds that lazily, only when an
/// assistive client is attached, and an `NSHostingView` in a test process has
/// no children to walk — measured, not assumed. That the composed label
/// actually reaches VoiceOver was verified by listening, and stays a manual
/// check; what a baseline can hold is the wording and the order, which is
/// where the defect was.
@Suite("Announcements")
struct AnnouncementTests {

    private static let baselineURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Baselines/announcements.txt")

    private func entry(fiveHour: Int?, sevenDay: Int?, context: Int?,
                       age: TimeInterval = 0) -> CCWidgetEntry {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Snapshot(
            schemaVersion: 1, capturedAt: now.addingTimeInterval(-age),
            sessionId: nil, claudeCodeVersion: nil, model: nil, project: nil,
            limits: Limits(
                fiveHour: fiveHour.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(3600)) },
                sevenDay: sevenDay.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(86400)) }),
            context: ContextInfo(usedPercentage: context, totalInputTokens: nil,
                                 windowSize: nil, cacheHitRatio: nil),
            cost: nil)
        return CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: nil)
    }

    /// A snapshot whose five-hour window ended before the moment it is drawn
    /// at. Nothing about the snapshot's own age says so — that is the point.
    private func closedWindowEntry() -> CCWidgetEntry {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = Snapshot(
            schemaVersion: 1, capturedAt: now.addingTimeInterval(-60),
            sessionId: nil, claudeCodeVersion: nil, model: nil, project: nil,
            limits: Limits(
                fiveHour: LimitWindow(usedPercentage: 19,
                                      resetsAt: now.addingTimeInterval(-12 * 3600)),
                sevenDay: LimitWindow(usedPercentage: 28,
                                      resetsAt: now.addingTimeInterval(86_400))),
            context: ContextInfo(usedPercentage: 90, totalInputTokens: nil,
                                 windowSize: nil, cacheHitRatio: nil),
            cost: nil)
        return CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: nil)
    }

    private func emptyEntry() -> CCWidgetEntry {
        CCWidgetEntry(date: Date(timeIntervalSince1970: 1_700_000_000),
                      snapshot: nil, failure: nil, forecast: nil)
    }

    /// Pinned so the file is the same on any machine. The check is about the
    /// wording and the order, not about which locale the runner happens to be
    /// in — and a baseline that differs between two correct machines is a
    /// baseline nobody trusts.
    private static let baselineLocale = Locale(identifier: "en_US_POSIX")

    private func announcement(_ caption: LocalizedStringResource, _ reading: GaugeReading,
                              detail: String? = nil) -> String {
        gaugeAnnouncement(caption, reading, detail: detail, locale: Self.baselineLocale)
    }

    // MARK: The baseline

    private func announcements() -> String {
        var lines: [String] = []

        func section(_ title: String, _ body: () -> Void) {
            lines.append("── \(title)")
            body()
            lines.append("")
        }

        section("normal data") {
            let e = entry(fiveHour: 21, sevenDay: 9, context: 63)
            lines.append("5-hour   " + (announcement("5-hour used", e.limitReading(e.snapshot?.limits.fiveHour))))
            lines.append("week     " + (announcement("Week used", e.limitReading(e.snapshot?.limits.sevenDay))))
            lines.append("context  " + (announcement("Context used", e.contextReading)))
        }

        section("a limit the source has not sent yet") {
            let e = entry(fiveHour: nil, sevenDay: 9, context: 63)
            lines.append("5-hour   " + (announcement("5-hour used", e.limitReading(e.snapshot?.limits.fiveHour))))
            lines.append("week     " + (announcement("Week used", e.limitReading(e.snapshot?.limits.sevenDay))))
        }

        section("no snapshot at all") {
            let e = emptyEntry()
            lines.append("5-hour   " + (announcement("5-hour used", e.limitReading(nil))))
            lines.append("context  " + (announcement("Context used", e.contextReading)))
        }

        section("a snapshot old enough to be abandoned") {
            let e = entry(fiveHour: 21, sevenDay: 9, context: 63, age: 48 * 3600)
            lines.append("5-hour   " + (announcement("5-hour used", e.limitReading(e.snapshot?.limits.fiveHour))))
            lines.append("week     " + (announcement("Week used", e.limitReading(e.snapshot?.limits.sevenDay))))
            lines.append("context  " + (announcement("Context used", e.contextReading)))
        }

        // What sits beside the number on the tile has to be said as well.
        // Dropping it was a regression the order fix introduced, and the
        // baseline enshrined it until a second VoiceOver pass caught it.
        section("with what sits beside the number") {
            // The detail is passed as a literal rather than taken from the
            // metric: a countdown is formatted in the process's locale, and a
            // baseline that says "1 ч" here and "1 hr" there is a baseline
            // nobody trusts. How the countdown itself is formatted belongs to
            // FormattersTests; what belongs here is that it is said at all.
            let e = entry(fiveHour: 21, sevenDay: 9, context: 63)
            let five = e.limitReading(e.snapshot?.limits.fiveHour)
            lines.append("5-hour   " + announcement("5-hour used", five, detail: "3 hr 59 min"))
            lines.append("context  " + announcement("Context used", e.contextReading, detail: "ccwidget"))
        }

        // The third state of a row. It must not be read out as "no data":
        // something did arrive for that row, and a listener told there is no
        // data would go looking for a fault that is not there.
        section("a window that has ended") {
            let e = closedWindowEntry()
            lines.append("5-hour   " + announcement("5-hour used", e.limitReading(e.snapshot?.limits.fiveHour)))
            lines.append("week     " + announcement("Week used", e.limitReading(e.snapshot?.limits.sevenDay)))
            lines.append("context  " + announcement("Context used", e.contextReading))
        }

        section("the boundaries") {
            for used in [0, 50, 81, 100] {
                let e = entry(fiveHour: used, sevenDay: nil, context: nil)
                lines.append(String(format: "%3d %%    ", used)
                             + (announcement("5-hour used", e.limitReading(e.snapshot?.limits.fiveHour))))
            }
        }

        return lines.joined(separator: "\n")
    }

    /// The baseline is text, so a change to it is legible in a pull request —
    /// which is the whole reason this tier is text rather than pictures. A
    /// reviewer can tell an improvement from a regression by reading it.
    @Test("What the widget announces matches the baseline")
    func matchesBaseline() throws {
        // Trailing newlines are an artefact of how the file is written, not
        // part of what is being checked; trim both sides or the comparison
        // fails on whitespace nobody can see.
        let produced = announcements().trimmingCharacters(in: .newlines)

        guard let existing = try? String(contentsOf: Self.baselineURL, encoding: .utf8) else {
            try FileManager.default.createDirectory(
                at: Self.baselineURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try produced.write(to: Self.baselineURL, atomically: true, encoding: .utf8)
            Issue.record("no baseline existed; one was written — review it and commit it")
            return
        }

        if produced != existing.trimmingCharacters(in: .newlines) {
            // Write the new one beside the old so the difference can be read
            // rather than reconstructed from an assertion message.
            let rejected = Self.baselineURL.appendingPathExtension("actual")
            try? produced.write(to: rejected, atomically: true, encoding: .utf8)
        }
        #expect(produced == existing.trimmingCharacters(in: .newlines),
                "announcements changed; compare Baselines/announcements.txt with .actual beside it")
    }

    /// The property the baseline exists to protect, stated on its own so a
    /// regression names itself rather than showing up as a diff someone has to
    /// interpret.
    @Test("The caption is announced before the value")
    func labelPrecedesValue() {
        let e = entry(fiveHour: 21, sevenDay: nil, context: nil)
        let text = (announcement("5-hour used", e.limitReading(e.snapshot?.limits.fiveHour)))

        let caption = try? #require(text.range(of: "5-hour used"))
        let percent = try? #require(text.range(of: "21"))
        guard let caption, let percent else {
            Issue.record("neither part of \"\(text)\" is recognisable")
            return
        }
        #expect(caption.lowerBound < percent.lowerBound,
                "the value comes first: \"\(text)\"")
    }

    /// A row with nothing behind it says so, rather than reading as zero.
    @Test("A row with no data says so")
    func missingDataIsAnnounced() {
        let e = emptyEntry()
        let text = (announcement("Week used", e.limitReading(nil)))
        #expect(text.contains("no data"), "got \"\(text)\"")
        #expect(!text.contains("0"), "an absent measurement must not read as zero: \"\(text)\"")
    }
}

/// The two enums that were private to their views, and therefore had five and
/// three cases respectively that nothing could ask for.
@Suite("View state")
struct ViewStateTests {

    private func snapshot(age: TimeInterval) -> Snapshot {
        let now = Date()
        return Snapshot(schemaVersion: 1, capturedAt: now.addingTimeInterval(-age),
                        sessionId: nil, claudeCodeVersion: nil, model: nil, project: nil,
                        limits: Limits(fiveHour: nil, sevenDay: nil),
                        context: nil, cost: nil)
    }

    /// The order of the questions is the content of the type, so the checks
    /// are written as "this beats that" rather than as six independent cases.
    @Test("A missing container outranks everything else")
    func containerFirst() {
        let state = WindowState(containerExists: false, statusLineIsOurs: true,
                                snapshot: snapshot(age: 0), now: Date())
        #expect(state == .needsWidget)
        #expect(!state.showsData)
    }

    /// "Waiting" would be a lie when nothing is configured to write, and a
    /// person would wait for it.
    @Test("Setup outranks the absence of data")
    func setupBeforeData() {
        let state = WindowState(containerExists: true, statusLineIsOurs: false,
                                snapshot: nil, now: Date())
        #expect(state == .needsSetup)
    }

    @Test("Everything in place and nothing written yet")
    func waiting() {
        let state = WindowState(containerExists: true, statusLineIsOurs: true,
                                snapshot: nil, now: Date())
        #expect(state == .waiting)
        #expect(!state.showsData)
    }

    @Test("The three ages",
          arguments: [(0.0, WindowState.working), (3600 * 2, .outdated), (86_400 * 2, .abandoned)])
    func ages(age: TimeInterval, expected: WindowState) {
        let state = WindowState(containerExists: true, statusLineIsOurs: true,
                                snapshot: snapshot(age: age), now: Date())
        #expect(state == expected, "\(Int(age)) s old")
    }

    /// This used to say "an aged snapshot still has numbers to show" of all
    /// three, which was the defect written down as a requirement: section 2.4
    /// replaces day-old numbers with an invitation, the widget did it and the
    /// window did not. Kept and split, because where the line falls is worth
    /// asserting either way.
    @Test("Numbers survive being dimmed, and do not survive a day")
    func numbersSurviveDimmingButNotADay() {
        #expect(WindowState.working.showsData)
        #expect(WindowState.outdated.showsData,
                "an hour-old snapshot is dimmed, not withheld")
        #expect(!WindowState.abandoned.showsData,
                "a day-old snapshot is replaced by an invitation")
    }

    // MARK: Onboarding

    /// Asking someone to confirm that software they already have is installed
    /// teaches them to click through without reading.
    @Test("The first step is skipped when there is nothing to check")
    func onboardingSkipsTheCheck() {
        #expect(OnboardingStep.start(claudeCodeIsPresent: true) == .install)
        #expect(OnboardingStep.start(claudeCodeIsPresent: false) == .checkClaudeCode)
    }

    @Test("The steps advance in order and only forwards")
    func onboardingAdvances() {
        var step = OnboardingStep.checkClaudeCode
        #expect(step.afterCheckingClaudeCode(present: false) == .checkClaudeCode,
                "without Claude Code the first step holds")

        step = step.afterCheckingClaudeCode(present: true)
        #expect(step == .install)

        step = step.afterInstalling()
        #expect(step == .waitingForData,
                "installing does not mean data exists: the status line runs on the next redraw")

        step = step.afterFirstSnapshot()
        #expect(step == .ready)

        // Late arrivals must not walk the wizard backwards.
        #expect(step.afterInstalling() == .ready)
        #expect(step.afterCheckingClaudeCode(present: true) == .ready)
        #expect(step.afterFirstSnapshot() == .ready)
    }

    /// Pinned so the file is the same on any machine — but for this baseline
    /// that is insurance, not an effect, and saying otherwise would be the
    /// false rationale `CLAUDE.md` warns about.
    ///
    /// The announcements' locale does work: they carry percentages and
    /// countdowns, which Foundation formats from its own locale data. The
    /// setup screen carries nothing but catalog strings, and the test bundle
    /// does not ship `Localizable.xcstrings` — the checks read the catalog off
    /// disk instead. So `String(localized:)` here returns the source string
    /// whatever locale it is handed, and this baseline records the English.
    /// `theCatalogIsAbsentFromTheTestBundle` is the guard on that sentence.
    private static let baselineLocale = Locale(identifier: "en_US_POSIX")

    /// The fact the baseline above rests on, stated so it cannot rot quietly.
    ///
    /// If the catalog is ever added to the test bundle this fails, and it
    /// should: the baseline would start depending on the runner's language,
    /// and the width checks in `TextMetricsTests` — which take translations
    /// from disk precisely because of this — would have a second source of
    /// truth to disagree with.
    @Test("Localized strings are not translated inside the test bundle")
    func theCatalogIsAbsentFromTheTestBundle() {
        let ru = OnboardingStep.install.script(locale: Locale(identifier: "ru"))
        let en = OnboardingStep.install.script(locale: Locale(identifier: "en"))
        #expect(ru == en, "the catalog reached the test bundle: \(ru.actions) vs \(en.actions)")
    }

    // MARK: The setup screen

    /// Tier 2 for the last enum that had no reachable consequence.
    ///
    /// `OnboardingStep` decided which of four views the setup screen showed,
    /// and the views were the only difference between the cases — so nothing
    /// could tell them apart, and a wrong one would have looked like a right
    /// one to every check in the project. What each step says is a value now,
    /// and this is the baseline of it.
    ///
    /// Two of the four ask about the world first, so both answers are in here:
    /// a reader with Claude Code installed and one without, a desktop with the
    /// widget on it and one without.
    private static let onboardingBaselineURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Baselines/onboarding.txt")

    private func onboardingScript() -> String {
        var lines: [String] = []

        func show(_ title: String, _ script: OnboardingStep.Script) {
            lines.append("── \(title)")
            lines.append("headline     \(script.headline)")
            lines.append("explanation  \(script.explanation ?? "—")")
            lines.append("actions      \(script.actions.isEmpty ? "—" : script.actions.joined(separator: " | "))")
            lines.append("")
        }

        let locale = Self.baselineLocale
        show("step 1, Claude Code not found",
             OnboardingStep.checkClaudeCode.script(claudeCodeIsPresent: false, locale: locale))
        show("step 1, Claude Code found",
             OnboardingStep.checkClaudeCode.script(claudeCodeIsPresent: true, locale: locale))
        show("step 2, no widget on the desktop yet",
             OnboardingStep.install.script(widgetContainerExists: false, locale: locale))
        show("step 2, ready to write",
             OnboardingStep.install.script(widgetContainerExists: true, locale: locale))
        show("step 3, waiting for the first snapshot",
             OnboardingStep.waitingForData.script(locale: locale))
        show("step 4, done",
             OnboardingStep.ready.script(locale: locale))

        return lines.joined(separator: "\n")
    }

    @Test("What the setup screen says matches the baseline")
    func onboardingMatchesBaseline() throws {
        let produced = onboardingScript().trimmingCharacters(in: .newlines)
        guard let existing = try? String(contentsOf: Self.onboardingBaselineURL, encoding: .utf8) else {
            try FileManager.default.createDirectory(
                at: Self.onboardingBaselineURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try produced.write(to: Self.onboardingBaselineURL, atomically: true, encoding: .utf8)
            Issue.record("no baseline yet; written, read it before trusting it")
            return
        }
        if produced != existing.trimmingCharacters(in: .newlines) {
            let rejected = Self.onboardingBaselineURL.appendingPathExtension("actual")
            try? produced.write(to: rejected, atomically: true, encoding: .utf8)
            Issue.record("the setup screen changed; compare Baselines/onboarding.txt with .actual beside it")
        }
    }

    /// And the steps have to differ from each other, or the baseline is six
    /// copies of one screen.
    @Test("No two setup steps say the same thing")
    func onboardingStepsDiffer() {
        let locale = Self.baselineLocale
        let scripts = [
            OnboardingStep.checkClaudeCode.script(claudeCodeIsPresent: false, locale: locale),
            OnboardingStep.checkClaudeCode.script(claudeCodeIsPresent: true, locale: locale),
            OnboardingStep.install.script(widgetContainerExists: false, locale: locale),
            OnboardingStep.install.script(widgetContainerExists: true, locale: locale),
            OnboardingStep.waitingForData.script(locale: locale),
            OnboardingStep.ready.script(locale: locale),
        ]
        let headlines = scripts.map { $0.headline }
        #expect(Set(headlines).count == headlines.count,
                "two steps open with the same line: \(headlines)")
    }
}
