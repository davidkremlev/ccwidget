import Foundation
import WidgetKit

/// Section 2.4: watches the snapshot and triggers widget reloads.
///
/// Two things, without which the watcher fires exactly once:
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
@MainActor
final class SnapshotWatcher: ObservableObject {
    /// Minimum gap between reloads. Less is wasteful; more puts a noticeable
    /// delay between doing the work and seeing the widget catch up.
    static let minimumReloadInterval: TimeInterval = 60
    /// The exporter writes the snapshot and the history back to back; wait
    /// for the dust to settle.
    static let debounce: TimeInterval = 2

    @Published private(set) var lastReload: Date?
    @Published private(set) var reloadCount = 0
    @Published private(set) var freshness: Freshness?
    @Published private(set) var isRunning = false

    private let store: SnapshotStore
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var directoryDescriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?
    private var freshnessTimer: Timer?
    private var lastSignature: String?

    init(store: SnapshotStore = .default()) {
        self.store = store
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        watchDirectory()
        watchFile()
        startFreshnessTimer()

        // Reload on app launch. Beyond the obvious — showing fresh numbers
        // right away — it covers the case where the widget sat on a stale
        // timeline the whole time the app was closed.
        reload(reason: "app launch", force: true)
    }

    func stop() {
        debounceTask?.cancel()
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        fileSource?.cancel()
        directorySource?.cancel()
        fileSource = nil
        directorySource = nil
        isRunning = false
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
            self.reload(reason: reason, force: false)
        }
    }

    // MARK: Reloading

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

    private func reload(reason: String, force: Bool) {
        let snapshot = try? store.load()
        if let snapshot {
            freshness = Freshness(age: snapshot.age())
        }

        if !force {
            guard let snapshot else { return }
            let current = signature(of: snapshot)
            guard current != lastSignature else { return }

            if let lastReload, Date().timeIntervalSince(lastReload) < Self.minimumReloadInterval {
                // New numbers, but the budget has to last: do not fire early.
                // The exporter's next write will wake us again.
                ccwidgetStoreLog.debug("watcher: reload deferred, budget window")
                return
            }
            lastSignature = current
        } else if let snapshot {
            lastSignature = signature(of: snapshot)
        }

        WidgetCenter.shared.reloadAllTimelines()
        lastReload = Date()
        reloadCount += 1
        ccwidgetStoreLog.notice(
            "widget reload #\(self.reloadCount, privacy: .public) (\(reason, privacy: .public))"
        )
    }

    // MARK: Freshness

    /// Recompute the age once a minute. Crossing a threshold from section
    /// 2.4 changes how the widget looks, so it has to be shown without
    /// waiting for new data — otherwise going stale passes unnoticed.
    private func startFreshnessTimer() {
        freshnessTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFreshness() }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
    }

    private func refreshFreshness() {
        guard let snapshot = try? store.load() else { return }
        let updated = Freshness(age: snapshot.age())
        guard updated != freshness else { return }
        ccwidgetStoreLog.notice(
            "freshness changed to \(String(describing: updated), privacy: .public)"
        )
        freshness = updated
        WidgetCenter.shared.reloadAllTimelines()
        lastReload = Date()
        reloadCount += 1
    }
}
