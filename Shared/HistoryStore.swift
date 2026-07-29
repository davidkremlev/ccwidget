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

/// Чтение и усечение `history.jsonl`.
///
/// Формат намеренно построчный: экспортёр только дописывает, а виджет
/// обязан читать быстро и не бояться оборванной последней строки.
public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(store: SnapshotStore) {
        self.url = store.historyURL
    }

    /// Раздел 7: не более 2000 строк, при превышении оставляем последние 1000.
    public static let maxLines = 2000
    public static let keepLines = 1000

    /// Разбирает историю. Битая строка пропускается, но не молча —
    /// правило раздела 6.1 действует и здесь.
    public func load() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var entries: [HistoryEntry] = []
        var skipped = 0

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8) else { skipped += 1; continue }
            guard let raw = try? JSONDecoder().decode(RawEntry.self, from: data) else {
                skipped += 1
                ccgaugeParseLog.error(
                    "history line dropped; raw=\(line.prefix(120), privacy: .public)"
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
            ccgaugeParseLog.error("history: \(skipped, privacy: .public) line(s) unreadable")
        }
        return entries.sorted { $0.time < $1.time }
    }

    /// Усечение. Выполняет приложение, а не виджет: виджет только читает.
    @discardableResult
    public func truncateIfNeeded() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > Self.maxLines else { return 0 }

        let removed = lines.count - Self.keepLines
        let kept = lines.suffix(Self.keepLines).joined(separator: "\n") + "\n"

        // Через временный файл: усечение не должно застать экспортёр врасплох.
        let tmp = url.deletingLastPathComponent().appending(path: "history.jsonl.tmp")
        do {
            try kept.write(to: tmp, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            ccgaugeStoreLog.notice("history truncated, dropped \(removed, privacy: .public) line(s)")
            return removed
        } catch {
            ccgaugeStoreLog.error("history truncation failed: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: tmp)
            return 0
        }
    }

    private struct RawEntry: Decodable {
        let t: Double
        let sevenDay: Double
        let resetsAt: Double?
    }
}
