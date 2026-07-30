import Foundation

public struct HistoryEntry: Sendable, Equatable {
    public let time: Date
    public let sevenDayUsed: Int
    public let resetsAt: Date?

    public init(time: Date, sevenDayUsed: Int, resetsAt: Date?) {
        self.time = time
        self.sevenDayUsed = sevenDayUsed
        self.resetsAt = resetsAt
    }
}

/// Reads and truncates `history.jsonl`.
///
/// The line-per-record format is deliberate: the exporter only ever appends,
/// and the widget has to read quickly and survive a truncated last line.
public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(store: SnapshotStore) {
        self.url = store.historyURL
    }

    /// Section 7: at most 2000 lines; past that, keep the last 1000.
    public static let maxLines = 2000
    public static let keepLines = 1000

    /// Parses the history. A broken line is skipped, but never quietly — the
    /// rule from section 6.1 applies here too.
    public func load() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var entries: [HistoryEntry] = []
        var skipped = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { skipped += 1; continue }
            guard let raw = try? JSONDecoder().decode(RawEntry.self, from: data) else {
                skipped += 1
                ccwidgetParseLog.error(
                    "history line dropped; raw=\(line.prefix(120), privacy: .private)"
                )
                continue
            }
            entries.append(
                HistoryEntry(
                    time: Date(timeIntervalSince1970: raw.t),
                    sevenDayUsed: Int(raw.sevenDay.rounded()),
                    resetsAt: raw.resetsAt.map { Date(timeIntervalSince1970: $0) }
                )
            )
        }

        if skipped > 0 {
            ccwidgetParseLog.error("history: \(skipped, privacy: .public) line(s) unreadable")
        }
        return entries.sorted { $0.time < $1.time }
    }

    /// Truncation. Done by the app, never the widget: the widget only reads.
    @discardableResult
    public func truncateIfNeeded() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > Self.maxLines else { return 0 }

        let removed = lines.count - Self.keepLines
        let kept = lines.suffix(Self.keepLines).joined(separator: "\n") + "\n"

        // Through a temporary file, so truncation never catches the exporter
        // mid-write. Opened with O_NOFOLLOW and O_EXCL: without them a planted
        // symlink turns truncation into overwriting somebody else's file.
        let tmp = url.deletingLastPathComponent().appending(path: "history.jsonl.tmp")
        do {
            guard try writeExclusively(kept, to: tmp) else { return 0 }
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            ccwidgetStoreLog.notice("history truncated, dropped \(removed, privacy: .public) line(s)")
            return removed
        } catch {
            ccwidgetStoreLog.error("history truncation failed: \(error.localizedDescription, privacy: .private)")
            try? FileManager.default.removeItem(at: tmp)
            return 0
        }
    }

    /// Creates the file, refusing to follow a symlink.
    private func writeExclusively(_ text: String, to url: URL) throws -> Bool {
        let path = url.path(percentEncoded: false)
        // unlink removes the link itself, not what it points at.
        try? FileManager.default.removeItem(at: url)
        let descriptor = path.withCString { pointer in
            Darwin.open(pointer, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        }
        guard descriptor >= 0 else {
            ccwidgetStoreLog.error("history truncation: refusing to write through a link")
            return false
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        return true
    }

    private struct RawEntry: Decodable {
        let t: Double
        let sevenDay: Double
        let resetsAt: Double?
    }
}
