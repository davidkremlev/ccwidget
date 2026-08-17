import Foundation
import WidgetKit

/// Everything the window needs to know about the outside world, published as
/// one value.
///
/// One publisher rather than six is not tidiness. `@Published` delivers the new
/// value through `objectWillChange`, before the property itself is updated, so
/// a subscriber that reacts to one field and then reads its neighbours reads
/// them as they were a moment ago. A single value cannot disagree with itself.
struct WatcherState {
    /// The snapshot as last read from disk. The window draws this rather than
    /// reading the file for itself.
    var snapshot: Snapshot?
    var freshness: Freshness?
    var isRunning = false
    var lastReload: Date?
    var reloadCount = 0
    /// Advances on a timer so that anything showing an age — "updated 3 minutes
    /// ago" — re-renders. Nothing is read from disk to move it.
    var now = Date()
}

/// Section 2.4: watches the snapshot, publishes it, and triggers widget
/// reloads.
///
/// Three things, without which the watcher fires exactly once, shows stale
/// numbers, or burns the reload budget:
///
/// 1. **The exporter writes through `os.replace`**, so the inode is swapped.
///    A source bound to the old descriptor gets `.rename`/`.delete` on the
///    first write and never fires again. Hence the descriptor is reopened,
///    and the directory is watched separately for the case where the file
///    does not exist yet.
/// 2. **The WidgetKit budget.** The status line redraws dozens of times a
///    minute, and reloading the widget on every write would burn through the
///    budget within hours (section 2.3). A reload happens only when the
///    numbers themselves changed and at least a minute has passed.
/// 3. **The budget applies to the widget, not to the window.** The window is
///    on screen because the user opened it, and it costs nothing to redraw.
///    So the snapshot is published on every change, and only the widget reload
///    is rationed. Keeping the two on the same throttle is what once left the
///    window claiming the data was twenty-one minutes old while the widget
///    beside it showed numbers from two seconds ago.
@MainActor
final class SnapshotWatcher: ObservableObject {
    /// Minimum gap between widget reloads **while the app is in the
    /// foreground**, where the documentation says they are free.
    ///
    /// Less is wasteful; more puts a noticeable delay between doing the work and
    /// seeing the widget catch up.
    static let minimumReloadInterval: TimeInterval = 60

    /// And the gap when it is not, where they are not free.
    ///
    /// **Why there have to be two.** Apple's page — cached as
    /// `apple/widgetkit-keeping-up-to-date.md`, quoted in `SPEC` 2.3 — gives a
    /// daily budget of 40 to 70 reloads for a widget somebody looks at often,
    /// and exempts the case where "the widget's containing app is in the
    /// foreground". Section 2.3 leant on that exemption with an argument that
    /// was true when it was written and false the day background updates
    /// shipped: the watcher used to live in the window, so a closed window meant
    /// a silent watcher and no reloads to pay for. It now lives in the app, and
    /// the app can run all day with nothing on screen.
    ///
    /// Measured on the owner's machine within an hour of that shipping: reloads
    /// #22 through #27, one a minute, `reload budget elapsed` each time, the app
    /// not in front. Sixty an hour against a budget of forty to seventy a day
    /// spends the whole day's allowance before lunch — and the symptom is the
    /// tile freezing until the budget rolls over, which `SPEC` 2.3 describes and
    /// nothing in the code reports, because the system refuses in silence.
    ///
    /// Fifteen minutes is four an hour at worst, and in practice fewer, because
    /// in the background a reload also has to be *worth* something — see
    /// `visibleChange`.
    static let backgroundReloadInterval: TimeInterval = 15 * 60
    /// The exporter writes the snapshot and the history back to back; wait
    /// for the dust to settle.
    static let debounce: TimeInterval = 2
    /// How often the age is recomputed. The tick reads nothing, so the only
    /// thing this has to do is land on every minute boundary — that is when
    /// the age can change, and the widget beside the window changes there
    /// exactly. Thirty seconds divides sixty, so every other tick is a minute
    /// boundary; `theTickGridContainsTheMinute` holds that.
    nonisolated static let tickInterval: TimeInterval = 30

