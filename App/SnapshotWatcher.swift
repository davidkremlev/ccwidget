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
    /// Minimum gap between widget reloads. Less is wasteful; more puts a
    /// noticeable delay between doing the work and seeing the widget catch up.
    static let minimumReloadInterval: TimeInterval = 60
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

    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var directoryDescriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?
    private var tickTimer: Timer?
    private var lastSignature: String?

    init(
        store: SnapshotStore = .default(),
        read: (() throws -> Snapshot)? = nil,
        reloadWidgets: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
        clock: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.read = read ?? { try store.load() }
        self.reloadWidgets = reloadWidgets
        self.clock = clock
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
    private func signature(of snapshot: Snapshot) -> String {
        [
            snapshot.limits.fiveHour?.usedPercentage.description ?? "-",
            snapshot.limits.sevenDay?.usedPercentage.description ?? "-",
            snapshot.context?.usedPercentage?.description ?? "-",
        ].joined(separator: "|")
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
        let current = signature(of: snapshot)

        if !force {
            // Either reason is enough. The numbers are the obvious one; the
            // freshness matters because it changes how the widget draws itself
            // — a stale snapshot is dimmed — and a write that revives a dimmed
            // widget without changing a single percentage would otherwise
            // leave it dimmed until the next time a number moved.
            guard current != lastSignature || state.freshness != wasFresh else { return }
            if let last = state.lastReload,
               state.now.timeIntervalSince(last) < Self.minimumReloadInterval {
                // New numbers, but the budget has to last: do not fire early.
                // The exporter's next write will wake us again.
                ccwidgetStoreLog.debug("watcher: reload deferred, budget window")
                return
            }
        }

        lastSignature = current
        reloadWidgets()
        state.lastReload = state.now
        state.reloadCount += 1
        ccwidgetStoreLog.notice(
            "widget reload #\(self.state.reloadCount, privacy: .public) (\(reason, privacy: .public))"
        )
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
