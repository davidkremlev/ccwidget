import Foundation

// Проверки установщика и точечной правки настроек.
//
// Всё выполняется в подставном каталоге: корень приходит параметром
// (раздел 5.2), поэтому настоящий ~/.claude не участвует и пострадать
// не может. Ровно этой изоляции не хватало, когда установщик вычислял
// домашний каталог сам и переписал живой конфиг.

var failures = 0

@MainActor
func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    if condition {
        print("  ✓ \(name)")
    } else {
        failures += 1
        let extra = detail()
        print("  ✗ \(name)\(extra.isEmpty ? "" : "\n      " + extra)")
    }
}

@MainActor
func sandbox() -> URL {
    let root = URL(filePath: NSTemporaryDirectory())
        .appending(path: "ccwidget-selftest-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor
func makeContainer(in home: URL) {
    try! FileManager.default.createDirectory(
        at: SnapshotStore.widgetContainerURL(home: home)
            .appending(path: "Data/Library/Application Support"),
        withIntermediateDirectories: true
    )
}

@MainActor
func makeTemplate(in root: URL) -> URL {
    let url = root.appending(path: "ccwidget-export.py.template")
    try! "#!/usr/bin/env python3\nGROUP_DIR = \"__GROUP_DIR__\"\n".write(to: url, atomically: true, encoding: .utf8)
    return url
}

@MainActor
func installer(home: URL, template: URL) -> Installer {
    Installer(
        home: home,
        exchangeDirectory: SnapshotStore.exchangeURL(home: home),
        templateURL: template
    )
}

@MainActor
func isSymlink(_ url: URL) -> Bool {
    let type = try? FileManager.default.attributesOfItem(
        atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType
    return type == .typeSymbolicLink
}

@MainActor
func settings(_ home: URL) -> String {
    (try? String(contentsOf: home.appending(path: ".claude/settings.json"), encoding: .utf8)) ?? ""
}

@MainActor
func write(_ text: String, to home: URL) {
    let dir = home.appending(path: ".claude")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try! text.write(to: dir.appending(path: "settings.json"), atomically: true, encoding: .utf8)
}

// MARK: - Точечная правка

print("\nSettingsEditor")

do {
    let original = """
    {
      "theme": "dark",
      "permissions": {
        "defaultMode": "auto"
      },
      "language": "Russian"
    }
    """
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/tmp/x.py", "padding": 0], in: original
    )
    guard case .surgical(let edited) = outcome else {
        check("новый ключ дописывается точечно", false, "правка свелась к пересборке")
        exit(1)
    }
    check("новый ключ дописывается точечно", true)
    check("порядок прежних ключей сохранён",
          edited.range(of: "\"theme\"")!.lowerBound < edited.range(of: "\"permissions\"")!.lowerBound
          && edited.range(of: "\"permissions\"")!.lowerBound < edited.range(of: "\"language\"")!.lowerBound)
    check("прежние строки не тронуты", edited.contains("  \"language\": \"Russian\""))
    check("отступ подхвачен из файла", edited.contains("\n  \"statusLine\": {"))
    check("результат разбирается", (try? JSONSerialization.jsonObject(
        with: edited.data(using: .utf8)!)) != nil)
}

do {
    let original = """
    {
      "theme": "dark",
      "statusLine": {
        "type": "command",
        "command": "/старый/скрипт.sh",
        "padding": 4
      },
      "language": "Russian"
    }
    """
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/новый.py", "padding": 0], in: original
    )
    guard case .surgical(let edited) = outcome else {
        check("существующий ключ заменяется точечно", false); exit(1)
    }
    check("существующий ключ заменяется точечно", true)
    check("старая команда исчезла", !edited.contains("/старый/скрипт.sh"))
    check("новая команда на месте", edited.contains("/новый.py"))
    check("соседние ключи целы",
          edited.contains("\"theme\": \"dark\"") && edited.contains("\"language\": \"Russian\""))
    check("ключ остался на своём месте",
          edited.range(of: "\"theme\"")!.lowerBound < edited.range(of: "\"statusLine\"")!.lowerBound
          && edited.range(of: "\"statusLine\"")!.lowerBound < edited.range(of: "\"language\"")!.lowerBound)
}

do {
    // Одноимённый ключ на большей глубине трогать нельзя.
    let original = """
    {
      "nested": {
        "statusLine": "не трогать"
      },
      "theme": "dark"
    }
    """
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: original
    )
    guard case .surgical(let edited) = outcome else {
        check("вложенный одноимённый ключ не путается с верхним", false); exit(1)
    }
    check("вложенный одноимённый ключ не путается с верхним", edited.contains("\"не трогать\""))
    let parsed = try! JSONSerialization.jsonObject(with: edited.data(using: .utf8)!) as! [String: Any]
    check("верхний ключ добавлен", parsed["statusLine"] is [String: Any])
    check("вложенный остался строкой",
          (parsed["nested"] as? [String: Any])?["statusLine"] as? String == "не трогать")
}

