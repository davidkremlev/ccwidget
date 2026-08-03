import Foundation
import Testing

/// Anchors the bundle the test resources live in.
final class TestBundleAnchor {}

/// The exporter, run rather than read.
///
/// It is the only part of this project that executes on someone's machine
/// dozens of times a minute, with their privileges, on input nobody controls.
/// Until now the whole of it was checked by `py_compile` in CI, which proves
/// the file is syntactically Python and nothing else. Section 3 lists seven
/// guarantees; every one of them is about behaviour.
///
/// Each check installs the real template through the real installer and runs
/// the result as a subprocess, so what is being exercised is the exporter as
/// it is actually rendered and shipped — the interpreter line, the substituted
/// directory, the permissions.
@Suite("Exporter")
struct ExporterTests {

    // MARK: Harness

    private struct Run {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private struct Installed {
        let exporter: URL
        let exchange: URL
        var snapshot: URL { exchange.appending(path: "snapshot.json") }
        var history: URL { exchange.appending(path: "history.jsonl") }
    }

    private func template() throws -> URL {
        let bundle = Bundle(for: TestBundleAnchor.self)
        return try #require(
            bundle.url(forResource: "ccwidget-export.py", withExtension: "template"),
            "the template is missing from the test bundle")
    }

    /// Installs through `Installer`, exactly as the app does. Rendering the
    /// template by hand here would check a second implementation of the
    /// substitution rather than the one that ships.
    private func install() throws -> Installed {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        return Installed(exporter: inst.exporterURL,
                         exchange: SnapshotStore.exchangeURL(home: home))
    }

    @discardableResult
    private func run(_ installed: Installed, stdin: Data) throws -> Run {
        let process = Process()
        process.executableURL = installed.exporter
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        // Write on a separate queue: a payload larger than the pipe buffer
        // would deadlock against a child that has stopped reading, which is
        // exactly what the megabyte check arranges.
        DispatchQueue.global().async {
            input.fileHandleForWriting.write(stdin)
            try? input.fileHandleForWriting.close()
        }
        let out = output.fileHandleForReading.readDataToEndOfFile()
        let err = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Run(status: process.terminationStatus,
                   stdout: String(decoding: out, as: UTF8.self),
                   stderr: String(decoding: err, as: UTF8.self))
    }

