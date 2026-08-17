import Foundation
import Testing

/// Installing a widget must not cost somebody their prompt.
///
/// The exporter prints nothing of its own, so taking the `statusLine` key over
/// left the line blank — and for an audience running `ccstatusline` or a script
/// of their own, that is a bad trade dressed up as a feature. `SPEC` 13 filed
/// composition under "version 2" and the cost was already being paid before
/// then: the uninstaller had to be taught not to delete a wrapper that chains
/// the exporter, which means people who do this were in the model already.
///
/// What is checked here is the whole round trip, because every part of it can
/// be right while the trip is broken: the command is captured at install,
/// substituted into the exporter as a literal, read back out of the exporter
/// when it is needed again, run with the same input the status line sent, and
/// put back as the `statusLine` on removal.
@Suite("Sharing the status line")
struct StatusLineSharingTests {

    private func template() throws -> URL {
        let bundle = Bundle(for: TestBundleAnchor.self)
        return try #require(
            bundle.url(forResource: "ccwidget-export.py", withExtension: "template"),
            "the template is missing from the test bundle")
    }

    private func settingsWithStatusLine(_ command: String, extra: String = "") -> String {
        """
        {
          "theme": "dark",
          "statusLine": { "type": "command", "command": \(quoted(command))\(extra) }
        }
        """
    }

    private func quoted(_ value: String) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    // MARK: What gets captured

    /// A command with quotes in it, because that is what a real one looks like:
    /// the status line documentation's own example is an inline `jq` pipeline.
    /// The literal goes into a Python file that runs on every redraw, so a
    /// value that escapes its quotes is a code-injection sink, and the round
    /// trip is the property — not "it looks about right in the file".
    @Test("A command survives the trip into the exporter and back out",
          arguments: [
            "/usr/local/bin/my-statusline",
            #"jq -r '"[\(.model.display_name)] \(.workspace.current_dir)"'"#,
            #"sh -c 'printf "%s" "$(date)"'"#,
            "echo 'don'\\''t'",
            "echo \"a\tb\"",
            "printf '%s' 'ünïcødé ↯'",
          ])
    func aCommandSurvivesTheRoundTrip(command: String) throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine(command), to: home)
        let inst = installer(home: home, template: try template())
        #expect(inst.commandToChain() == command, "the foreign command is what would be chained")

        _ = try inst.install()
        #expect(inst.chainedCommand() == command,
                "read back out of the exporter, it is the same string it went in as")
        #expect(inst.statusLineState() == .ours, "and the status line is now ours")
    }

    /// The case that made this worth reading back out of the file rather than
    /// keeping it anywhere else. By the second install the status line is ours,
    /// so asking what to chain would answer "ourselves" — and writing that
    /// would either lose the command or make the exporter call itself for ever.
    /// `reinstall.sh` runs install dozens of times a day.
    @Test("Reinstalling keeps the chain instead of eating it")
    func reinstallingKeepsTheChain() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine("/usr/local/bin/theirs"), to: home)
        let inst = installer(home: home, template: try template())

        _ = try inst.install()
        _ = try inst.install()
        _ = try inst.install()

        #expect(inst.chainedCommand() == "/usr/local/bin/theirs",
                "three installs later the command is still there")
        let body = try String(contentsOf: inst.exporterURL, encoding: .utf8)
        #expect(!body.contains(inst.exporterURL.path(percentEncoded: false) + "\""),
                "and the exporter is not chaining itself")
    }

    @Test("With nothing configured, nothing is chained")
    func nothingConfiguredChainsNothing() throws {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let inst = installer(home: home, template: try template())
        #expect(inst.commandToChain() == nil)
        _ = try inst.install()
        #expect(inst.chainedCommand() == nil)
        let body = try String(contentsOf: inst.exporterURL, encoding: .utf8)
        #expect(body.contains("CHAINED = None"), "the literal says so in the file")
    }

    // MARK: What the exporter does with it

    /// The point of the whole exercise: their command runs, gets the input
    /// Claude Code sent, and its output is what lands under the prompt.
    @Test("The chained command runs, is given the same input, and is printed")
    func theChainedCommandRunsAndIsPrinted() throws {
        let home = sandbox()
        makeContainer(in: home)
        // Reads the JSON on its stdin and prints one field of it, so a check
        // that passes proves the input arrived rather than that something ran.
        let theirs = #"python3 -c 'import json,sys; print("model:" + json.load(sys.stdin)["model"]["display_name"])'"#
        write(settingsWithStatusLine(theirs), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)

        let result = try runExporter(inst.exporterURL, stdin: Self.payload)

        #expect(result.status == 0, "the exporter never fails the prompt")
        #expect(result.stdout == "model:Opus 5\n",
                "their output, and only their output: \(result.stdout.debugDescription)")
        // And our own half still happened.
        let snapshot = try SnapshotStore(containerURL: exchange).load()
        #expect(snapshot.limits.sevenDay?.usedPercentage == 62,
                "the widget still got its data while the other line was rendered")
    }

    /// A chained command that is broken must not break the prompt — and must
    /// not be silent about it either. Section 6.1: a silent fallback turns a
    /// defect into an absence, and here the absence is somebody's status line,
    /// which they will blame on this widget.
    @Test("A broken chained command is survived and recorded",
          arguments: [("a command that does not exist", "definitely-not-a-command-anywhere", "exited"),
                      ("one that fails", "sh -c 'exit 3'", "exited 3")])
    func aBrokenChainIsSurvivedAndRecorded(name: String, command: String, says: String) throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine(command), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)

        let result = try runExporter(inst.exporterURL, stdin: Self.payload)
        #expect(result.status == 0, "\(name): the prompt survives it")

        let notice = exchange.appending(path: "chain-failed.json")
        let text = try #require(try? String(contentsOf: notice, encoding: .utf8),
                                "\(name): nothing was recorded, so the failure is invisible")
        #expect(text.contains(says), "\(name): the notice says what happened — \(text)")
        #expect(text.contains("since"), "\(name): and since when")
    }

    /// And it clears itself, or the window would go on reporting a failure that
    /// stopped happening.
    @Test("A chain that starts working again clears the notice")
    func aWorkingChainClearsTheNotice() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine("sh -c 'exit 1'"), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        _ = try runExporter(inst.exporterURL, stdin: Self.payload)
        let notice = exchange.appending(path: "chain-failed.json")
        #expect(FileManager.default.fileExists(atPath: notice.path(percentEncoded: false)))

        // Reinstall over a working command, the way somebody fixing their
        // script would end up doing.
        write(settingsWithStatusLine("echo fixed"), to: home)
        _ = try inst.install()
        let after = try runExporter(inst.exporterURL, stdin: Self.payload)

        #expect(after.stdout == "fixed\n")
        #expect(!FileManager.default.fileExists(atPath: notice.path(percentEncoded: false)),
                "the notice outlived the failure it described")
    }

    // MARK: What installing and removing do to the rest of the key

    /// Installation changes `command` and nothing else. It used to write a
    /// whole new object, which threw away `padding` and anything else
    /// documented — and then removal could not put back what installation had
    /// not kept.
    @Test("Installing leaves the rest of the statusLine object alone")
    func installingKeepsTheOtherFields() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine("/usr/local/bin/theirs",
                                     extra: #", "padding": 4, "refreshInterval": 5"#), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()

        let line = try #require(parseJSON(settings(home))?["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == inst.exporterURL.path(percentEncoded: false))
        #expect(line["padding"] as? Int == 4, "somebody's padding survived the install")
        #expect(line["refreshInterval"] as? Int == 5, "and so did their refresh interval")
    }

    /// The inverse, and the reason the chain is worth capturing at all: taking
    /// the widget away gives the prompt back.
    @Test("Removing puts their status line back, with its other fields")
    func removingRestoresTheirStatusLine() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine("/usr/local/bin/theirs", extra: #", "padding": 4"#), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()

        let plan = inst.removalPlan()
        #expect(plan.restoresStatusLine == "/usr/local/bin/theirs",
                "the plan says so before the button is pressed")
        #expect(!plan.removesStatusLine, "and does not also claim the key is deleted")

        let report = try inst.uninstall(removingHistory: false)
        #expect(report.statusLineRestored == "/usr/local/bin/theirs")
        #expect(!report.statusLineRemoved, "restored and removed are not both true")

        let line = try #require(parseJSON(settings(home))?["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "/usr/local/bin/theirs",
                "their command is what the status line runs again")
        #expect(line["padding"] as? Int == 4)
        #expect(settings(home).contains("\"theme\": \"dark\""), "and the neighbours are untouched")
        #expect(!FileManager.default.fileExists(atPath: inst.exporterURL.path(percentEncoded: false)),
                "the exporter is gone, so nothing chains anything")
    }

    /// With nothing chained the old behaviour is the right one, and the two
    /// paths must not be confused: a key deleted where one should have been
    /// restored loses somebody's prompt, and a key restored where one should
    /// have been deleted leaves ours behind.
    @Test("With nothing chained, removal deletes the key as before")
    func removingWithNoChainDeletesTheKey() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(#"{"theme": "dark"}"#, to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()

        #expect(inst.removalPlan().restoresStatusLine == nil)
        #expect(inst.removalPlan().removesStatusLine)

        let report = try inst.uninstall(removingHistory: false)
        #expect(report.statusLineRestored == nil)
        #expect(report.statusLineRemoved)
        #expect(!settings(home).contains("statusLine"))
        #expect(settings(home).contains("\"theme\": \"dark\""))
    }

    /// The notice has to be readable by something, or it is a file nobody
    /// opens. `ccwidget-dump` is what reads it, through this type.
    @Test("The recorded failure decodes into something a reader can print")
    func theNoticeDecodes() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine("sh -c 'exit 4'"), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        _ = try runExporter(inst.exporterURL, stdin: Self.payload)

        let notice = try #require(SnapshotStore(containerURL: exchange).loadChainNotice(),
                                  "the file is there but nothing can read it")
        #expect(notice.reason.contains("exited 4"))
        #expect(notice.age() < 60, "the moment it records is now, not the epoch")
    }

    /// And it goes when the widget goes. The same rule as the skip notice, which
    /// was found surviving a request to delete the data.
    @Test("Removing the history takes the chain notice with it")
    func removingHistoryTakesTheChainNotice() throws {
        let home = sandbox()
        makeContainer(in: home)
        write(settingsWithStatusLine("sh -c 'exit 4'"), to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        _ = try runExporter(inst.exporterURL, stdin: Self.payload)
        let store = SnapshotStore(containerURL: exchange)
        #expect(store.loadChainNotice() != nil, "there is something to remove")

        _ = try inst.uninstall(removingHistory: true)
        #expect(!FileManager.default.fileExists(atPath: store.chainNoticeURL.path(percentEncoded: false)),
                "the notice outlived the widget")
    }

    // MARK: The template that actually ships

    /// Every check above uses the stand-in template from `Sandbox.swift`. This
    /// one uses the file the app ships, and it exists because the difference
    /// between them is where a defect hid for exactly one release.
    ///
    /// The stand-in carried `# Written by ccwidget __VERSION__` with nothing
    /// after it. The real template carried a sentence after the version, and the
    /// code reading the stamp back took that sentence's full stop for part of
    /// the number — so the window told everybody their exporter was out of date,
    /// for ever, and the button that rewrites it changed nothing. Every check
    /// passed, because none of them read the file that ships.
    @Test("The version round-trips through the template the app actually ships")
    func theRealTemplateStampsAVersionThatReadsBack() throws {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let inst = installer(home: home, template: try template()).asVersion("1.2.3")

        _ = try inst.install()

        #expect(inst.installedExporterVersion() == "1.2.3",
                "the stamp reads back as the version that was written, exactly")
        #expect(inst.checkIntegrity() == .matches,
                "so a freshly written exporter is not reported as out of date")
        #expect(!inst.checkIntegrity().raisesBanner,
                "and the window has nothing to warn about")
    }

    /// And the state it is there to detect still works with the real template.
    @Test("The real template still lets an upgrade be noticed")
    func theRealTemplateStillDetectsAnUpgrade() throws {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let template = try template()
        _ = try installer(home: home, template: template).asVersion("1.2.3").install()

        let newer = installer(home: home, template: template).asVersion("1.3.0")
        #expect(newer.checkIntegrity() == .outdated)
        _ = try newer.install()
        #expect(newer.checkIntegrity() == .matches)
    }

    // MARK: Helpers

    private struct Run {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func runExporter(_ exporter: URL, stdin: Data) throws -> Run {
        let process = Process()
        process.executableURL = exporter
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: stdin)
        try input.fileHandleForWriting.close()
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus,
                   stdout: String(decoding: out, as: UTF8.self),
                   stderr: String(decoding: err, as: UTF8.self))
    }

    private static let payload = Data("""
        {"session_id": "abcdef1234", "version": "2.1.223",
         "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
         "workspace": {"current_dir": "/tmp/thing"},
         "context_window": {"used_percentage": 23.5, "total_input_tokens": 62777,
                            "context_window_size": 1000000},
         "cost": {"total_cost_usd": 1.13},
         "rate_limits": {"five_hour": {"used_percentage": 21, "resets_at": 1700100000},
                         "seven_day": {"used_percentage": 62, "resets_at": 1700259200}}}
        """.utf8)
}