do {
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: "{}"
    )
    if case .surgical(let edited) = outcome {
        check("пустой объект наполняется", edited.contains("\"statusLine\""))
        check("пустой объект остаётся валидным",
              (try? JSONSerialization.jsonObject(with: edited.data(using: .utf8)!)) != nil)
    } else {
        check("пустой объект наполняется", false)
    }
}

do {
    // Табы вместо пробелов — отступ обязан подхватиться.
    let original = "{\n\t\"theme\": \"dark\"\n}"
    if case .surgical(let edited) = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: original) {
        check("табуляция сохранена", edited.contains("\n\t\"statusLine\""))
    } else {
        check("табуляция сохранена", false)
    }
}

do {
    // Битый JSON точечно править нельзя — обязан быть откат на пересборку.
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: "{ это не json")
    if case .rewritten(let text) = outcome {
        check("битый файл уходит в пересборку", text.contains("\"statusLine\""))
    } else {
        check("битый файл уходит в пересборку", false, "точечная правка не должна была пройти")
    }
}

// MARK: - Установщик

print("\nInstaller")

do {
    let home = sandbox()
    let template = makeTemplate(in: home)
    write("{}", to: home)
    // Контейнер не создаём: установка обязана отказать, а не создать его сама.
    var thrown: Error?
    do { _ = try installer(home: home, template: template).install() } catch { thrown = error }
    check("без контейнера расширения установка отказывает", thrown != nil)
    check("каталог контейнера не создан сам",
          !FileManager.default.fileExists(
            atPath: SnapshotStore.widgetContainerURL(home: home).path))
}

do {
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("""
    {
      "theme": "dark",
      "language": "Russian"
    }
    """, to: home)

    let inst = installer(home: home, template: template)
    check("Claude Code найден", inst.isClaudeCodePresent)
    check("статуслайн ещё не наш", inst.statusLineState() == .absent)

    let report = try! inst.install()
    check("правка точечная", report.editWasSurgical)
    check("копия создана", report.backup != nil)
    check("экспортёр записан", FileManager.default.fileExists(atPath: inst.exporterURL.path))

    let mode = (try! FileManager.default.attributesOfItem(atPath: inst.exporterURL.path)[.posixPermissions] as! NSNumber).intValue
    check("экспортёр исполняемый", mode & 0o111 != 0, "права \(String(mode, radix: 8))")

    let body = try! String(contentsOf: inst.exporterURL, encoding: .utf8)
    check("плейсхолдер подставлен", !body.contains("__GROUP_DIR__")
          && body.contains(SnapshotStore.exchangeURL(home: home).path))

    let text = settings(home)
    check("прежние ключи целы", text.contains("\"theme\": \"dark\"") && text.contains("\"language\": \"Russian\""))
    check("статуслайн стал нашим", inst.statusLineState() == .ours)

    let backupText = try! String(contentsOf: report.backup!, encoding: .utf8)
    check("копия содержит исходник", backupText.contains("\"theme\": \"dark\"")
          && !backupText.contains("statusLine"))

    // Второй запуск подряд: имя копии не должно совпасть.
    let second = try! inst.install()
    check("вторая установка не падает на имени копии", second.backup != nil)
    check("вторая копия отличается", second.backup?.lastPathComponent != report.backup?.lastPathComponent)
}

do {
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("""
    {
      "statusLine": {
        "type": "command",
        "command": "/чужой/скрипт.sh"
      }
    }
    """, to: home)
    let inst = installer(home: home, template: template)
    guard case .foreign(let command) = inst.statusLineState() else {
        check("чужой статуслайн распознан", false); exit(1)
    }
    check("чужой статуслайн распознан", command == "/чужой/скрипт.sh")
    _ = try! inst.install()
    check("чужой статуслайн заменён", inst.statusLineState() == .ours)
}