    private func payload(fiveHour: Int? = 21, sevenDay: Int? = 9,
                         resetsAt: Int = 1_700_100_000,
                         extra: String = "") -> Data {
        var limits: [String] = []
        if let fiveHour {
            limits.append(#""five_hour":{"used_percentage":\#(fiveHour),"resets_at":\#(resetsAt)}"#)
        }
        if let sevenDay {
            limits.append(#""seven_day":{"used_percentage":\#(sevenDay),"resets_at":\#(resetsAt)}"#)
        }
        return Data("""
        {"version":"2.1.220","session_id":"abcdef0123456789",
         "model":{"id":"claude-opus-5","display_name":"Opus 5"},
         "rate_limits":{\(limits.joined(separator: ","))},
         "context_window":{"used_percentage":25,"total_input_tokens":1000},
         "workspace":{"current_dir":"/Users/someone/Documents/secret-client/app"}
         \(extra)}
        """.utf8)
    }

    /// The exporter creates the exchange directory on its first run, so a
    /// check that plants something there beforehand has to create it first.
    /// Deliberately not folded into `install()`: the container check below
    /// depends on it *not* existing.
    private func existingExchange() throws -> Installed {
        let installed = try install()
        try FileManager.default.createDirectory(at: installed.exchange,
                                                withIntermediateDirectories: true)
        return installed
    }

    private func loadSnapshot(_ installed: Installed) throws -> Snapshot {
        try SnapshotStore(containerURL: installed.exchange).load()
    }

    // MARK: Section 3 — always exits 0, says nothing

    /// A non-zero exit or a stray byte on stdout lands in the user's status
    /// line, under the prompt, on every redraw. The exporter's failures are
    /// its own business.
    @Test("Whatever it is fed, it exits 0 and prints nothing",
          arguments: [
            ("valid input", #"{"version":"2.1.220"}"#),
            ("empty input", ""),
            ("not JSON at all", "}{ nonsense"),
            ("JSON that is not an object", "[1, 2, 3]"),
            ("JSON that is a bare string", "\"hello\""),
            ("a null", "null"),
            ("truncated JSON", #"{"version":"#),
            ("nested nulls where objects belong", #"{"rate_limits":null,"model":null}"#),
          ])
    func alwaysSilentAndSuccessful(name: String, input: String) throws {
        let installed = try install()
        let result = try run(installed, stdin: Data(input.utf8))
        #expect(result.status == 0, "\(name): exit \(result.status)")
        #expect(result.stdout.isEmpty, "\(name): stdout \"\(result.stdout)\"")
        #expect(result.stderr.isEmpty, "\(name): stderr \"\(result.stderr)\"")
    }

    /// Section 3: missing fields are normal. The status line sends a different
    /// shape in the first seconds of a session, and no lookup may fail on it.
    ///
    /// This used to end by loading the snapshot such an input produced and
    /// checking its limits were nil — which is to say it required the exporter
    /// to write a snapshot with no numbers in it. That is the shape a session
    /// starts with, and writing it is what emptied the widget on every restart
    /// of Claude Code. The check was holding the defect in place, so it is
    /// rewritten rather than joined by a second one: no lookup fails, the
    /// exporter says nothing, and nothing is written because there is nothing
    /// to say.
    @Test("An empty object is handled and produces nothing")
    func emptyObjectIsHandled() throws {
        let installed = try install()
        let result = try run(installed, stdin: Data("{}".utf8))
        #expect(result.status == 0)
        #expect(result.stdout.isEmpty && result.stderr.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: installed.snapshot.path),
                "an input with no numbers in it wrote a snapshot with no numbers in it")
    }

    // MARK: Section 3 — the input cap

    /// A gigabyte of input once landed in the snapshot whole and killed the
    /// widget extension on read. The cap is a megabyte; the status line sends
    /// kilobytes.
    @Test("Input past a megabyte is refused, and nothing is written")
    func oversizedInputIsRefused() throws {
        let installed = try install()
        let filler = String(repeating: "x", count: 1 << 20)
        let result = try run(installed, stdin: Data(#"{"version":"\#(filler)"}"#.utf8))

        #expect(result.status == 0, "it still exits quietly")
        #expect(!FileManager.default.fileExists(atPath: installed.snapshot.path),
                "an oversized payload must not reach the snapshot")
    }

    @Test("Input just under the cap is accepted")
    func inputUnderTheCapIsAccepted() throws {
        let installed = try install()
        // Real numbers with padding around them. The padding alone used to do,
        // when any payload produced a snapshot; now a snapshot is proof of
        // acceptance only if there was something in it worth writing.
        //
        // Stay well clear of the boundary so this checks the cap rather than an
        // off-by-one in the fixture.
        let filler = String(repeating: "x", count: (1 << 20) - 1024)
        let result = try run(installed, stdin: payload(extra: #","padding":"\#(filler)""#))

        #expect(result.status == 0)
        #expect(FileManager.default.fileExists(atPath: installed.snapshot.path),
                "a large but legal payload is still data")
    }

    // MARK: Section 3 — symlinks

    /// The exporter writes with the user's privileges on every redraw. A
    /// symlink planted where its temporary file goes would make it overwrite
    /// whatever is on the other end, once a second, for as long as Claude Code
    /// is open.
    @Test("A symlink planted at the temporary file is not followed")
    func temporaryFileSymlinkIsRefused() throws {
        let installed = try existingExchange()
        let victim = installed.exchange.appending(path: "victim.txt")
        try "PRECIOUS DATA".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: installed.exchange.appending(path: "snapshot.json.tmp"),
            withDestinationURL: victim)

        _ = try run(installed, stdin: payload())

        #expect(try String(contentsOf: victim, encoding: .utf8) == "PRECIOUS DATA",
                "the exporter wrote through the link")
        #expect(try loadSnapshot(installed).limits.sevenDay?.usedPercentage == 9,
                "and it still did its job")
    }

    /// The same for the history, which is appended to rather than replaced —
    /// a different code path with the same consequence.
    @Test("A symlink planted at the history is not appended through")
    func historySymlinkIsRefused() throws {
        let installed = try existingExchange()
        let victim = installed.exchange.appending(path: "victim.txt")
        try "PRECIOUS DATA".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: installed.history, withDestinationURL: victim)

        _ = try run(installed, stdin: payload())

        #expect(try String(contentsOf: victim, encoding: .utf8) == "PRECIOUS DATA",
                "the exporter appended through the link")
    }

    /// A symlink at the snapshot itself is replaced rather than written
    /// through, because `os.replace` renames over the link.
    @Test("A symlink at the snapshot is replaced, not followed")
    func snapshotSymlinkIsReplaced() throws {
        let installed = try existingExchange()
        let victim = installed.exchange.appending(path: "victim.txt")
        try "PRECIOUS DATA".write(to: victim, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: installed.snapshot, withDestinationURL: victim)

        _ = try run(installed, stdin: payload())

        #expect(try String(contentsOf: victim, encoding: .utf8) == "PRECIOUS DATA")
        #expect(!isSymlink(installed.snapshot), "the link was replaced by a regular file")
        #expect(try loadSnapshot(installed).limits.sevenDay?.usedPercentage == 9)
    }

    // MARK: Section 3 — atomicity, as far as it is observable

    /// A race cannot be reproduced on demand, so what is checked here is what
    /// atomicity leaves behind: the target is a regular file with the mode the
    /// exporter chose, and no temporary file survives for the next run to trip
    /// over. The absence of a partial read is the part that stays an argument
    /// about `os.replace` rather than a check.
    @Test("Nothing is left behind, and the result is a private regular file")
    func writeLeavesNoDebris() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload())

