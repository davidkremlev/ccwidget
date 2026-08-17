import Foundation
import Testing

/// The defect these were written for: the window showed "updated 21 minutes
/// ago" and a context of 93% while the widget beside it, at the same moment,
/// showed two seconds and 9%. The watcher was reloading the widget and never
/// telling the window anything.
@MainActor
@Suite("Watcher and window state")
struct WatcherTests {

    private func snapshot(capturedAt: Date, fiveHour: Int, week: Int, context: Int) -> Snapshot {
        Snapshot(
            schemaVersion: 1,
            capturedAt: capturedAt,
            sessionId: "abcd1234",
            claudeCodeVersion: "2.1.220",
            model: nil,
            project: nil,
            limits: Limits(
                fiveHour: LimitWindow(usedPercentage: fiveHour,
                                      resetsAt: capturedAt.addingTimeInterval(3600)),
                sevenDay: LimitWindow(usedPercentage: week,
                                      resetsAt: capturedAt.addingTimeInterval(86400))),
            context: ContextInfo(usedPercentage: context, totalInputTokens: nil,
                                 windowSize: nil, cacheHitRatio: nil),
            cost: nil
        )
    }

    /// Counts what the watcher does to the outside world, so a claim about
    /// "without touching the disk" has something behind it.
    private final class Spy {
        var reads = 0
        var reloads = 0
        var current: Snapshot?
        var now = Date()
        /// What the watcher asked to have done later, and after how long. Held
        /// rather than run, so a check decides when later is.
        var postponed: [(after: TimeInterval, work: @MainActor () -> Void)] = []

        @MainActor func firePostponed() {
            let due = postponed
            postponed.removeAll()
            for item in due { item.work() }
        }
    }

    private func watcher(_ spy: Spy, in home: URL) -> SnapshotWatcher {
        SnapshotWatcher(
            store: SnapshotStore(containerURL: SnapshotStore.exchangeURL(home: home)),
            read: {
                spy.reads += 1
                guard let snapshot = spy.current else { throw CocoaError(.fileNoSuchFile) }
                return snapshot
            },
            reloadWidgets: { spy.reloads += 1 },
            clock: { spy.now },
            schedule: { seconds, work in spy.postponed.append((seconds, work)) }
        )
    }

    /// The publication crosses an async boundary, so the check has to wait for
    /// it — but bounded, and it stops the moment the condition holds rather
    /// than sleeping a fixed amount and hoping.
    private func eventually(within timeout: Duration = .seconds(2),
                            _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("A new snapshot reaches the window even when the widget is not due a reload")
    func publishesWhileTheReloadIsRationed() async {
        let home = sandbox()
        makeContainer(in: home)
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        let model = StatusModel(installer: installer(home: home, template: makeTemplate(in: home)),
                                watcher: w)
        model.start()
        defer { model.stop() }

        #expect(await eventually { model.snapshot?.context?.usedPercentage == 9 },
                "the first read reaches the window")
        let reloadsAfterLaunch = spy.reloads

        // A second change immediately after: the budget window forbids another
        // widget reload. The window has no budget and must see it anyway —
        // this is the exact case that produced the twenty-one-minute gap.
        spy.now += 5
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 11, week: 21, context: 93)
        w.handleChange(reason: "test", force: false)