do {
    let home = sandbox()
    makeContainer(in: home)
    write("{}", to: home)
    var thrown: Error?
    do {
        _ = try Installer(home: home,
                          exchangeDirectory: SnapshotStore.exchangeURL(home: home),
                          templateURL: nil).install()
    } catch { thrown = error }
    check("без шаблона установка отказывает", thrown != nil)
}

// MARK: - Символические ссылки и внедрение

print("\nБезопасность")

do {
    // B: ~/.claude/settings.json — ссылка в репозиторий dotfiles.
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    let real = home.appending(path: "dotfiles/settings.json")
    try! FileManager.default.createDirectory(
        at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! "{\n  \"theme\": \"dark\"\n}\n".write(to: real, atomically: true, encoding: .utf8)
    try! FileManager.default.createDirectory(
        at: home.appending(path: ".claude"), withIntermediateDirectories: true)
    try! FileManager.default.createSymbolicLink(
        at: home.appending(path: ".claude/settings.json"), withDestinationURL: real)

    let inst = installer(home: home, template: template)
    check("ссылка распознана до записи", inst.preflight().settingsLinkTarget != nil)
    let report = try! inst.install()

    check("ссылка сохранена", isSymlink(inst.settingsURL))
    let target = try! String(contentsOf: real, encoding: .utf8)
    check("запись ушла по цели ссылки", target.contains("statusLine"))
    check("прежний ключ цели цел", target.contains("\"theme\": \"dark\""))
    check("копия — обычный файл, не ссылка", report.backup.map { !isSymlink($0) } ?? false)
    let backup = try! String(contentsOf: report.backup!, encoding: .utf8)
    check("копия содержит исходник цели",
          backup.contains("\"theme\"") && !backup.contains("statusLine"))
}

do {
    // C: подложенная ссылка на месте временного файла усечения истории.
    let home = sandbox()
    makeContainer(in: home)
    let exchange = SnapshotStore.exchangeURL(home: home)
    try! FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
    let victim = home.appending(path: "victim.txt")
    try! "ВАЖНЫЕ ДАННЫЕ".write(to: victim, atomically: true, encoding: .utf8)

    let store = HistoryStore(url: exchange.appending(path: "history.jsonl"))
    let lines = (0..<2500).map { #"{"t":\#($0),"sevenDay":1,"resetsAt":9}"# }
    try! lines.joined(separator: "\n").write(to: store.url, atomically: true, encoding: .utf8)
    try! FileManager.default.createSymbolicLink(
        at: exchange.appending(path: "history.jsonl.tmp"), withDestinationURL: victim)

    _ = store.truncateIfNeeded()
    check("усечение не пишет сквозь ссылку",
          (try! String(contentsOf: victim, encoding: .utf8)) == "ВАЖНЫЕ ДАННЫЕ")
}

do {
    // D: путь с кавычкой и переводом строки обязан дать корректный литерал.
    let hostile = "/tmp/x\"\nimport os; os.system(\"touch /tmp/PWNED\")\nJUNK = \""
    let literal = Installer.pythonStringLiteral(hostile)

    // Настоящее свойство: литерал разбирается обратно в исходную строку.
    let decoded = (try? JSONSerialization.jsonObject(
        with: Data("[\(literal)]".utf8))) as? [String]
    check("литерал декодируется обратно в исходный путь", decoded?.first == hostile,
          "получено: \(decoded?.first ?? "nil")")
    check("литерал однострочный", !literal.contains("\n"))

    let rendered = Installer.replacingShebang(
        in: "#!/usr/bin/env python3\nGROUP_DIR = \"__GROUP_DIR__\"\n",
        with: URL(filePath: "/usr/bin/python3")
    ).replacingOccurrences(of: "\"__GROUP_DIR__\"", with: literal)
    check("шебанг заменён абсолютным путём", rendered.hasPrefix("#!/usr/bin/python3\n"))
    check("внедрение не создало новых строк",
          rendered.components(separatedBy: "\n").count == 3,
          "строк: \(rendered.components(separatedBy: "\n").count)")
}

// MARK: - Удаление

print("\nУдаление")

do {
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("""
    {
      "theme": "dark",
      "permissions": {
        "defaultMode": "auto"
      },
      "language": "Russian"
    }
    """, to: home)

    let inst = installer(home: home, template: template)
    _ = try! inst.install()
    check("после установки статуслайн наш", inst.statusLineState() == .ours)
    check("хеш записан", FileManager.default.fileExists(
        atPath: inst.integrityURL.path(percentEncoded: false)))
    check("целостность сходится", inst.checkIntegrity() == .matches)

    // Подмена экспортёра посторонним должна быть замечена.
    try! "#!/bin/sh\necho hacked\n".write(to: inst.exporterURL, atomically: true, encoding: .utf8)
    check("подмена экспортёра замечена", inst.checkIntegrity() == .changed)
    _ = try! inst.install()
    check("переустановка чинит целостность", inst.checkIntegrity() == .matches)

    let plan = inst.removalPlan()
    check("план удаления видит наш статуслайн", plan.removesStatusLine)
    check("план удаления видит экспортёр", plan.removesExporter)

    let report = try! inst.uninstall(removingHistory: false)
    check("ключ statusLine удалён", report.statusLineRemoved)
    check("экспортёр удалён", !FileManager.default.fileExists(
        atPath: inst.exporterURL.path(percentEncoded: false)))
    check("хеш удалён", !FileManager.default.fileExists(
        atPath: inst.integrityURL.path(percentEncoded: false)))
    check("статуслайн больше не наш", inst.statusLineState() == .absent)

    let text = settings(home)
    check("соседние ключи целы после удаления",
          text.contains("\"theme\": \"dark\"") && text.contains("\"language\": \"Russian\"")
          && text.contains("\"defaultMode\": \"auto\""))
    check("форматирование соседей сохранено", text.contains("  \"language\": \"Russian\""))
    check("файл остался валидным JSON",
          (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil)
    check("висячей запятой нет", !text.contains(",\n}") && !text.contains(", }"))
    check("копия при удалении сделана", report.backup != nil)
    if let backup = report.backup {
        let mode = (try! FileManager.default.attributesOfItem(
            atPath: backup.path(percentEncoded: false))[.posixPermissions] as! NSNumber).intValue
        check("копия закрыта правами 0600", mode == 0o600, "права \(String(mode, radix: 8))")
    }
}

do {
    // Чужой статуслайн удаление трогать не должно.
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write(#"{"statusLine":{"type":"command","command":"/чужой.sh"}}"#, to: home)
    let inst = installer(home: home, template: template)
    _ = try? inst.uninstall(removingHistory: false)
    check("чужой статуслайн не тронут", settings(home).contains("/чужой.sh"))
}

do {
    // Ротация копий.
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("{}", to: home)
    let inst = installer(home: home, template: template)
    for _ in 0..<8 { _ = try? inst.install() }
    let names = (try! FileManager.default.contentsOfDirectory(
        atPath: inst.claudeDirectory.path(percentEncoded: false)))
        .filter { $0.hasPrefix("settings.json.bak-") }
    check("копий не больше пяти", names.count <= Installer.backupsKept,
          "найдено \(names.count)")
}

// MARK: - Оценка расхода

print("\nForecast")

@MainActor
func series(
    count: Int, stepMinutes: Double, from start: Int, per step: Double,
    resets: Date, now: Date, noise: (Int) -> Double = { _ in 0 }
) -> [HistoryEntry] {
    (0..<count).map { i in
        HistoryEntry(
            time: now.addingTimeInterval(-Double(count - 1 - i) * stepMinutes * 60),
            sevenDayUsed: Int((Double(start) + step * Double(i) + noise(i)).rounded()),
            resetsAt: resets
        )
    }
}

@MainActor
func describe(_ o: Forecast.Outcome) -> String {
    switch o {
    case .notEnoughData: return "notEnoughData"
    case .flat: return "flat"
    case .rateOnly: return "rateOnly"
    case .lastsUntilReset: return "lastsUntilReset"
    case .runsOut: return "runsOut"
    }
}

let now = Date()

do {
    // Идеальная прямая на четырёх часах: R² должен быть единицей.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let f = Forecast.make(history: series(count: 25, stepMinutes: 10, from: 20, per: 1.6,
                                          resets: resets, now: now), window: window, now: now)
    check("идеальная линия даёт R² около единицы", (f.fitQuality ?? 0) > 0.99,
          "R² = \(f.fitQuality ?? -1)")
    check("на достаточной базе дата называется", describe(f.outcome) == "runsOut",
          "получено \(describe(f.outcome))")
    check("пунктир рисуется", f.showsProjection)
}

do {
    // Меньше десяти точек — считать нечего, какой бы ни была база.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let f = Forecast.make(history: series(count: 9, stepMinutes: 30, from: 20, per: 4,
                                          resets: resets, now: now), window: window, now: now)
    check("девять точек отбраковываются", describe(f.outcome) == "notEnoughData")
}

