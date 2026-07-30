import Foundation

// Checks for the installer and for the surgical settings edit.
//
// Everything runs inside a stand-in directory: the root arrives as a parameter
// (section 5.2), so the real ~/.claude takes no part and cannot be harmed.
// This is exactly the isolation that was missing when the installer worked out
// the home directory by itself and overwrote a live config.

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

// MARK: - Surgical edit

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
        check("a new key is added surgically", false, "the edit fell back to a rewrite")
        exit(1)
    }
    check("a new key is added surgically", true)
    check("the order of the existing keys survives",
          edited.range(of: "\"theme\"")!.lowerBound < edited.range(of: "\"permissions\"")!.lowerBound
          && edited.range(of: "\"permissions\"")!.lowerBound < edited.range(of: "\"language\"")!.lowerBound)
    check("the existing lines are untouched", edited.contains("  \"language\": \"Russian\""))
    check("the indentation is picked up from the file", edited.contains("\n  \"statusLine\": {"))
    check("the result parses", (try? JSONSerialization.jsonObject(
        with: edited.data(using: .utf8)!)) != nil)
}

do {
    let original = """
    {
      "theme": "dark",
      "statusLine": {
        "type": "command",
        "command": "/old/script.sh",
        "padding": 4
      },
      "language": "Russian"
    }
    """
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/new.py", "padding": 0], in: original
    )
    guard case .surgical(let edited) = outcome else {
        check("an existing key is replaced surgically", false); exit(1)
    }
    check("an existing key is replaced surgically", true)
    check("the old command is gone", !edited.contains("/old/script.sh"))
    check("the new command is there", edited.contains("/new.py"))
    check("the neighbouring keys are intact",
          edited.contains("\"theme\": \"dark\"") && edited.contains("\"language\": \"Russian\""))
    check("the key stays where it was",
          edited.range(of: "\"theme\"")!.lowerBound < edited.range(of: "\"statusLine\"")!.lowerBound
          && edited.range(of: "\"statusLine\"")!.lowerBound < edited.range(of: "\"language\"")!.lowerBound)
}

do {
    // A key of the same name further down must be left alone.
    let original = """
    {
      "nested": {
        "statusLine": "leave me alone"
      },
      "theme": "dark"
    }
    """
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: original
    )
    guard case .surgical(let edited) = outcome else {
        check("a nested key of the same name is not confused with the top one", false); exit(1)
    }
    check("a nested key of the same name is not confused with the top one",
          edited.contains("\"leave me alone\""))
    let parsed = try! JSONSerialization.jsonObject(with: edited.data(using: .utf8)!) as! [String: Any]
    check("the top-level key was added", parsed["statusLine"] is [String: Any])
    check("the nested one is still a string",
          (parsed["nested"] as? [String: Any])?["statusLine"] as? String == "leave me alone")
}

do {
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: "{}"
    )
    if case .surgical(let edited) = outcome {
        check("an empty object gets filled in", edited.contains("\"statusLine\""))
        check("an empty object stays valid",
              (try? JSONSerialization.jsonObject(with: edited.data(using: .utf8)!)) != nil)
    } else {
        check("an empty object gets filled in", false)
    }
}

do {
    // Tabs instead of spaces — the indentation has to be picked up.
    let original = "{\n\t\"theme\": \"dark\"\n}"
    if case .surgical(let edited) = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: original) {
        check("tab indentation survives", edited.contains("\n\t\"statusLine\""))
    } else {
        check("tab indentation survives", false)
    }
}

do {
    // Broken JSON cannot be edited surgically — it has to fall back to a rewrite.
    let outcome = SettingsEditor.setting(
        "statusLine", to: ["type": "command", "command": "/x.py", "padding": 0], in: "{ not json at all")
    if case .rewritten(let text) = outcome {
        check("a broken file falls back to a rewrite", text.contains("\"statusLine\""))
    } else {
        check("a broken file falls back to a rewrite", false, "the surgical edit should not have gone through")
    }
}

// MARK: - Installer

print("\nInstaller")

