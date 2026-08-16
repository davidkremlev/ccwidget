import Foundation
import Testing

/// Conditions the installer's own comments state, and nothing asserted.
///
/// The installer drops an executable into a path the status line runs on every
/// redraw and edits a configuration file it did not write. Most of what makes
/// that acceptable is stated in prose beside the code — which interpreter, at
/// what permissions, through which link — and prose does not fail.
@Suite("Installer conditions")
struct InstallerConditionsTests {

    // MARK: The interpreter

    /// The one thing a clean account was going to test by hand. On a fresh
    /// macOS `/usr/bin/python3` exists and is executable and is a stub that
    /// offers to install the Command Line Tools instead of running — so
    /// checking that the file is there proves nothing, and the exporter would
    /// silently do nothing while onboarding waited forever.
    @Test("The interpreter is the first candidate that answers, not the first that exists")
    func interpreterIsProbedNotAssumed() throws {
        let home = sandbox()
        var inst = installer(home: home, template: makeTemplate(in: home))

        // Picked by answering, not by existing — which is the distinction this
        // whole check is about, and it was picked the wrong way until a CI
        // runner turned out to be the machine the comment above describes.
        // There `/usr/bin/python3` exists and is executable and does not run,
        // so choosing the first executable chose the stub, and the check then
        // demanded exactly the behaviour it exists to forbid.
        let working = try #require(inst.findInterpreter(),
                                   "no working interpreter on this machine to check against")