do {
    // База меньше двух часов — отбраковка по разбросу.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let f = Forecast.make(history: series(count: 20, stepMinutes: 5, from: 20, per: 2,
                                          resets: resets, now: now), window: window, now: now)
    check("база в полтора часа отбраковывается", describe(f.outcome) == "notEnoughData",
          "база \(Int(f.observationSpan / 60)) мин, получено \(describe(f.outcome))")
}

do {
    // Шум, который линия не описывает: R² ниже порога.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let saw: (Int) -> Double = { i in i % 2 == 0 ? -18 : 18 }
    let f = Forecast.make(history: series(count: 30, stepMinutes: 10, from: 30, per: 0.2,
                                          resets: resets, now: now, noise: saw),
                          window: window, now: now)
    check("линия, не описывающая данные, отбраковывается по R²",
          describe(f.outcome) == "notEnoughData", "R² = \(f.fitQuality ?? -1)")
}

do {
    // Главный случай: сразу после сброса недели. База два часа,
    // до сброса почти семь суток — дату называть нельзя, темп можно.
    let resets = now.addingTimeInterval(6.9 * 24 * 3600)
    let window = LimitWindow(usedPercentage: 3, resetsAt: resets)
    let f = Forecast.make(history: series(count: 13, stepMinutes: 10, from: 1, per: 0.15,
                                          resets: resets, now: now), window: window, now: now)
    check("после сброса недели — темп без даты", describe(f.outcome) == "rateOnly",
          "получено \(describe(f.outcome))")
    check("темп при этом есть", f.hasRate)
    check("пунктир не рисуется", !f.showsProjection)
    check("темп положительный", (f.percentPerHour ?? 0) > 0)
}