do {
    let home = sandbox()
    let template = makeTemplate(in: home)
    write("{}", to: home)
    // Do not create the container: installing has to refuse, not create it itself.
    var thrown: Error?
    do { _ = try installer(home: home, template: template).install() } catch { thrown = error }
    check("installing refuses without the extension's container", thrown != nil)
    check("the container directory was not created behind our back",
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
    check("Claude Code is found", inst.isClaudeCodePresent)
    check("the status line is not ours yet", inst.statusLineState() == .absent)

    let report = try! inst.install()
    check("the edit was surgical", report.editWasSurgical)
    check("a backup was made", report.backup != nil)
    check("the exporter was written", FileManager.default.fileExists(atPath: inst.exporterURL.path))

    let mode = (try! FileManager.default.attributesOfItem(atPath: inst.exporterURL.path)[.posixPermissions] as! NSNumber).intValue
    check("the exporter is executable", mode & 0o111 != 0, "mode \(String(mode, radix: 8))")

    let body = try! String(contentsOf: inst.exporterURL, encoding: .utf8)
    check("the placeholder was substituted", !body.contains("__GROUP_DIR__")
          && body.contains(SnapshotStore.exchangeURL(home: home).path))

    let text = settings(home)
    check("the existing keys are intact", text.contains("\"theme\": \"dark\"") && text.contains("\"language\": \"Russian\""))
    check("the status line became ours", inst.statusLineState() == .ours)

    let backupText = try! String(contentsOf: report.backup!, encoding: .utf8)
    check("the backup holds the original", backupText.contains("\"theme\": \"dark\"")
          && !backupText.contains("statusLine"))

    // Two runs back to back: the backup names must not collide.
    let second = try! inst.install()
    check("a second install does not trip over the backup name", second.backup != nil)
    check("the second backup has a different name", second.backup?.lastPathComponent != report.backup?.lastPathComponent)
}

do {
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("""
    {
      "statusLine": {
        "type": "command",
        "command": "/someone/else.sh"
      }
    }
    """, to: home)
    let inst = installer(home: home, template: template)
    guard case .foreign(let command) = inst.statusLineState() else {
        check("a foreign status line is recognised", false); exit(1)
    }
    check("a foreign status line is recognised", command == "/someone/else.sh")
    _ = try! inst.install()
    check("a foreign status line is replaced", inst.statusLineState() == .ours)
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
    check("installing refuses without the template", thrown != nil)
}

// MARK: - Symbolic links and injection

print("\nSecurity")

do {
    // B: ~/.claude/settings.json is a link into a dotfiles repository.
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
    check("the link is spotted before anything is written", inst.preflight().settingsLinkTarget != nil)
    let report = try! inst.install()

    check("the link survives", isSymlink(inst.settingsURL))
    let target = try! String(contentsOf: real, encoding: .utf8)
    check("the write landed on the link's target", target.contains("statusLine"))
    check("the target's existing key is intact", target.contains("\"theme\": \"dark\""))
    check("the backup is a plain file, not a link", report.backup.map { !isSymlink($0) } ?? false)
    let backup = try! String(contentsOf: report.backup!, encoding: .utf8)
    check("the backup holds the target's original",
          backup.contains("\"theme\"") && !backup.contains("statusLine"))
}

do {
    // C: a link planted where the history truncation writes its temporary file.
    let home = sandbox()
    makeContainer(in: home)
    let exchange = SnapshotStore.exchangeURL(home: home)
    try! FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
    let victim = home.appending(path: "victim.txt")
    try! "PRECIOUS DATA".write(to: victim, atomically: true, encoding: .utf8)

    let store = HistoryStore(url: exchange.appending(path: "history.jsonl"))
    let lines = (0..<2500).map { #"{"t":\#($0),"sevenDay":1,"resetsAt":9}"# }
    try! lines.joined(separator: "\n").write(to: store.url, atomically: true, encoding: .utf8)
    try! FileManager.default.createSymbolicLink(
        at: exchange.appending(path: "history.jsonl.tmp"), withDestinationURL: victim)

    _ = store.truncateIfNeeded()
    check("truncation does not write through a link",
          (try! String(contentsOf: victim, encoding: .utf8)) == "PRECIOUS DATA")
}

do {
    // D: a path with a quote and a newline in it has to produce a sound literal.
    let hostile = "/tmp/x\"\nimport os; os.system(\"touch /tmp/PWNED\")\nJUNK = \""
    let literal = Installer.pythonStringLiteral(hostile)

    // The real property: the literal parses back into the original string.
    let decoded = (try? JSONSerialization.jsonObject(
        with: Data("[\(literal)]".utf8))) as? [String]
    check("the literal decodes back into the original path", decoded?.first == hostile,
          "got: \(decoded?.first ?? "nil")")
    check("the literal is a single line", !literal.contains("\n"))

    let rendered = Installer.replacingShebang(
        in: "#!/usr/bin/env python3\nGROUP_DIR = \"__GROUP_DIR__\"\n",
        with: URL(filePath: "/usr/bin/python3")
    ).replacingOccurrences(of: "\"__GROUP_DIR__\"", with: literal)
    check("the shebang was replaced with an absolute path", rendered.hasPrefix("#!/usr/bin/python3\n"))
    check("the injection added no new lines",
          rendered.components(separatedBy: "\n").count == 3,
          "lines: \(rendered.components(separatedBy: "\n").count)")
}

// MARK: - Removal

print("\nRemoval")

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
    check("the status line is ours after installing", inst.statusLineState() == .ours)
    check("the hash was written", FileManager.default.fileExists(
        atPath: inst.integrityURL.path(percentEncoded: false)))
    check("the integrity check passes", inst.checkIntegrity() == .matches)

    // Swapping the exporter for something else has to be noticed.
    try! "#!/bin/sh\necho hacked\n".write(to: inst.exporterURL, atomically: true, encoding: .utf8)
    check("a swapped exporter is noticed", inst.checkIntegrity() == .changed)
    _ = try! inst.install()
    check("reinstalling repairs the integrity", inst.checkIntegrity() == .matches)

    let plan = inst.removalPlan()
    check("the removal plan sees our status line", plan.removesStatusLine)
    check("the removal plan sees the exporter", plan.removesExporter)

    let report = try! inst.uninstall(removingHistory: false)
    check("the statusLine key was removed", report.statusLineRemoved)
    check("the exporter was deleted", !FileManager.default.fileExists(
        atPath: inst.exporterURL.path(percentEncoded: false)))
    check("the hash was deleted", !FileManager.default.fileExists(
        atPath: inst.integrityURL.path(percentEncoded: false)))
    check("the status line is no longer ours", inst.statusLineState() == .absent)

    let text = settings(home)
    check("the neighbouring keys are intact after removal",
          text.contains("\"theme\": \"dark\"") && text.contains("\"language\": \"Russian\"")
          && text.contains("\"defaultMode\": \"auto\""))
    check("the neighbours keep their formatting", text.contains("  \"language\": \"Russian\""))
    check("the file is still valid JSON",
          (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil)
    check("no trailing comma is left behind", !text.contains(",\n}") && !text.contains(", }"))
    check("removal made a backup", report.backup != nil)
    if let backup = report.backup {
        let mode = (try! FileManager.default.attributesOfItem(
            atPath: backup.path(percentEncoded: false))[.posixPermissions] as! NSNumber).intValue
        check("the backup is locked down to 0600", mode == 0o600, "mode \(String(mode, radix: 8))")
    }
}

do {
    // Regression: a status line of OURS that is already installed must not read
    // as foreign. A live run showed "Another status line is already configured"
    // pointing at our own exporter — the culprit was not the code but an app
    // left over under the old name. This check catches that, and any future
    // drift between what we write into the config and what we compare against.
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("{}", to: home)

    _ = try! installer(home: home, template: template).install()

    // A fresh instance, as on the app's next launch.
    let fresh = installer(home: home, template: template)
    check("our own status line is recognised after installing", fresh.statusLineState() == .ours,
          "got \(fresh.statusLineState())")

    var foreignWarning = false
    if case .foreign = fresh.statusLineState() { foreignWarning = true }
    check("no foreign status line warning", !foreignWarning)

    let stored = ((try? JSONSerialization.jsonObject(
        with: Data(contentsOf: fresh.settingsURL)) as? [String: Any])
        .flatMap { ($0?["statusLine"] as? [String: Any])?["command"] as? String }) ?? ""
    check("the recorded path matches the computed one",
          stored == fresh.exporterURL.path(percentEncoded: false),
          "recorded [\(stored)], computed [\(fresh.exporterURL.path(percentEncoded: false))]")

    // Installing over our own install must break nothing.
    _ = try! fresh.install()
    check("reinstalling leaves the status line ours",
          fresh.statusLineState() == .ours)
}

do {
    // Removal must not touch a foreign status line.
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write(#"{"statusLine":{"type":"command","command":"/someone/else.sh"}}"#, to: home)
    let inst = installer(home: home, template: template)
    _ = try? inst.uninstall(removingHistory: false)
    check("a foreign status line is left alone", settings(home).contains("/someone/else.sh"))
}

do {
    // Backup rotation.
    let home = sandbox()
    let template = makeTemplate(in: home)
    makeContainer(in: home)
    write("{}", to: home)
    let inst = installer(home: home, template: template)
    for _ in 0..<8 { _ = try? inst.install() }
    let names = (try! FileManager.default.contentsOfDirectory(
        atPath: inst.claudeDirectory.path(percentEncoded: false)))
        .filter { $0.hasPrefix("settings.json.bak-") }
    check("no more than five backups are kept", names.count <= Installer.backupsKept,
          "found \(names.count)")
}

// MARK: - Usage estimate

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
    // A perfect straight line over four hours: R² should come out at one.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let f = Forecast.make(history: series(count: 25, stepMinutes: 10, from: 20, per: 1.6,
                                          resets: resets, now: now), window: window, now: now)
    check("a perfect line gives an R² of about one", (f.fitQuality ?? 0) > 0.99,
          "R² = \(f.fitQuality ?? -1)")
    check("a wide enough base names a date", describe(f.outcome) == "runsOut",
          "got \(describe(f.outcome))")
    check("the dashed line is drawn", f.showsProjection)
}