        inst.interpreterCandidates = [
            URL(filePath: "/nonexistent/python3"),   // not there at all
            URL(filePath: "/usr/bin/false"),         // there, executable, wrong answer
            working,
        ]
        #expect(inst.findInterpreter() == working,
                "got \(String(describing: inst.findInterpreter()))")
    }

    /// A candidate that exits 0 but is not Python 3 is still not an
    /// interpreter. `/bin/echo` is the shape of that mistake: it runs, it
    /// succeeds, it prints something that is not "3".
    @Test("Something that runs and answers wrongly is not accepted")
    func wrongAnswerIsRejected() {
        let home = sandbox()
        var inst = installer(home: home, template: makeTemplate(in: home))
        inst.interpreterCandidates = [URL(filePath: "/bin/echo")]
        #expect(inst.findInterpreter() == nil)
    }

    /// The order is a security decision, not a preference. `/usr/bin/python3`
    /// is owned by root; `/opt/homebrew/bin` is owned by the user, and the
    /// exporter runs dozens of times a minute — taking its interpreter from a
    /// directory any process of this user can write to widens the attack
    /// surface for nothing.
    @Test("The system interpreter is tried before anything under a user-writable prefix")
    func systemInterpreterComesFirst() throws {
        let candidates = Installer.defaultInterpreters.map { $0.path(percentEncoded: false) }
        let system = try #require(candidates.firstIndex(of: "/usr/bin/python3"),
                                  "the system interpreter is not a candidate at all")
        for (index, path) in candidates.enumerated() where path.hasPrefix("/opt/") || path.hasPrefix("/usr/local/") {
            #expect(index > system, "\(path) is tried before /usr/bin/python3")
        }
    }

    // MARK: The directory

    /// A directory we create is ours to close. `~/.claude` holds the
    /// configuration and, after installing, an executable that runs on every
    /// redraw; the default umask would leave both group- and world-readable.
    @Test("A directory we create is created closed")
    func createdDirectoryIsPrivate() throws {
        let home = sandbox()
        makeContainer(in: home)
        // No write() here: the point is that ~/.claude does not exist yet.
        let inst = installer(home: home, template: makeTemplate(in: home))
        #expect(!FileManager.default.fileExists(atPath: inst.claudeDirectory.path))

        _ = try inst.install()

        #expect(posixMode(of: inst.claudeDirectory) == 0o700,
                "mode \(String(posixMode(of: inst.claudeDirectory), radix: 8))")
    }

    /// And a directory that was already there is not ours to change. Someone
    /// who deliberately made `~/.claude` group-readable — a shared machine, a
    /// team account — did not ask us to reconsider.
    @Test("A directory that already exists keeps its own permissions")
    func existingDirectoryIsLeftAlone() throws {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: inst.claudeDirectory.path)

        _ = try inst.install()

        #expect(posixMode(of: inst.claudeDirectory) == 0o755,
                "mode \(String(posixMode(of: inst.claudeDirectory), radix: 8))")
    }

    // MARK: The symlink that cannot be preserved

    /// `settings.json` pointing into a dotfiles repository is the case the
    /// link handling exists for, and it has a second half nothing asserted:
    /// a link whose target cannot be written. Installing there would replace
    /// the link with a regular file and quietly detach the config from the
    /// repository it lives in, so onboarding has to say so *before* the button
    /// is pressed rather than report it afterwards.
    @Test("A link whose target cannot be written is reported before installing")
    func unwritableLinkTargetIsFlagged() throws {
        let home = sandbox()
        makeContainer(in: home)
        let vault = home.appending(path: "vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let real = vault.appending(path: "settings.json")
        try "{\n  \"theme\": \"dark\"\n}\n".write(to: real, atomically: true, encoding: .utf8)

        try FileManager.default.createDirectory(at: home.appending(path: ".claude"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: ".claude/settings.json"), withDestinationURL: real)

        // An atomic write needs to create a temporary file beside the target,
        // so it is the directory that has to be writable.
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: vault.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: vault.path)
        }

        let preflight = installer(home: home, template: makeTemplate(in: home)).preflight()
        #expect(preflight.settingsLinkTarget != nil, "the link itself is seen")
        #expect(preflight.canPreserveLink == false,
                "an unwritable target must not be reported as preservable")
    }

    @Test("A link whose target can be written is reported as preservable")
    func writableLinkTargetIsFine() throws {
        let home = sandbox()
        makeContainer(in: home)
        let real = home.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "{}".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appending(path: ".claude"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: ".claude/settings.json"), withDestinationURL: real)

        let preflight = installer(home: home, template: makeTemplate(in: home)).preflight()
        #expect(preflight.settingsLinkTarget != nil)
        #expect(preflight.canPreserveLink)
    }

    // MARK: The manual instructions

    /// Offered to anyone who would rather not let an app edit their config,
    /// and therefore pasted into a terminal by hand. The comment beside them
    /// explains why they show the finished line instead of a `sed` command: a
    /// path containing `|` breaks the delimiter and one containing a quote
    /// breaks the literal inside the script. The equivalent property for the
    /// generated Python literal is checked; this one was not.
    @Test("The manual instructions survive a path that would break a shell",
          arguments: ["/tmp/a|b", "/tmp/a'b", "/tmp/a\"b", "/tmp/a b",
                      "/tmp/a$b", "/tmp/a`b", "/tmp/a\nb"])
    func manualInstructionsSurviveHostilePaths(hostile: String) throws {
        let inst = installer(home: URL(filePath: hostile), template: makeTemplate(in: sandbox()))
        let text = inst.manualInstructions()

        #expect(!text.contains("sed "), "the instructions grew a sed command")

        // The property is not "the path appears verbatim" — it must not, when
        // the path contains a quote. It is that the line a reader is told to
        // paste parses back into exactly the path we meant. Asking for the raw
        // substring is the symptom check that an earlier version of this made,
        // and it failed on the very case it exists for.
        // The key, not the value: `"type": "command"` sits two lines above and
        // matches a naive search for the word.
        let line = try #require(
            text.split(separator: "\n").first {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("\"command\":")
            },
            "no command line in the instructions")
        let fragment = "{" + line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",")) + "}"

        let parsed = try? JSONSerialization.jsonObject(with: Data(fragment.utf8)) as? [String: Any]
        let command = try #require((parsed ?? nil)?["command"] as? String,
                                   "the pasted line is not valid JSON: \(fragment)")
        #expect(command == inst.exporterURL.path(percentEncoded: false),
                "the path came back as \(command)")
    }
}