do {
    // База выросла до суток — горизонта хватает на всю неделю.
    let resets = now.addingTimeInterval(6 * 24 * 3600)
    let window = LimitWindow(usedPercentage: 10, resetsAt: resets)
    let f = Forecast.make(history: series(count: 40, stepMinutes: 40, from: 1, per: 0.22,
                                          resets: resets, now: now), window: window, now: now)
    check("на суточной базе горизонт покрывает неделю",
          describe(f.outcome) != "rateOnly", "получено \(describe(f.outcome))")
}

do {
    // Плато: наклон не положительный.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 55, resetsAt: resets)
    let f = Forecast.make(history: series(count: 20, stepMinutes: 15, from: 55, per: 0,
                                          resets: resets, now: now), window: window, now: now)
    check("плато распознано", describe(f.outcome) == "flat")
    check("на плато темпа не показываем", !f.hasRate)
}

do {
    // Точки чужого окна отфильтровываются целиком.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let other = series(count: 30, stepMinutes: 10, from: 20, per: 1.5,
                       resets: resets.addingTimeInterval(-604800), now: now)
    let f = Forecast.make(history: other, window: window, now: now)
    check("точки прошлого окна отброшены", f.points.isEmpty)
    check("и оценки по ним нет", describe(f.outcome) == "notEnoughData")
}

do {
    // Расход быстрый, исчерпание близко — дата в пределах горизонта.
    let resets = now.addingTimeInterval(5 * 24 * 3600)
    let window = LimitWindow(usedPercentage: 80, resetsAt: resets)
    let f = Forecast.make(history: series(count: 15, stepMinutes: 20, from: 60, per: 1.4,
                                          resets: resets, now: now), window: window, now: now)
    check("близкое исчерпание называется датой", describe(f.outcome) == "runsOut",
          "получено \(describe(f.outcome))")
    if case .runsOut(let date) = f.outcome {
        check("дата не в прошлом", date >= now)
        let horizon = date.timeIntervalSince(now)
        check("дата в пределах десяти длин базы",
              horizon <= f.observationSpan * Forecast.horizonMultiplier + 60,
              "горизонт \(Int(horizon / 3600)) ч при базе \(Int(f.observationSpan / 3600)) ч")
    }
}

print("\n\(failures == 0 ? "всё сошлось" : "провалов: \(failures)")")
exit(failures == 0 ? 0 : 1)