    @Published private(set) var state = WatcherState()

    private let store: SnapshotStore
    /// Reading and reloading arrive from outside so the checks can count them:
    /// the claim that the age ticks without touching the disk is only worth
    /// something if something is watching the disk. Section 5.2.
    private let read: () throws -> Snapshot
    private let reloadWidgets: () -> Void
    /// Freshness is a function of the clock alone, so the clock has to be
    /// something a check can move. Waiting five real minutes to watch a
    /// threshold get crossed is not a check, it is a hope.
    private let clock: () -> Date
    /// Doing something later, from outside.
    ///
    /// The clock is injected because freshness is a function of it, and this is
    /// injected for the same reason one step further: a reload the budget window
    /// postponed happens *later*, and a check that waits fifty-five real seconds
    /// for it is a hope rather than a check. The live one sleeps; a check fires
    /// it when it chooses and can say what delay was asked for.
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    /// Whether the app is in front, which decides what a reload costs.
    ///
    /// Injected rather than read from `NSApp` where it is needed, for the usual
    /// reason: a check cannot bring the app to the front, and a regime nothing
    /// can put into a state is a regime nothing can test.
    ///
    /// `NSApplication.isActive` and not "is a window open": the exemption in the
    /// documentation is about the app being in the foreground, and a window
    /// behind somebody's terminal is not that.
    private let isForeground: () -> Bool

    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var directoryDescriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?
    /// Whether the budget window postponed a reload that something has to come
    /// back for. See `handleChange`.
    private var reloadIsOwed = false
    private var tickTimer: Timer?
    private var lastSignature: Signature?
    /// The windows the last reload drew, kept only so that a reading which goes
    /// backwards can be named. See `olderReadings`.
    private var lastLimits: Limits?