do {
    // Fewer than ten points — nothing to compute, however wide the base.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let f = Forecast.make(history: series(count: 9, stepMinutes: 30, from: 20, per: 4,
                                          resets: resets, now: now), window: window, now: now)
    check("nine points are rejected", describe(f.outcome) == "notEnoughData")
}

do {
    // A base shorter than two hours — rejected on span.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let f = Forecast.make(history: series(count: 20, stepMinutes: 5, from: 20, per: 2,
                                          resets: resets, now: now), window: window, now: now)
    check("a base of an hour and a half is rejected", describe(f.outcome) == "notEnoughData",
          "base \(Int(f.observationSpan / 60)) min, got \(describe(f.outcome))")
}

do {
    // Noise the line does not describe: R² below the threshold.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let saw: (Int) -> Double = { i in i % 2 == 0 ? -18 : 18 }
    let f = Forecast.make(history: series(count: 30, stepMinutes: 10, from: 30, per: 0.2,
                                          resets: resets, now: now, noise: saw),
                          window: window, now: now)
    check("a line that does not describe the data is rejected on R²",
          describe(f.outcome) == "notEnoughData", "R² = \(f.fitQuality ?? -1)")
}

do {
    // The important case: right after the weekly reset. The base is two hours
    // and the reset is nearly seven days out — no date may be named, but a
    // rate may.
    let resets = now.addingTimeInterval(6.9 * 24 * 3600)
    let window = LimitWindow(usedPercentage: 3, resetsAt: resets)
    let f = Forecast.make(history: series(count: 13, stepMinutes: 10, from: 1, per: 0.15,
                                          resets: resets, now: now), window: window, now: now)
    check("after a weekly reset — a rate without a date", describe(f.outcome) == "rateOnly",
          "got \(describe(f.outcome))")
    check("and there is a rate to show", f.hasRate)
    check("the dashed line is not drawn", !f.showsProjection)
    check("the rate is positive", (f.percentPerHour ?? 0) > 0)
}

