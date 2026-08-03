import Foundation
import Testing

/// The window and the widget sit side by side on the same desktop, reading the
/// same file. What they say about it has to be the same sentence.
///
/// Observed: the window said "updated 42 seconds ago" while both widgets, at
/// that moment, said "1 minute ago". Both were arithmetically right and the
/// pair was still wrong — the comparison with the official Usage panel is
/// built on the two surfaces agreeing, and two different numbers beside each
/// other take that away.
///
/// Neither surface asks the clock at the moment it draws. The widget has no
/// clock at all: it renders a timeline entry that was stamped when the
/// timeline was built, up to a minute earlier. The window has one, but it
/// reads it on a timer, so what it holds is up to one tick old. Two quantised
/// clocks with different phases, one snapshot, two answers.
///
/// So the check below is not "the same formatter gives the same string" —
/// that was already true and is why nothing caught this. It is: **at one real
/// instant, with one snapshot, the two surfaces produce the same characters**,
/// each reaching its `now` the way it actually reaches it.
@Suite("The age reads the same in the window and in the widget")
struct AgeAgreementTests {

    /// A moment chosen to sit nowhere special: 17 seconds past a minute, so
    /// nothing lines up by accident.
    private static let start = Date(timeIntervalSince1970: 1_785_000_017)

    /// What the widget shows at `moment`: WidgetKit draws the last entry whose
    /// date has passed, and that entry's date is the only "now" the extension
    /// has.
    private func widgetLine(captured: Date, at moment: Date, timelineBuiltAt built: Date) -> String {
        let dates = CCWidgetProvider.entryDates(from: built)
        let shown = dates.last { $0 <= moment } ?? dates[0]
        return CCWidgetFormat.relativeAge(of: captured, at: shown)
    }

    /// What the window shows at `moment`: the watcher's clock, last moved by a
    /// tick.
    private func windowLine(captured: Date, at moment: Date, watcherStartedAt started: Date) -> String {
        var tick = started
        while true {
            let next = SnapshotWatcher.nextTick(after: tick)
            if next > moment { break }
            tick = next
        }
        return CCWidgetFormat.relativeAge(of: captured, at: tick)
    }

    /// Ages either side of every place the wording changes, and either side of
    /// zero — a snapshot can be stamped after the entry that is on screen, and
    /// a negative age is where "in 0 seconds" comes from.
    static let ages: [TimeInterval] = [-30, -1, 0, 1, 30, 59, 60, 61, 119, 120, 3599, 3600]

    /// Offsets within a minute, so the two clocks are caught at every relative
    /// phase — including the worst one, where the widget has just moved to a
    /// new entry and the window's tick is still due.
    static let offsets: [TimeInterval] = [0, 1, 15, 29, 30, 31, 45, 59]