        #expect(spy.reloads == reloadsAfterLaunch, "the widget reload is still rationed")
        #expect(w.state.snapshot?.context?.usedPercentage == 93,
                "the published snapshot is the new one")
        #expect(await eventually { model.snapshot?.context?.usedPercentage == 93 },
                "and the window's model follows it")
    }

    @Test("The age advances without the file being read again")
    func tickReadsNothing() {
        let home = sandbox()
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now.addingTimeInterval(-30),
                               fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        w.handleChange(reason: "test", force: true)

        let readsAfterLoad = spy.reads
        let before = w.state.now
        #expect(readsAfterLoad == 1)

        spy.now += 30
        w.tick()

        #expect(spy.reads == readsAfterLoad, "the tick reads nothing from disk")
        #expect(w.state.now > before, "but the clock the window renders against moves")
        #expect(w.state.snapshot != nil, "and the snapshot in hand is kept")
    }

    /// What the tick is for. No write happens, so nothing is read and no
    /// signature changes — but the snapshot ages past a threshold, the widget
    /// starts drawing itself dimmed, and it has to be told.
    ///
    /// The crossing here is the hour. It used to be five minutes, which was
    /// the boundary between two levels that drew the same — so the reload this
    /// check demanded produced a timeline identical to the one it replaced.
    /// The levels are one now and the hour is the first crossing that changes
    /// anything.
    @Test("Crossing a freshness threshold on the clock alone reloads the widget")
    func tickReloadsOnFreshnessChange() {
        let home = sandbox()
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now.addingTimeInterval(-3599),
                               fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        w.handleChange(reason: "test", force: true)
        #expect(w.state.freshness == .fresh)
        let reloadsAfterLoad = spy.reloads
        let readsAfterLoad = spy.reads

        // Two minutes later the snapshot is over an hour old, so the widget
        // draws itself dimmed. Nothing has been written and nothing is read.
        spy.now += 120
        w.tick()

        #expect(spy.reads == readsAfterLoad, "still nothing is read")
        #expect(w.state.freshness == .stale, "the freshness follows the clock")
        #expect(spy.reloads == reloadsAfterLoad + 1, "and the widget is told once")
    }

    /// The reload the collapse removed. Ageing from four minutes to seven used
    /// to cross a threshold and cost a reload; it now crosses nothing, and the
    /// widget is left alone. This is the check that keeps it that way — the
    /// budget in section 2.3 is small enough that a reload nobody can see is
    /// worth refusing.
    @Test("Ageing without changing how the widget looks costs no reload")
    func tickDoesNotReloadWithoutAVisibleChange() {
        let home = sandbox()
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now.addingTimeInterval(-240),
                               fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        w.handleChange(reason: "test", force: true)
        #expect(w.state.freshness == .fresh)
        let reloadsAfterLoad = spy.reloads

        spy.now += 180          // seven minutes old, and still drawn the same
        w.tick()

        #expect(w.state.freshness == .fresh)
        #expect(spy.reloads == reloadsAfterLoad,
                "the widget was reloaded for a change it cannot show")
    }

    /// The other half: a write that revives a widget which had gone dim. The
    /// percentages are identical, so the signature says "nothing new" — but
    /// the widget is dimmed and has to stop being dimmed.
    @Test("A write that only changes the freshness still reloads the widget")
    func reloadsWhenAWriteRevivesTheWidget() {
        let home = sandbox()
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now.addingTimeInterval(-7200),
                               fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        w.handleChange(reason: "test", force: true)
        #expect(w.state.freshness == .stale)
        let reloadsAfterLoad = spy.reloads

        // An hour later Claude Code writes again with the very same numbers.
        spy.now += 3600
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 10, week: 20, context: 9)
        w.handleChange(reason: "test", force: false)

        #expect(w.state.freshness == .fresh, "the snapshot is fresh again")
        #expect(spy.reloads == reloadsAfterLoad + 1,
                "and the widget is reloaded even though no percentage moved")
    }

    @Test("Refresh is a manual duplicate of the automatic path")
    func refreshButtonRereads() async {
        let home = sandbox()
        makeContainer(in: home)
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 10, week: 20, context: 9)

        let model = StatusModel(installer: installer(home: home, template: makeTemplate(in: home)),
                                watcher: watcher(spy, in: home))
        model.start()
        defer { model.stop() }
        #expect(await eventually { model.snapshot != nil })

        let readsAfterLaunch = spy.reads
        spy.now += 5
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 42, week: 43, context: 44)
        model.refresh()

        #expect(spy.reads == readsAfterLaunch + 1,
                "the button reaches the same read the file sources trigger")
        #expect(await eventually { model.snapshot?.context?.usedPercentage == 44 },
                "and the result arrives by the same route, not a second one")
    }

    /// The stubbed checks above prove the decisions. This one proves the
    /// plumbing: a real directory, a real file, a real `DispatchSource`, and
    /// the same inode swap the exporter performs. Nothing about the file
    /// sources is stubbed, because the bug they exist for — a source bound to
    /// an inode that no longer exists — cannot be reproduced without them.
    @Test("A real write on disk reaches the window", .timeLimit(.minutes(1)))
    func realFileChangeReachesTheModel() async throws {
        let home = sandbox()
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)

        func writeSnapshot(context: Int) throws {
            let body = """
            {"schemaVersion":1,"capturedAt":\(Int(Date().timeIntervalSince1970)),            "limits":{"fiveHour":{"usedPercentage":10,"resetsAt":\(Int(Date().timeIntervalSince1970) + 3600)},            "sevenDay":{"usedPercentage":20,"resetsAt":\(Int(Date().timeIntervalSince1970) + 86400)}},            "context":{"usedPercentage":\(context)}}
            """
            // The exporter writes to a temporary file and renames it over the
            // target, which swaps the inode. Do the same, or this checks a
            // case that never happens.
            let staging = exchange.appending(path: "snapshot.json.tmp")
            try body.write(to: staging, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(
                exchange.appending(path: "snapshot.json"), withItemAt: staging)
        }

        try writeSnapshot(context: 9)

        let reloads = Spy()
        let w = SnapshotWatcher(store: SnapshotStore(containerURL: exchange),
                                reloadWidgets: { reloads.reloads += 1 })
        let model = StatusModel(installer: installer(home: home, template: makeTemplate(in: home)),
                                watcher: w)
        model.start()
        defer { model.stop() }

        #expect(await eventually { model.snapshot?.context?.usedPercentage == 9 },
                "the snapshot present at launch reaches the window")

        // Twice, because the first replacement is what used to kill the file
        // source: it would report .rename once and then go silent forever.
        for value in [42, 77] {
            try writeSnapshot(context: value)
            #expect(await eventually(within: .seconds(10)) {
                model.snapshot?.context?.usedPercentage == value
            }, "write of \(value)% reaches the window")
        }
    }

    /// The defect the signature was too narrow to notice.
    ///
    /// Seen on the desktop: the window said "updated now" and both widgets
    /// beside it said "2 minutes ago". A message had gone out, the context had
    /// grown by a thousand tokens and stayed on 76 %, so none of the three
    /// percentages moved — and the widget went on counting the age from a
    /// snapshot two minutes old, because nothing had asked it to look again.
    ///
    /// A new snapshot always changes what the widget says, whatever the
    /// numbers do: it puts the age back to zero, and the timeline in the
    /// widget's hands cannot know that on its own.
    @Test("A new snapshot with the very same percentages still reloads")
    func newSnapshotWithUnchangedPercentagesReloads() {
        let home = sandbox()
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 13, week: 23, context: 76)

        let w = watcher(spy, in: home)
        w.handleChange(reason: "test", force: true)
        let reloadsAfterLoad = spy.reloads

        // Two minutes on, another write with identical numbers. The exporter
        // does this constantly: the status line redraws on every turn and the
        // percentages only move when a whole point is crossed.
        spy.now += 120
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 13, week: 23, context: 76)
        w.handleChange(reason: "test", force: false)

        #expect(spy.reloads == reloadsAfterLoad + 1,
                "the numbers were the same, so the widget kept an age two minutes out of date")
    }

    /// And the budget still holds. The moment in the signature means every
    /// write is a change, so the minute is now the only thing rationing
    /// reloads — it has to actually ration them.
    @Test("Writes inside the same minute still cost one reload between them")
    func repeatedWritesWithinAMinuteReloadOnce() {
        let home = sandbox()
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 13, week: 23, context: 76)

        let w = watcher(spy, in: home)
        w.handleChange(reason: "test", force: true)
        let reloadsAfterLoad = spy.reloads

        // Fifteen writes in two and a half minutes is what was measured of the
        // status line; here they are, ten seconds apart.
        for _ in 0..<15 {
            spy.now += 10
            spy.current = snapshot(capturedAt: spy.now, fiveHour: 13, week: 23, context: 76)
            w.handleChange(reason: "test", force: false)
        }

        #expect(spy.reloads == reloadsAfterLoad + 2,
                "two and a half minutes of writing bought \(spy.reloads - reloadsAfterLoad) reloads")
    }

    /// The write that lands after the last prompt.
    ///
    /// The budget window used to *drop* a change rather than postpone it, on the
    /// reasoning that the exporter's next write would wake the watcher again.
    /// That holds while somebody is working and fails exactly when it matters:
    /// the final write of a session has no successor, so the tile kept the
    /// previous snapshot until WidgetKit came round on its own — up to half an
    /// hour, at the moment a person stops and looks at the widget.
    ///
    /// Measured before it was fixed: one write inside the window, then three and
    /// a half minutes of an unchanged tile with the app running in the
    /// background. That is what this forbids.
    @Test("A change inside the budget window is postponed, not dropped")
    func aChangeInsideTheBudgetWindowIsPostponed() async {
        let home = sandbox()
        makeContainer(in: home)
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        let model = StatusModel(installer: installer(home: home, template: makeTemplate(in: home)),
                                watcher: w)
        model.start()
        defer { model.stop() }
        #expect(await eventually { spy.reloads >= 1 }, "the first read reloads")
        let afterFirst = spy.reloads

        // Half a minute later: inside the window, so nothing fires — and the
        // watcher says it will come back, with how long it means to wait.
        spy.now += 30
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 11, week: 21, context: 10)
        w.handleChange(reason: "test", force: false)

        #expect(spy.reloads == afterFirst, "still rationed, as before")
        #expect(spy.postponed.count == 1, "and something is owed")
        #expect(spy.postponed.first?.after == 30,
                "postponed by what is left of the window, not by the whole of it")

        // Nothing else happens — no second write, which is the whole point.
        spy.now += 30
        spy.firePostponed()
        #expect(spy.reloads == afterFirst + 1,
                "the postponed reload never came: the last write of a session was dropped")
    }

    /// A burst inside one window owes one reload, not one per write. Otherwise
    /// the fix for the dropped write would spend the budget it exists to
    /// protect.
    @Test("A burst inside one window owes exactly one reload")
    func aBurstOwesOneReload() async {
        let home = sandbox()
        makeContainer(in: home)
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        let model = StatusModel(installer: installer(home: home, template: makeTemplate(in: home)),
                                watcher: w)
        model.start()
        defer { model.stop() }
        #expect(await eventually { spy.reloads >= 1 })
        let afterFirst = spy.reloads

        for step in 1...5 {
            spy.now += 5
            spy.current = snapshot(capturedAt: spy.now, fiveHour: 10 + step, week: 20, context: 9)
            w.handleChange(reason: "burst \(step)", force: false)
        }
        #expect(spy.reloads == afterFirst, "none of the burst fired early")
        #expect(spy.postponed.count == 1, "five writes, one thing owed")

        spy.now += 60
        spy.firePostponed()
        #expect(spy.reloads == afterFirst + 1,
                "the burst owed one reload and produced \(spy.reloads - afterFirst)")
    }

    /// And a postponed reload does not fire after the watcher has been stopped.
    /// A window that closes, or an app quitting, must not reload the widget on
    /// its way out.
    @Test("Stopping cancels what the budget window postponed")
    func stoppingCancelsThePostponedReload() async {
        let home = sandbox()
        makeContainer(in: home)
        let spy = Spy()
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 10, week: 20, context: 9)

        let w = watcher(spy, in: home)
        w.start()
        #expect(await eventually { spy.reloads >= 1 })
        let afterFirst = spy.reloads

        spy.now += 10
        spy.current = snapshot(capturedAt: spy.now, fiveHour: 11, week: 20, context: 9)
        w.handleChange(reason: "test", force: false)
        #expect(spy.postponed.count == 1)

        w.stop()
        spy.now += 60
        spy.firePostponed()
        #expect(spy.reloads == afterFirst, "it reloaded after being stopped")
    }
}

