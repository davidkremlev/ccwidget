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
            clock: { spy.now }
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
}