        #expect(!FileManager.default.fileExists(
            atPath: installed.exchange.appending(path: "snapshot.json.tmp").path),
                "a temporary file survived the write")
        #expect(!isSymlink(installed.snapshot))
        #expect(posixMode(of: installed.snapshot) == 0o600,
                "mode \(String(posixMode(of: installed.snapshot), radix: 8))")
        #expect(posixMode(of: installed.history) == 0o600,
                "mode \(String(posixMode(of: installed.history), radix: 8))")
    }

    // MARK: Section 4 — only what is displayed

    /// The snapshot lives in a directory other processes of this user can
    /// read. A full working directory names the client whose code is open,
    /// and no size of this widget ever displays it.
    @Test("The snapshot carries the project name and not the path to it")
    func snapshotIsMinimal() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload())

        let text = try String(contentsOf: installed.snapshot, encoding: .utf8)
        #expect(!text.contains("/Users/someone"), "a user path reached the snapshot: \(text)")
        #expect(!text.contains("secret-client/app"), "the working directory reached the snapshot")
        #expect(text.contains("\"name\": \"app\"") || text.contains("\"name\":\"app\""),
                "the project name is what is kept: \(text)")
    }

    /// A session identifier is enough to correlate two files; the widget shows
    /// eight characters of it and that is all it needs.
    @Test("The session identifier is truncated to eight characters")
    func sessionIdentifierIsTruncated() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload())

        let session = try #require(try loadSnapshot(installed).sessionId)
        #expect(session == "abcdef01", "got \(session)")
    }

    /// The written object is fixed by section 4. A future edit adding a field
    /// has to come here first, which is the point.
    @Test("The snapshot has exactly the documented shape")
    func snapshotShapeIsFixed() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload())

        let data = try Data(contentsOf: installed.snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "schemaVersion", "capturedAt", "sessionId", "claudeCodeVersion",
            "model", "project", "limits", "context", "cost",
        ], "got \(Set(object.keys).sorted())")

        let project = try #require(object["project"] as? [String: Any])
        #expect(Set(project.keys) == ["name"], "got \(Set(project.keys).sorted())")
    }

    // MARK: Section 7 — history deduplication

    /// The status line redraws on every keystroke of the model's answer —
    /// fifteen calls in two and a half minutes, measured. Writing a history
    /// line for each would fill the file with the same number.
    @Test("Two identical readings in a row produce one history line")
    func identicalReadingsAreDeduplicated() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload())
        _ = try run(installed, stdin: payload())

        let lines = try String(contentsOf: installed.history, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1, "got \(lines.count) lines")
    }

    @Test("A changed percentage is always recorded")
    func changedPercentageIsRecorded() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload(sevenDay: 9))
        _ = try run(installed, stdin: payload(sevenDay: 10))

        let lines = try String(contentsOf: installed.history, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2, "got \(lines.count) lines")
    }

    /// A new reset moment means a new window, and the first point of a window
    /// is what the estimate needs most.
    @Test("A changed reset moment is always recorded")
    func changedResetIsRecorded() throws {
        let installed = try install()
        _ = try run(installed, stdin: payload(resetsAt: 1_700_100_000))
        _ = try run(installed, stdin: payload(resetsAt: 1_700_700_000))

        let lines = try String(contentsOf: installed.history, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2, "got \(lines.count) lines")
    }

    /// Ten minutes of the same number is still worth a point: a plateau is
    /// information, and the estimate reads flatness from the gaps.
    @Test("An identical reading after ten minutes is recorded anyway")
    func staleIdenticalReadingIsRecorded() throws {
        let installed = try existingExchange()
        let old = Int(Date().timeIntervalSince1970) - 700
        try #"{"t":\#(old),"sevenDay":9,"resetsAt":1700100000}"#
            .appending("\n")
            .write(to: installed.history, atomically: true, encoding: .utf8)

        _ = try run(installed, stdin: payload())

        let lines = try String(contentsOf: installed.history, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2, "got \(lines.count) lines")
    }

    @Test("The same reading a minute later is not recorded")
    func recentIdenticalReadingIsSkipped() throws {
        let installed = try existingExchange()
        let recent = Int(Date().timeIntervalSince1970) - 60
        try #"{"t":\#(recent),"sevenDay":9,"resetsAt":1700100000}"#
            .appending("\n")
            .write(to: installed.history, atomically: true, encoding: .utf8)

        _ = try run(installed, stdin: payload())

        let lines = try String(contentsOf: installed.history, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1, "got \(lines.count) lines")
    }

    /// Truncation lives in the exporter rather than in the app because the app
    /// window may never be opened, and then the limit would never apply.
    @Test("The exporter truncates the history it has grown")
    func exporterTruncatesHistory() throws {
        let installed = try existingExchange()
        let old = Int(Date().timeIntervalSince1970) - 700
        let seeded = (0..<2500)
            .map { #"{"t":\#(old - 2500 + $0),"sevenDay":9,"resetsAt":1700100000}"# }
            .joined(separator: "\n")
        try (seeded + "\n").write(to: installed.history, atomically: true, encoding: .utf8)

        _ = try run(installed, stdin: payload())

        let lines = try String(contentsOf: installed.history, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1000, "got \(lines.count) lines")
        #expect(lines.last?.contains("\"sevenDay\": 9") == true
                || lines.last?.contains("\"sevenDay\":9") == true,
                "the newest line survives: \(lines.last ?? "—")")
    }

    // MARK: The container

    /// The system creates the extension's container the first time the widget
    /// runs, and creating it from outside is forbidden — `containermanagerd`
    /// may decide the directory is foreign and move it. No parent means the
    /// widget has never run, and the exporter has nowhere legitimate to write.
    @Test("With no container, nothing is created and nothing is written")
    func noContainerMeansNoWrite() throws {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let inst = installer(home: home, template: try template())
        _ = try inst.install()
        let exchange = SnapshotStore.exchangeURL(home: home)

        // Remove the container the system had made, leaving the exporter
        // pointing at a path whose parent is gone.
        try FileManager.default.removeItem(at: SnapshotStore.widgetContainerURL(home: home))

        let installed = Installed(exporter: inst.exporterURL, exchange: exchange)
        let result = try run(installed, stdin: payload())

        #expect(result.status == 0)
        #expect(!FileManager.default.fileExists(atPath: exchange.path),
                "the exporter created a container it must not create")
    }

    // MARK: A session that has only just started

    /// What Claude Code sends before the first prompt of a session: no
    /// `rate_limits` key at all, and a context window whose usage is `null`.
    /// Taken from a real status-line log — every session begins with one of
    /// these, and there are two in twenty-nine lines of it.
    private func sessionStartPayload() -> Data {
        Data("""
        {"version":"2.1.220","session_id":"fedcba9876543210",
         "model":{"id":"claude-opus-5","display_name":"Opus 5"},
         "context_window":{"used_percentage":null,"current_usage":null,
                           "context_window_size":1000000},
         "workspace":{"current_dir":"/Users/someone/Documents/app"}}
        """.utf8)
    }

    /// Restarting Claude Code emptied the widget.
    ///
    /// The exporter replaces `snapshot.json` on every status-line redraw, and
    /// a session's first redraw carries no limits. So the numbers a person was
    /// looking at were overwritten with nothing, and stayed that way until the
    /// first prompt of the new session — every restart, every time.
    ///
    /// A payload without `rate_limits` does not say the limits are zero. It
    /// says this redraw knows nothing about them, which is not news and must
    /// not replace what is known. The snapshot keeps ageing meanwhile, and the
    /// age is what tells the truth about how current it is.
    @Test("A session starting does not wipe the numbers")
    func sessionStartKeepsTheLastNumbers() throws {
        let installed = try install()

        try run(installed, stdin: payload(fiveHour: 21, sevenDay: 9))
        let before = try loadSnapshot(installed)
        #expect(before.limits.sevenDay?.usedPercentage == 9, "the fixture is wrong")

        try run(installed, stdin: sessionStartPayload())

        let after = try loadSnapshot(installed)
        #expect(after.limits.sevenDay?.usedPercentage == 9,
                "a session start replaced the weekly number with nothing")
        #expect(after.limits.fiveHour?.usedPercentage == 21,
                "a session start replaced the five-hour number with nothing")
        #expect(after.context?.usedPercentage == 25,
                "and the context with nothing")
    }

    /// The same payload before anything has ever been written leaves no
    /// snapshot at all, which is the state the window already has words for —
    /// rather than a snapshot full of dashes that looks like data.
    @Test("A session starting before any data writes nothing")
    func sessionStartOnAnEmptyExchangeWritesNothing() throws {
        let installed = try existingExchange()
        try run(installed, stdin: sessionStartPayload())
        #expect(!FileManager.default.fileExists(atPath: installed.snapshot.path),
                "a snapshot with no numbers in it was written")
    }
}