/// What the log says about a reload, which is the only place a maintainer can
/// find out what the tile drew an hour ago.
///
/// Written after a question no log could answer: the owner closed one of two
/// editor windows, the five-hour row read "closed", and deciding whether one
/// caused the other needed to know whether that snapshot's window had already
/// expired. It had — the period reset at 18:30 and the row was right — but the
/// order of events had to be reconstructed from timestamps in Claude Code's own
/// prompt history, because `widget reload #22 (snapshot changed)` says nothing
/// about the snapshot.
@Suite("What a reload writes down")
struct ReloadDetailTests {

    private func snapshot(fiveHour: LimitWindow?, week: LimitWindow?,
                          context: Int? = 40,
                          capturedAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> Snapshot {
        Snapshot(
            schemaVersion: 1, capturedAt: capturedAt, sessionId: "abcd1234",
            claudeCodeVersion: "2.1.220", model: nil, project: nil,
            limits: Limits(fiveHour: fiveHour, sevenDay: week),
            context: context.map { ContextInfo(usedPercentage: $0, totalInputTokens: nil,
                                               windowSize: nil, cacheHitRatio: nil) },
            cost: nil
        )
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func open(_ percent: Int) -> LimitWindow {
        LimitWindow(usedPercentage: percent, resetsAt: now.addingTimeInterval(60))
    }
    private func expired(_ percent: Int) -> LimitWindow {
        LimitWindow(usedPercentage: percent, resetsAt: now.addingTimeInterval(-1))
    }

    private func detail(from previous: Snapshot?, to current: Snapshot) -> String {
        SnapshotWatcher.reloadDetail(
            from: previous.map(SnapshotWatcher.Signature.init(of:)),
            to: SnapshotWatcher.Signature(of: current),
            snapshot: current, at: now)
    }

    @Test("The first reload says so, rather than pretending nothing moved")
    func theFirstOneSaysFirst() {
        let s = snapshot(fiveHour: open(10), week: open(5))
        #expect(detail(from: nil, to: s) == "first snapshot · five-hour open · week open")
    }

    /// The case the question was about: an expired window is named as expired,
    /// so a reader an hour later knows the row said so because the period had
    /// ended and not because of anything they did.
    @Test("An expired window is named expired")
    func expiredWindowIsNamed() {
        let s = snapshot(fiveHour: expired(10), week: open(5))
        #expect(detail(from: nil, to: s) == "first snapshot · five-hour expired · week open")
    }

    @Test("A window that never arrived is named absent, which is not the same thing")
    func absentWindowIsNamed() {
        let s = snapshot(fiveHour: nil, week: nil)
        #expect(detail(from: nil, to: s) == "first snapshot · five-hour absent · week absent")
    }

    @Test("Each part that moves is named, in the order the tile draws them")
    func everyPartIsNamed() {
        let before = snapshot(fiveHour: open(10), week: open(5), context: 40)
        let after = snapshot(fiveHour: open(11), week: open(6), context: 41,
                             capturedAt: now.addingTimeInterval(30))
        #expect(detail(from: before, to: after)
                == "moved 5h,7d,context,moment · five-hour open · week open")
    }

    @Test("Only what moved is named")
    func onlyWhatMovedIsNamed() {
        let before = snapshot(fiveHour: open(10), week: open(5), context: 40)
        let after = snapshot(fiveHour: open(10), week: open(5), context: 41)
        #expect(detail(from: before, to: after) == "moved context · five-hour open · week open")
    }

    /// A reload with nothing moved is not a contradiction: crossing a freshness
    /// threshold reloads the tile because it draws itself dimmer, and the log
    /// has to be able to say that the numbers stood still.
    @Test("Standing still is a thing the log can say")
    func nothingMovedIsSayable() {
        let s = snapshot(fiveHour: open(10), week: open(5))
        #expect(detail(from: s, to: s) == "moved nothing · five-hour open · week open")
    }

    /// A field going missing is movement. It was, briefly, invisible: a
    /// signature built by joining descriptions turned both `nil` and a real
    /// value into text, and the placeholder for absence was a string like any
    /// other, so this worked by luck rather than by construction.
    @Test("A percentage disappearing counts as movement")
    func disappearanceIsMovement() {
        let before = snapshot(fiveHour: open(10), week: open(5), context: 40)
        let after = snapshot(fiveHour: open(10), week: open(5), context: nil)
        #expect(detail(from: before, to: after) == "moved context · five-hour open · week open")
    }
}

/// A reading that goes backwards, which the log now names.
///
/// Measured on this machine's own history: 522 rows, 13 steps backwards inside
/// one weekly window, the largest 27 % → 24 % six minutes apart. Consumption
/// cannot fall before a reset, so those rows carry a reading older than the one
/// before them — and until now nothing said so.
@Suite("An older reading is named")
struct OlderReadingTests {

