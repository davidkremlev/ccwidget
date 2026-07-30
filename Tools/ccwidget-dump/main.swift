import Foundation

// A console check: reads snapshot.json from the exchange directory and prints
// the parsed values. Xcode is not needed for this.

let store: SnapshotStore
if CommandLine.arguments.count > 1 {
    let path = (CommandLine.arguments[1] as NSString).expandingTildeInPath
    store = SnapshotStore(containerURL: URL(filePath: path).deletingLastPathComponent())
} else {
    store = SnapshotStore.default()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let snapshot: Snapshot
do {
    snapshot = try store.load()
} catch let error as SnapshotStoreError {
    fail(error.description)
} catch {
    fail("\(error)")
}

// MARK: - Formatting

let percent: FloatingPointFormatStyle<Double>.Percent = .percent.precision(.fractionLength(0))
let money: FloatingPointFormatStyle<Double>.Currency = .currency(code: "USD").precision(.fractionLength(2))
let tokens: IntegerFormatStyle<Int> = .number.grouping(.automatic)

func dash(_ value: String?) -> String { value ?? "—" }

func line(_ label: String, _ value: String) {
    let padded = label.padding(toLength: max(20, label.count), withPad: " ", startingAt: 0)
    print("  \(padded) \(value)")
}

func duration(_ seconds: TimeInterval) -> String {
    let style = Duration.UnitsFormatStyle(
        allowedUnits: [.days, .hours, .minutes],
        width: .abbreviated,
        maximumUnitCount: 2
    )
    return Duration.seconds(max(0, seconds)).formatted(style)
}

func describe(_ level: Level) -> String {
    switch level {
    case .healthy: return "healthy"
    case .warning: return "warning"
    case .critical: return "critical"
    case .depleted: return "depleted"
    }
}

func describe(_ freshness: Freshness) -> String {
    switch freshness {
    case .fresh: return "just now"
    case .recent: return "recent"
    case .stale: return "outdated"
    case .abandoned: return "launch Claude Code"
    }
}

func report(_ title: String, _ window: LimitWindow?) {
    guard let window else {
        print("\(title): no data (rate_limits have not arrived yet)")
        return
    }
    let reset = window.resetsAt.formatted(date: .abbreviated, time: .shortened)
    print("\(title):")
    line("used", "\(window.usedPercentage)%")
    line("remaining", "\(window.remainingPercentage)%  [\(describe(window.level))]")
    line("resets", "\(reset)  (in \(duration(window.timeUntilReset())))")
}

// MARK: - Output

let age = snapshot.age()

print("Directory: \(store.containerURL.path)")
print("File:      \(store.snapshotURL.lastPathComponent)")
print("")
print("Snapshot:")
line("schema", "\(snapshot.schemaVersion)")
line("captured", "\(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
line("age", "\(duration(age))  [\(describe(Freshness(age: age)))]")
line("session", dash(snapshot.sessionId))
line("Claude Code", dash(snapshot.claudeCodeVersion))
print("")

print("Model:")
line("id", dash(snapshot.model?.id))
line("name", dash(snapshot.model?.displayName))
line("effort", dash(snapshot.model?.effort))
print("")

print("Project:")
line("name", dash(snapshot.project?.name))
print("")

report("Five-hour window", snapshot.limits.fiveHour)
print("")
report("Weekly window", snapshot.limits.sevenDay)
print("")

print("Context:")
if let context = snapshot.context {
    line("used", context.usedPercentage.map { "\($0)%" } ?? "—")
    line("level", context.level.map(describe) ?? "—")
    line("tokens", context.totalInputTokens.map { $0.formatted(tokens) } ?? "—")
    line("window", context.windowSize.map { $0.formatted(tokens) } ?? "—")
    line("cache share", context.cacheHitRatio.map { $0.formatted(percent) } ?? "—")
} else {
    line("—", "no data")
}
print("")

print("Cost:")
line("session", snapshot.cost?.sessionUsd.map { $0.formatted(money) } ?? "—")
print("")

print("Parse diagnostics:")
if snapshot.diagnostics.isEmpty {
    line("—", "clean, no fields dropped")
} else {
    for issue in snapshot.diagnostics {
        line(issue.field, "\(issue.rawValue ?? "?")  ←  \(issue.reason)")
    }
}