do {
    // The base has grown to a day — the horizon now covers the whole week.
    let resets = now.addingTimeInterval(6 * 24 * 3600)
    let window = LimitWindow(usedPercentage: 10, resetsAt: resets)
    let f = Forecast.make(history: series(count: 40, stepMinutes: 40, from: 1, per: 0.22,
                                          resets: resets, now: now), window: window, now: now)
    check("a day-wide base reaches across the week",
          describe(f.outcome) != "rateOnly", "got \(describe(f.outcome))")
}

do {
    // A plateau: the slope is not positive.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 55, resetsAt: resets)
    let f = Forecast.make(history: series(count: 20, stepMinutes: 15, from: 55, per: 0,
                                          resets: resets, now: now), window: window, now: now)
    check("a plateau is recognised", describe(f.outcome) == "flat")
    check("no rate is shown on a plateau", !f.hasRate)
}

do {
    // Points from another window are filtered out entirely.
    let resets = now.addingTimeInterval(20 * 3600)
    let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
    let other = series(count: 30, stepMinutes: 10, from: 20, per: 1.5,
                       resets: resets.addingTimeInterval(-604800), now: now)
    let f = Forecast.make(history: other, window: window, now: now)
    check("points from a past window are discarded", f.points.isEmpty)
    check("and no estimate is built from them", describe(f.outcome) == "notEnoughData")
}

do {
    // Fast consumption, running out soon — the date falls inside the horizon.
    let resets = now.addingTimeInterval(5 * 24 * 3600)
    let window = LimitWindow(usedPercentage: 80, resetsAt: resets)
    let f = Forecast.make(history: series(count: 15, stepMinutes: 20, from: 60, per: 1.4,
                                          resets: resets, now: now), window: window, now: now)
    check("running out soon is named with a date", describe(f.outcome) == "runsOut",
          "got \(describe(f.outcome))")
    if case .runsOut(let date) = f.outcome {
        check("the date is not in the past", date >= now)
        let horizon = date.timeIntervalSince(now)
        check("the date is within ten base lengths",
              horizon <= f.observationSpan * Forecast.horizonMultiplier + 60,
              "horizon \(Int(horizon / 3600)) h on a base of \(Int(f.observationSpan / 3600)) h")
    }
}

print("\n\(failures == 0 ? "all checks passed" : "failures: \(failures)")")
exit(failures == 0 ? 0 : 1)
