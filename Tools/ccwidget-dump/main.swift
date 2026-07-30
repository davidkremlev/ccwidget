import Foundation

// Консольная проверка этапа 1: читает snapshot.json из папки App Group
// и печатает разобранные значения. Xcode для этого не нужен.

let store: SnapshotStore
if CommandLine.arguments.count > 1 {
    let path = (CommandLine.arguments[1] as NSString).expandingTildeInPath
    store = SnapshotStore(containerURL: URL(filePath: path).deletingLastPathComponent())
} else {
    store = SnapshotStore.default()
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("ошибка: " + message + "\n").utf8))
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

// MARK: - Форматирование

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
    case .fresh: return "только что"
    case .recent: return "недавно"
    case .stale: return "данные устарели"
    case .abandoned: return "запустите Claude Code"
    }
}

func report(_ title: String, _ window: LimitWindow?) {
    guard let window else {
        print("\(title): нет данных (rate_limits ещё не пришли)")
        return
    }
    let reset = window.resetsAt.formatted(date: .abbreviated, time: .shortened)
    print("\(title):")
    line("израсходовано", "\(window.usedPercentage)%")
    line("остаток", "\(window.remainingPercentage)%  [\(describe(window.level))]")
    line("сброс", "\(reset)  (через \(duration(window.timeUntilReset())))")
}

// MARK: - Вывод

let age = snapshot.age()

print("Контейнер: \(store.containerURL.path)")
print("Файл:      \(store.snapshotURL.lastPathComponent)")
print("")
print("Снимок:")
line("схема", "\(snapshot.schemaVersion)")
line("снят", "\(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
line("возраст", "\(duration(age))  [\(describe(Freshness(age: age)))]")
line("сессия", dash(snapshot.sessionId))
line("Claude Code", dash(snapshot.claudeCodeVersion))
print("")

print("Модель:")
line("id", dash(snapshot.model?.id))
line("название", dash(snapshot.model?.displayName))
line("усилие", dash(snapshot.model?.effort))
print("")

print("Проект:")
line("имя", dash(snapshot.project?.name))
print("")

report("Пятичасовое окно", snapshot.limits.fiveHour)
print("")
report("Недельное окно", snapshot.limits.sevenDay)
print("")

print("Контекст:")
if let context = snapshot.context {
    line("заполнено", context.usedPercentage.map { "\($0)%" } ?? "—")
    line("уровень", context.level.map(describe) ?? "—")
    line("токенов", context.totalInputTokens.map { $0.formatted(tokens) } ?? "—")
    line("окно", context.windowSize.map { $0.formatted(tokens) } ?? "—")
    line("доля кеша", context.cacheHitRatio.map { $0.formatted(percent) } ?? "—")
} else {
    line("—", "нет данных")
}
print("")

print("Стоимость:")
line("сессия", snapshot.cost?.sessionUsd.map { $0.formatted(money) } ?? "—")
print("")

print("Диагностика разбора:")
if snapshot.diagnostics.isEmpty {
    line("—", "чисто, полей не отброшено")
} else {
    for issue in snapshot.diagnostics {
        line(issue.field, "\(issue.rawValue ?? "?")  ←  \(issue.reason)")
    }
}