    private let reset = Date(timeIntervalSince1970: 2_000_000)
    private func window(_ percent: Int, resetsAt: Date? = nil) -> LimitWindow {
        LimitWindow(usedPercentage: percent, resetsAt: resetsAt ?? reset)
    }
    private func limits(_ fiveHour: LimitWindow?, _ week: LimitWindow?) -> Limits {
        Limits(fiveHour: fiveHour, sevenDay: week)
    }

    @Test("A percentage that fell inside one window is named")
    func fallInsideOneWindowIsNamed() {
        let before = limits(window(30), window(27))
        let after = limits(window(30), window(24))
        #expect(SnapshotWatcher.olderReadings(previous: before, current: after) == ["7d"])
    }

    @Test("Both windows can go back at once")
    func bothCanGoBack() {
        #expect(SnapshotWatcher.olderReadings(previous: limits(window(30), window(27)),
                                              current: limits(window(29), window(24)))
                == ["5h", "7d"])
    }

    @Test("Growing is not an older reading")
    func growthIsNotNamed() {
        #expect(SnapshotWatcher.olderReadings(previous: limits(window(30), window(27)),
                                              current: limits(window(31), window(28))).isEmpty)
    }

    /// The case that would make this cry wolf every five hours. After a reset
    /// the percentage is supposed to fall, which is why the comparison is per
    /// window rather than per number.
    @Test("A reset is not an older reading")
    func resetIsNotNamed() {
        let before = limits(window(90), window(27))
        let after = limits(window(0, resetsAt: reset.addingTimeInterval(18_000)), window(27))
        #expect(SnapshotWatcher.olderReadings(previous: before, current: after).isEmpty)
    }

    @Test("With nothing to compare against, nothing is claimed")
    func firstSnapshotClaimsNothing() {
        #expect(SnapshotWatcher.olderReadings(previous: nil,
                                              current: limits(window(30), window(27))).isEmpty)
    }

    @Test("A window that arrives or disappears is not an older reading")
    func appearanceIsNotNamed() {
        #expect(SnapshotWatcher.olderReadings(previous: limits(nil, window(27)),
                                              current: limits(window(30), nil)).isEmpty)
    }
}