    @Test("Both surfaces say the same thing at the same instant",
          arguments: ages, offsets)
    func theTwoSurfacesAgree(age: TimeInterval, offset: TimeInterval) {
        let moment = Self.start.addingTimeInterval(offset)
        let captured = Self.start.addingTimeInterval(-age)

        let widget = widgetLine(captured: captured, at: moment, timelineBuiltAt: Self.start)
        let window = windowLine(captured: captured, at: moment, watcherStartedAt: Self.start)

        #expect(widget == window,
                "age \(age) s, \(offset) s into the minute: widget says \"\(widget)\", window says \"\(window)\"")
    }

    /// The same, with the two clocks started at unrelated moments — which is
    /// the ordinary case, since the window starts when the user opens it and
    /// the timeline is rebuilt whenever the system feels like it.
    @Test("They agree whatever moments their clocks were started at",
          arguments: [0, 7, 23, 38, 51].map(TimeInterval.init),
          [0, 11, 27, 44, 58].map(TimeInterval.init))
    func theTwoSurfacesAgreeOutOfPhase(timelineOffset: TimeInterval, watcherOffset: TimeInterval) {
        // Half an hour in, so both clocks have advanced many times.
        let moment = Self.start.addingTimeInterval(1800)
        let captured = moment.addingTimeInterval(-75)

        let widget = widgetLine(captured: captured, at: moment,
                                timelineBuiltAt: Self.start.addingTimeInterval(timelineOffset))
        let window = windowLine(captured: captured, at: moment,
                                watcherStartedAt: Self.start.addingTimeInterval(watcherOffset))

        #expect(widget == window,
                "timeline built +\(timelineOffset) s, watcher started +\(watcherOffset) s: widget says \"\(widget)\", window says \"\(window)\"")
    }

    // MARK: The same disagreement, told in colour

    /// Freshness decides whether the numbers are dimmed and whether they are
    /// shown at all. It is the same statement about the same snapshot as the
    /// age caption, made without words — so two surfaces reading one file must
    /// not dim at different moments either, and having built shared clocks for
    /// the caption it would be strange to leave the colour on the old ones.
    ///
    /// Ages sit either side of each threshold: five minutes, an hour, a day.
    @Test("Both surfaces reach the same freshness at the same instant",
          arguments: [-30, 0, 299, 300, 301, 3599, 3600, 3601, 86_399, 86_400, 86_401]
            .map(TimeInterval.init),
          offsets)
    func freshnessAgrees(age: TimeInterval, offset: TimeInterval) {
        let moment = Self.start.addingTimeInterval(offset)
        let snapshot = Self.snapshot(capturedAt: Self.start.addingTimeInterval(-age))

        let dates = CCWidgetProvider.entryDates(from: Self.start)
        let shown = dates.last { $0 <= moment } ?? dates[0]
        let widget = Freshness(of: snapshot, at: shown)

        var tick = Self.start
        while SnapshotWatcher.nextTick(after: tick) <= moment {
            tick = SnapshotWatcher.nextTick(after: tick)
        }
        let window = Freshness(of: snapshot, at: tick)

        #expect(widget == window,
                "age \(age) s, \(offset) s into the minute: widget is \(String(describing: widget)), window is \(String(describing: window))")
        #expect(widget.isDimmed == window.isDimmed)
        #expect(widget.hidesNumbers == window.hidesNumbers)
    }

    private static func snapshot(capturedAt: Date) -> Snapshot {
        Snapshot(schemaVersion: 1, capturedAt: capturedAt, sessionId: nil,
                 claudeCodeVersion: nil, model: nil, project: nil,
                 limits: Limits(fiveHour: nil, sevenDay: nil), context: nil, cost: nil)
    }

    // MARK: The grid the two share

    /// The widget's clock *is* the entry dates. If they are stamped from
    /// whenever the timeline happened to be built, they are on a grid of their
    /// own and nothing else can join it.
    @Test("Every timeline entry lands on a minute boundary",
          arguments: [0, 1, 17, 30, 59].map(TimeInterval.init))
    func entryDatesAreOnTheGrid(built: TimeInterval) {
        let dates = CCWidgetProvider.entryDates(from: Self.start.addingTimeInterval(built))
        for date in dates {
            #expect(AgeClock.anchor(date) == date, "\(date) is not the start of a minute")
        }
        #expect(dates.count == CCWidgetProvider.count)
        #expect(dates[0] <= Self.start.addingTimeInterval(built),
                "the first entry is in the future, so nothing would be drawn until it arrives")
    }

    /// And the window's clock has to reach the same boundaries. Thirty seconds
    /// into sixty is why: every minute boundary is a tick. A tick interval that
    /// did not divide the minute — 45 seconds, say — would drift past them and
    /// the two surfaces would disagree again, in a way no other check here
    /// would name.
    @Test("The tick grid contains every minute boundary")
    func theTickGridContainsTheMinute() {
        #expect(AgeClock.step.truncatingRemainder(dividingBy: SnapshotWatcher.tickInterval) == 0,
                "a tick every \(SnapshotWatcher.tickInterval) s cannot land on every \(AgeClock.step) s boundary")

        // Demonstrated rather than asserted from arithmetic: start the ticking
        // at an awkward moment and walk it until a minute turns over.
        var tick = Self.start.addingTimeInterval(3)
        var landedOnAMinute = false
        for _ in 0..<10 {
            tick = SnapshotWatcher.nextTick(after: tick)
            if AgeClock.anchor(tick) == tick { landedOnAMinute = true }
        }
        #expect(landedOnAMinute, "no tick in five minutes landed on a minute boundary")
    }

    // MARK: What the shared rule is

    /// Neither surface can tell the time to better than a minute, so neither
    /// may print a number that claims it can. "42 seconds ago" is a promise the
    /// widget cannot keep and the window should not make.
    ///
    /// Stated as the property rather than by hunting for the word "second",
    /// which is a different word in each of the six languages this ships in:
    /// **the line changes when the minute changes and at no other time.**
    @Test("The age says nothing that a whole minute does not",
          arguments: [0, 60, 120, 3540, 3600, 86_400].map(TimeInterval.init))
    func onlyWholeMinutesShow(base: TimeInterval) {
        let anchor = AgeClock.anchor(Self.start)
        func line(_ age: TimeInterval) -> String {
            CCWidgetFormat.relativeAge(of: anchor.addingTimeInterval(-age), at: anchor)
        }

        let start = line(base)
        for extra in [1.0, 17, 30, 59] {
            #expect(line(base + extra) == start,
                    "\(base + extra) s reads \"\(line(base + extra))\" where \(base) s reads \"\(start)\"")
        }

        // The other half, and only where it is true. Past an hour the
        // formatter's own unit coarsens — 61 minutes is still "1 hour ago" —
        // so a minute stops being visible there by the formatter's choice
        // rather than by ours. Asserting it anyway would be asserting that
        // "1 hour 1 minute" gets printed, which nothing wants.
        if base + 60 < 3600 {
            #expect(line(base + 60) != start,
                    "a whole minute later it still reads \"\(start)\"")
        }
    }

    /// The zero and the negative case. A snapshot written after the entry on
    /// screen was stamped gives a negative age, and the numeric wording for
    /// that is "in 0 seconds" — a widget telling you the data arrives shortly.
    @Test("An age at or below zero reads as the present",
          arguments: [-3600, -60, -1, 0].map(TimeInterval.init))
    func zeroAndBelowReadAsNow(age: TimeInterval) {
        let captured = Self.start.addingTimeInterval(-age)
        let line = CCWidgetFormat.relativeAge(of: captured, at: Self.start)
        let atZero = CCWidgetFormat.relativeAge(of: Self.start, at: Self.start)

        #expect(line == atZero,
                "a snapshot \(-age) s in the future reads \"\(line)\" instead of \"\(atZero)\"")
        #expect(!line.contains("0"), "\"\(line)\" still counts something out")
    }

    /// Above a minute the wording stays a duration. `.named` phrasing would
    /// give "yesterday" and "last week", which is a calendar statement, not an
    /// age — and section 2.4 wants stale data to look its age.
    @Test("Beyond a minute the age is still a duration")
    func longAgesStayDurations() {
        // Measured from the anchor, not from `start`: `start` sits 17 seconds
        // into its minute, and an age counted from there is 23 hours and 59
        // minutes, which is a true answer to a question nobody asked.
        let anchor = AgeClock.anchor(Self.start)
        let day = CCWidgetFormat.relativeAge(of: anchor.addingTimeInterval(-86_400), at: anchor)
        let week = CCWidgetFormat.relativeAge(of: anchor.addingTimeInterval(-604_800), at: anchor)

        // A digit is what separates "1 day ago" from "yesterday" in every
        // language here; the calendar wording carries no number at all.
        #expect(!day.filter(\.isNumber).isEmpty, "a day old reads \"\(day)\"")
        #expect(!week.filter(\.isNumber).isEmpty, "a week old reads \"\(week)\"")
    }
}
