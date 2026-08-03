import Foundation

// Replays a history.jsonl through the estimate, one line at a time, and
// reports what the widget would have shown and for how long.
//
// It exists because the figures in Docs/estimate-review.md were produced by a
// script that was never committed, which made a published table impossible to
// re-derive. The estimate is the one part of this widget that can be
// confidently wrong, and a measurement of it that nobody can repeat is worth
// about as much as an opinion.
//
//   ./.build/ccwidget-replay ~/path/to/history.jsonl
//
// The file holds nothing but timestamps, percentages and reset times, so a
// history from somebody else can be replayed here without carrying anything
// about them or their work.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count > 1 else {
    fail("usage: ccwidget-replay <path to history.jsonl>")
}
let path = (CommandLine.arguments[1] as NSString).expandingTildeInPath
let entries = HistoryStore(url: URL(filePath: path)).load()
guard !entries.isEmpty else { fail("no readable lines in \(path)") }

// Windows in the order they appear. A reset drops the percentage in one step,
// so each one is replayed on its own — as the estimate itself does.
var windows: [Date] = []
for entry in entries {
    if let resets = entry.resetsAt, !windows.contains(resets) { windows.append(resets) }
}

struct Held {
    let at: Date
    let outcome: Forecast.Outcome
    let gate: Forecast.Gate
    let fitQuality: Double?
    let seconds: TimeInterval
}

var timeline: [Held] = []
var qualities: [Double] = []
var resets: [Date] = []

for (index, window) in windows.enumerated() {
    let points = entries.filter { $0.resetsAt == window }
    guard let last = points.last else { continue }
    // A verdict stays on screen until the next line is written; the last one
    // of a window stays until the first line of the next.
    let endsAt = index + 1 < windows.count
        ? (entries.first { $0.resetsAt == windows[index + 1] }?.time ?? last.time)
        : last.time
    if index > 0 { resets.append(points[0].time) }

    for k in 1...points.count {
        let newest = points[k - 1]
        let forecast = Forecast.make(
            history: Array(points.prefix(k)),
            window: LimitWindow(usedPercentage: newest.sevenDayUsed, resetsAt: window),
            now: newest.time)
        let until = k < points.count ? points[k].time : endsAt
        timeline.append(Held(at: newest.time, outcome: forecast.outcome, gate: forecast.gate,
                             fitQuality: forecast.fitQuality,
                             seconds: max(0, until.timeIntervalSince(newest.time))))
        if let quality = forecast.fitQuality { qualities.append(quality) }
    }
}

let total = timeline.reduce(0) { $0 + $1.seconds }
let span = (entries.last!.time.timeIntervalSince(entries.first!.time)) / 3600

func hours(_ seconds: TimeInterval) -> String { String(format: "%.1f h", seconds / 3600) }

print("File:    \(path)")
print(String(format: "History: %d lines, %d window(s), %.1f h", entries.count, windows.count, span))
print("")

print("What the widget showed:")
var shares: [String: TimeInterval] = [:]
for held in timeline { shares[held.outcome.label, default: 0] += held.seconds }
for (name, seconds) in shares.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  %-18@ %5.1f%%   %@", name as NSString,
                 total > 0 ? 100 * seconds / total : 0, hours(seconds) as NSString))
}
print("")

print("Time the gate spent in each state:")
var gates: [String: TimeInterval] = [:]
for held in timeline { gates[held.gate.label, default: 0] += held.seconds }
for (name, seconds) in gates.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  %-18@ %5.1f%%   %@", name as NSString,
                 total > 0 ? 100 * seconds / total : 0, hours(seconds) as NSString))
}
print("")

print("Every change of state:")
var changes = 0
for (index, held) in timeline.enumerated() {
    // The reset is a change and an honest one: the counter really did drop
    // to zero and the gate really did start over. Reported as itself rather
    // than as whatever transition it happens to produce.
    if resets.contains(held.at) {
        changes += 1
        print("  \(held.at.formatted(date: .abbreviated, time: .shortened))   — weekly reset —")
        continue
    }
    guard index > 0 else { continue }
    let previous = timeline[index - 1]
    guard previous.outcome.label != held.outcome.label else { continue }
    changes += 1
    print(String(format: "  %@   %@ → %@   R² %@, gate %@",
                 held.at.formatted(date: .abbreviated, time: .shortened) as NSString,
                 previous.outcome.label as NSString, held.outcome.label as NSString,
                 (held.fitQuality.map { String(format: "%.3f", $0) } ?? "—") as NSString,
                 held.gate.label as NSString))
}
print("  \(changes) in total")
print("")

let sorted = qualities.sorted()
if sorted.isEmpty {
    print("No fit was ever run: fewer than \(Forecast.minimumPoints) points in every window.")
} else {
    func quantile(_ share: Double) -> Double {
        sorted[min(sorted.count - 1, Int(share * Double(sorted.count)))]
    }
    print(String(format: "R² over %d fits:  min %.3f   p10 %.3f   median %.3f   p90 %.3f   max %.3f",
                 sorted.count, sorted.first!, quantile(0.1), quantile(0.5),
                 quantile(0.9), sorted.last!))
    print(String(format: "Thresholds:       enter at %.2f, leave at %.2f",
                 Forecast.minimumFitQuality, Forecast.minimumFitQualityToKeep))
}