    init(
        store: SnapshotStore = .default(),
        read: (() throws -> Snapshot)? = nil,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        clock: @escaping () -> Date = { Date() },
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { seconds, work in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                work()
            }
        },
        // Defaults to the budgeted regime rather than to `NSApp.isActive`.
        // Reaching for `NSApplication` from in here broke this project's own
        // rule — dependencies are injected, not computed — and it broke it
        // expensively: the window's `onAppear` calls `refresh()`, so rendering
        // the window inside a check touched `NSApplication.shared`, which in a
        // process with no GUI session blocks in `open()`. A suite that used to
        // take eighty seconds ran past ten minutes.
        //
        // False is also the right default on its own merits: it is the regime
        // that spends budget, so anything that forgets to say where it is
        // errs towards spending less rather than towards burning a day's
        // allowance before lunch.
        isForeground: @escaping () -> Bool = { false }
    ) {
        self.store = store
        self.read = read ?? { try store.load() }
        self.reloadWidgets = reloadWidgets
        self.clock = clock
        self.schedule = schedule
        self.isForeground = isForeground
        self.state = WatcherState(now: clock())
    }

    // MARK: Lifecycle

    func start() {
        guard !state.isRunning else { return }
        state.isRunning = true

        watchDirectory()
        watchFile()
        startTicking()

        // Reload on app launch. Beyond the obvious — showing fresh numbers
        // right away — it covers the case where the widget sat on a stale
        // timeline the whole time the app was closed.
        handleChange(reason: "app launch", force: true)
    }

    func stop() {
        reloadIsOwed = false
        debounceTask?.cancel()
        tickTimer?.invalidate()
        tickTimer = nil
        fileSource?.cancel()
        directorySource?.cancel()
        fileSource = nil
        directorySource = nil
        state.isRunning = false
    }

    // MARK: Watching

    /// The directory survives the file being replaced and catches a snapshot
    /// that does not exist yet.
    private func watchDirectory() {
        directorySource?.cancel()
        directoryDescriptor = open(store.containerURL.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            ccwidgetStoreLog.error(
                "watcher: cannot open directory \(self.store.containerURL.path, privacy: .private)"
            )
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        let descriptor = directoryDescriptor
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleCheck(reason: "directory changed") }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    /// A descriptor on the file itself: write events without scanning the
    /// directory.
    private func watchFile() {
        fileSource?.cancel()
        fileDescriptor = open(store.snapshotURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        let descriptor = fileDescriptor
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let data = source.data
                // The inode was swapped: this descriptor no longer points at
                // the snapshot.
                if data.contains(.delete) || data.contains(.rename) {
                    self.watchFile()
                }
                self.scheduleCheck(reason: "snapshot changed")
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileSource = source
    }

    private func scheduleCheck(reason: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.debounce))
            guard !Task.isCancelled else { return }
            if self.fileSource == nil { self.watchFile() }
            self.handleChange(reason: reason, force: false)
        }
    }

    // MARK: Reading and reloading

    /// The numbers whose change actually gives the widget something new to
    /// show. The snapshot's age is deliberately left out: it changes every
    /// second and the pre-generated timeline draws it without our help.
    /// What counts as the widget having something new to draw.
    ///
    /// The three percentages, and **when the snapshot was taken**. The moment
    /// was left out at first on the reasoning that the age ticks by itself,
    /// drawn by a pre-generated timeline without the daemon — which is true of
    /// the age *growing* and false of the age being *reset*. A new snapshot
    /// puts it back to zero, the timeline in the widget's hands cannot know
    /// that, and it goes on counting from the moment it was built.
    ///
    /// Seen: the window said "updated now" while both widgets beside it said
    /// "2 minutes ago". A message had been sent, the context had grown by a
    /// thousand tokens and stayed on 76 %, so not one of the three percentages
    /// moved and nothing asked the widget to look again.
    ///
    /// A type rather than the joined string it used to be. The string answered
    /// "is this different" and nothing else, so when the log needed to say
    /// *what* had changed the only way to get it was to split the string back
    /// apart and hope the pieces still lined up with their names. A value that
    /// can be asked a question does not need parsing back.
    struct Signature: Equatable {
        var fiveHour: Int?
        var sevenDay: Int?
        var context: Int?
        var capturedAt: Date

        init(of snapshot: Snapshot) {
            fiveHour = snapshot.limits.fiveHour?.usedPercentage
            sevenDay = snapshot.limits.sevenDay?.usedPercentage
            context = snapshot.context?.usedPercentage
            capturedAt = snapshot.capturedAt
        }

        /// Whether any of the three percentages moved — that is, whether the
        /// tile would draw a different *number*.
        ///
        /// The moment is left out on purpose, and that is the whole distinction
        /// this type exists to make. A write that only moves the moment changes
        /// the age the tile reports, which matters when reloads are free and is
        /// not worth a day's budget when they are not.
        func numbersMoved(from previous: Signature) -> Bool {
            fiveHour != previous.fiveHour
                || sevenDay != previous.sevenDay
                || context != previous.context
        }

        /// What moved, named in the order the tile draws it.
        ///
        /// "nothing" is a real answer, not a placeholder: a reload also happens
        /// when freshness crosses a threshold, and then the log should say the
        /// numbers stood still rather than leave the reader to assume they did
        /// not.
        func changes(from previous: Signature) -> [String] {
            var moved: [String] = []
            if fiveHour != previous.fiveHour { moved.append("5h") }
            if sevenDay != previous.sevenDay { moved.append("7d") }
            if context != previous.context { moved.append("context") }
            if capturedAt != previous.capturedAt { moved.append("moment") }
            return moved
        }
    }

    /// Which windows came back with a *lower* percentage than the one already
    /// drawn, inside the same window.
    ///
    /// Consumption cannot go down before a reset, so this can only mean the
    /// snapshot carries an older reading than the one before it — the limits
    /// arrive with a model's reply and sit in the session until the next one, so
    /// whichever session renders a status line writes the reading *it* last saw,
    /// which need not be the newest one. A fresh `capturedAt` is no promise of
    /// fresh limits.
    ///
    /// **Measured, and this is why it is here.** 522 rows of this machine's own
    /// history hold 13 steps backwards inside one weekly window, the largest
    /// 27 % → 24 % six minutes later on 7 August. Not rounding: `used_percentage`
    /// can be fractional, but consistent rounding cannot lose three points.
    ///
    /// Nothing is discarded on the strength of it. The forecast fits a weighted
    /// regression and gates on how well the line describes the points, so an
    /// older reading costs confidence rather than producing a confident wrong
    /// answer — section 7. What it must not do is pass unmentioned.
    ///
    /// A different `resetsAt` is not this: after a reset the percentage is
    /// *supposed* to fall, which is why the comparison is per window and not
    /// per number.
    nonisolated static func olderReadings(previous: Limits?, current: Limits) -> [String] {
        func wentBack(_ was: LimitWindow?, _ now: LimitWindow?) -> Bool {
            guard let was, let now, was.resetsAt == now.resetsAt else { return false }
            return now.usedPercentage < was.usedPercentage
        }
        guard let previous else { return [] }
        var names: [String] = []
        if wentBack(previous.fiveHour, current.fiveHour) { names.append("5h") }
        if wentBack(previous.sevenDay, current.sevenDay) { names.append("7d") }
        return names
    }

    /// What the log says about a reload besides the fact that one happened.
    ///
    /// It used to say the count and the reason, and on 17 August the question
    /// was whether the five-hour window was already expired in the snapshot the
    /// tile had at 18:31 — the owner had closed one of two editor windows and
    /// the row read as being about that. No log answered it, and the order of
    /// events had to be reconstructed from timestamps in Claude Code's own
    /// prompt history. What the tile drew belongs in the log; `ccwidget-replay`
    /// and this line are the same kind of surface as the screen.
    ///
    /// The numbers stay out of it. Percentages are raw field values, this
    /// project keeps those `.private`, and a `.private` value read back without
    /// a logging profile is redacted — so a line built from them would answer
    /// nothing. What is public is what the row *draws*: which of the four parts
    /// moved, and whether each window had expired by then.
    nonisolated static func reloadDetail(from previous: Signature?, to current: Signature,
                                         snapshot: Snapshot, at now: Date) -> String {
        func standing(_ name: String, _ window: LimitWindow?) -> String {
            guard let window else { return "\(name) absent" }
            return window.hasClosed(at: now) ? "\(name) expired" : "\(name) open"
        }

        let movement: String
        if let previous {
            let moved = current.changes(from: previous)
            movement = "moved \(moved.isEmpty ? "nothing" : moved.joined(separator: ","))"
        } else {
            movement = "first snapshot"
        }
        return [movement,
                standing("five-hour", snapshot.limits.fiveHour),
                standing("week", snapshot.limits.sevenDay)].joined(separator: " · ")
    }

    /// The single point where the snapshot is read. Reachable from the file
    /// sources, from `start()`, and from the window's Refresh button, which is
    /// a manual duplicate of what the sources do on their own.
    func handleChange(reason: String, force: Bool) {
        let snapshot = try? read()
        let wasFresh = state.freshness

        // Publishing comes first and unconditionally. Whether the widget is
        // due a reload is a separate question with a separate answer, and the
        // window must not be held hostage to it.
        state.now = clock()
        state.snapshot = snapshot
        if let snapshot {
            state.freshness = Freshness(of: snapshot, at: state.now)
        }

        guard let snapshot else { return }
        let current = Signature(of: snapshot)

        let inFront = isForeground()

        if !force {
            // **What counts as worth a reload depends on what one costs.**
            //
            // In front, the documentation says reloads are free, so anything
            // that changes what the tile would draw is enough — including the
            // moment, because a new snapshot puts the reported age back to zero
            // and the timeline already in the widget's hands cannot know that.
            //
            // Not in front, they come out of a budget of forty to seventy a day.
            // The moment alone is then not worth one: what the tile would draw
            // differently is a clock time in its footer, and paying a day's
            // allowance for that buys a frozen tile by lunchtime. So the numbers
            // have to have moved, or freshness has to have crossed a threshold —
            // the latter because a stale snapshot is *drawn* differently, dimmed,
            // and a write that revives a dimmed widget has to get through.
            let freshnessMoved = state.freshness != wasFresh
            let worthIt: Bool
            if let last = lastSignature {
                worthIt = inFront
                    ? (current != last || freshnessMoved)
                    : (current.numbersMoved(from: last) || freshnessMoved)
            } else {
                worthIt = true
            }
            guard worthIt else { return }
            let ration = inFront ? Self.minimumReloadInterval : Self.backgroundReloadInterval
            if let last = state.lastReload {
                let waited = state.now.timeIntervalSince(last)
                if waited < ration {
                    // New numbers, and the budget says not yet. **Postponed,
                    // not dropped** — and the difference is the last write of a
                    // session.
                    //
                    // This used to return here, on the reasoning that "the
                    // exporter's next write will wake us again". True while
                    // somebody is working, and false exactly when it matters:
                    // the write that lands after the final prompt has no
                    // successor, so it was thrown away and the tile kept the
                    // previous snapshot until WidgetKit came round on its own —
                    // up to half an hour, at the moment a person stops working
                    // and looks at the widget. Measured on 17 August: a single
                    // write inside the window, then three and a half minutes of
                    // an unchanged tile with the app running.
                    scheduleOwedReload(in: ration - waited)
                    return
                }
            }
        }

        var detail = Self.reloadDetail(from: lastSignature, to: current,
                                       snapshot: snapshot, at: state.now)
        // Which regime paid for it. Without this the two are indistinguishable
        // in the one place a maintainer can look, and "the budget ran out" and
        // "the watcher stopped" read the same.
        detail += inFront ? " · in front, free" : " · in background, budgeted"
        let older = Self.olderReadings(previous: lastLimits, current: snapshot.limits)
        if !older.isEmpty {
            detail += " · older reading: \(older.joined(separator: ","))"
        }
        lastSignature = current
        lastLimits = snapshot.limits
        reloadWidgets()
        state.lastReload = state.now
        state.reloadCount += 1
        ccwidgetStoreLog.notice(
            """
            widget reload #\(self.state.reloadCount, privacy: .public) \
            (\(reason, privacy: .public)) \(detail, privacy: .public)
            """
        )
    }

    /// Comes back when the budget window closes and does the reload the window
    /// postponed.
    ///
    /// One task at a time: a burst of writes inside one window owes exactly one
    /// reload, not one per write. Re-reads the snapshot when it fires rather
    /// than remembering the one that was current — by then it may not be.
    private func scheduleOwedReload(in seconds: TimeInterval) {
        guard !reloadIsOwed else { return }
        reloadIsOwed = true
        ccwidgetStoreLog.debug(
            "watcher: reload postponed \(Int(seconds), privacy: .public)s by the budget window"
        )
        schedule(seconds) { [weak self] in
            guard let self, self.reloadIsOwed, self.state.isRunning else { return }
            self.reloadIsOwed = false
            self.handleChange(reason: "reload budget elapsed", force: false)
        }
    }

    // MARK: Ticking

    /// When the tick after `moment` is due.
    ///
    /// Its own function because the phase is the point and a phase is not
    /// visible in a `Timer`. Ticking every thirty seconds from whenever the
    /// window opened leaves the age changing up to thirty seconds after the
    /// widget's does; ticking on the grid leaves it changing with it.
    nonisolated static func nextTick(after moment: Date) -> Date {
        AgeClock.boundary(after: moment, every: tickInterval)
    }

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.fireDate = Self.nextTick(after: clock())
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    /// Moves the clock forward and recomputes what depends on it. **Nothing is
    /// read here.** The snapshot in hand is current because the file sources
    /// fire on every write; re-reading it once a minute to discover that it
    /// has not changed would be work done to learn nothing.
    ///
    /// Crossing a freshness threshold from section 2.4 does change how the
    /// widget looks, so that still costs a reload — but only on the crossing,
    /// not on every tick.
    func tick() {
        state.now = clock()
        guard let snapshot = state.snapshot else { return }

        let updated = Freshness(of: snapshot, at: state.now)
        guard updated != state.freshness else { return }

        ccwidgetStoreLog.notice(
            "freshness changed to \(String(describing: updated), privacy: .public)"
        )
        state.freshness = updated
        reloadWidgets()
        state.lastReload = state.now
        state.reloadCount += 1
    }
}