/// The rule from section 8 that the widget is built around: every row shows
/// consumption, and the bar beside a number describes the same quantity as the
/// number.
///
/// This was a real defect — the bars for the two limits emptied as usage grew
/// while the numbers filled — and it is checkable without rendering anything.
@Suite("Polarity")
struct PolarityTests {

    private func entry(fiveHour: Int?, sevenDay: Int?, context: Int?,
                       age: TimeInterval = 0) -> CCWidgetEntry {
        let now = Date()
        let captured = now.addingTimeInterval(-age)
        let snapshot = Snapshot(
            schemaVersion: 1, capturedAt: captured, sessionId: nil, claudeCodeVersion: nil,
            model: nil, project: nil,
            limits: Limits(
                fiveHour: fiveHour.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(3600)) },
                sevenDay: sevenDay.map { LimitWindow(usedPercentage: $0, resetsAt: now.addingTimeInterval(86400)) }),
            context: ContextInfo(usedPercentage: context, totalInputTokens: nil,
                                 windowSize: nil, cacheHitRatio: nil),
            cost: nil)
        return CCWidgetEntry(date: now, snapshot: snapshot,
                             failure: nil, forecast: nil)
    }

    /// One column, one direction. The number says how much is used; the bar
    /// has to fill by the same amount, or the eye and the digits disagree.
    @Test("The bar and the number describe the same quantity",
          arguments: [0, 1, 25, 50, 80, 99, 100])
    func barMatchesTheNumber(used: Int) throws {
        let e = entry(fiveHour: used, sevenDay: used, context: used)

        for (name, reading) in [("5-hour", e.limitReading(e.snapshot?.limits.fiveHour)),
                               ("week", e.limitReading(e.snapshot?.limits.sevenDay)),
                               ("context", e.contextReading)] {
            let m = try #require(reading.metric, "\(name) has no metric at \(used) %")
            #expect(abs(m.fraction - Double(used) / 100) < 0.0001,
                    "\(name): bar \(m.fraction) against \(used) %")
            #expect(m.value.filter(\.isNumber) == String(used),
                    "\(name): number \"\(m.value)\" against \(used) %")
        }
    }

    /// More is worse, in every row. A bar that grows as things improve is the
    /// same defect wearing the other sign.
    @Test("Every row grows towards worse")
    func allRowsGrowTowardsWorse() throws {
        let low = entry(fiveHour: 10, sevenDay: 10, context: 10)
        let high = entry(fiveHour: 90, sevenDay: 90, context: 90)

        for (name, a, b) in [
            ("5-hour", low.limitReading(low.snapshot?.limits.fiveHour), high.limitReading(high.snapshot?.limits.fiveHour)),
            ("week", low.limitReading(low.snapshot?.limits.sevenDay), high.limitReading(high.snapshot?.limits.sevenDay)),
            ("context", low.contextReading, high.contextReading),
        ] {
            let quiet = try #require(a.metric)
            let loud = try #require(b.metric)
            #expect(loud.fraction > quiet.fraction, "\(name): the bar does not grow")
            #expect(loud.level != .healthy, "\(name): 90 % used is not healthy")
            #expect(quiet.level == .healthy, "\(name): 10 % used is not healthy")
        }
    }

    /// A snapshot old enough to be abandoned shows no numbers at all — an
    /// empty bar next to a stale percentage is worse than an empty row.
    @Test("An abandoned snapshot yields no metrics rather than stale ones")
    func abandonedSnapshotHasNoMetrics() {
        let e = entry(fiveHour: 50, sevenDay: 50, context: 50, age: 48 * 3600)
        #expect(e.hidesNumbers)
        #expect(e.limitReading(e.snapshot?.limits.fiveHour) == .missing)
        #expect(e.contextReading == .missing)
    }
}
