import CryptoKit
import Foundation

/// Installs the exporter into the Claude Code configuration. Section 11.
///
/// Every path is supplied from outside — see section 5.2.
struct Installer {
    let home: URL
    let exchangeDirectory: URL
    /// `nil` means the template is missing and installation is impossible.
    let templateURL: URL?
    /// Interpreter candidates, in order of preference.
    var interpreterCandidates: [URL] = Installer.defaultInterpreters

    /// The system Python comes first on purpose: `/usr/bin/python3` is owned
    /// by root while `/opt/homebrew/bin` is owned by the user. The exporter
    /// runs dozens of times a minute, and taking its interpreter from a
    /// directory any process of this user can write to widens the attack
    /// surface for nothing.
    static let defaultInterpreters: [URL] = [
        URL(filePath: "/usr/bin/python3"),
        URL(filePath: "/opt/homebrew/bin/python3"),
        URL(filePath: "/usr/local/bin/python3"),
    ]

    static func live() -> Installer {
        Installer(
            home: FileManager.default.homeDirectoryForCurrentUser,
            exchangeDirectory: SnapshotStore.exchangeURL,
            templateURL: Bundle.main.url(forResource: "ccwidget-export.py", withExtension: "template")
        )
    }

    enum Failure: LocalizedError {
        case widgetContainerMissing
        case templateMissing
        case pythonMissing
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .widgetContainerMissing:
                return String(localized: "Add the widget to your desktop first, then run setup again.")
            case .templateMissing:
                return String(localized: "The exporter template is missing from the app bundle.")
            case .pythonMissing:
                return String(localized: "No working python3 was found. Install the Xcode Command Line Tools with: xcode-select --install")
            case .writeFailed(let url, let error):
                return String(localized: "Could not write \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    enum StatusLineState: Equatable {
        case absent
        case ours
        case foreign(String)
    }

    struct Report {
        let backup: URL?
        /// False means `settings.json` had to be rebuilt from scratch.
        let editWasSurgical: Bool
        let interpreter: URL
    }

    /// What installation will do, before it is run. Section 11 requires
    /// warning up front rather than reporting after the fact.
    struct Preflight {
        let widgetContainerExists: Bool
        let interpreter: URL?
        /// `settings.json` is a symlink, and this is its target.
        let settingsLinkTarget: URL?
        /// The link can be preserved: its target is writable.
        let canPreserveLink: Bool
        let settingsWritable: Bool

        var isReady: Bool {
            widgetContainerExists && interpreter != nil && settingsWritable
        }
    }

    // MARK: Paths

    var claudeDirectory: URL { home.appending(path: ".claude") }
    var settingsURL: URL { claudeDirectory.appending(path: "settings.json") }
    var exporterURL: URL { claudeDirectory.appending(path: "ccwidget-export.py") }

    /// What the window shows. The real names may carry a `-2`, `-3` counter
    /// when two installs land in the same second; the pattern names the shape
    /// somebody should look for, not the grammar.
    var backupNamePattern: String { "settings.json.bak-YYYYMMDD-HHMMSS" }

    /// Where the hash of the installed exporter is kept.
    ///
    /// The app drops an executable into the status line's path and, without
    /// this, never looks at it again: it would keep saying "configured" about
    /// a file that had been swapped.
    ///
    /// **What it does not do.** The hash lives in the same directory as the
    /// file it describes, with the same permissions, so anyone who can replace
    /// the exporter can rewrite the hash beside it. This detects drift — an
    /// edit, a half-finished upgrade, a file replaced by another tool — and
    /// not an adversary. The comment here used to say it "makes tampering
    /// visible", which is the stronger claim and is false. Making it true
    /// needs somewhere else to keep the hash, and nothing in this project has
    /// that today.
    var integrityURL: URL { claudeDirectory.appending(path: ".ccwidget-export.sha256") }

    /// How many backups to keep. A backup holds someone's configuration;
    /// hoarding them serves nobody, and old ones go stale besides.
    static let backupsKept = 5

    /// Where the settings actually have to be written.
    ///
    /// If `~/.claude/settings.json` is a symlink into a dotfiles repository,
    /// the write has to go through to the target. Otherwise an atomic write
    /// replaces the link itself with a regular file: the connection to
    /// dotfiles breaks silently, the real config never gets its `statusLine`,
    /// and nothing on screen explains why.
    var resolvedSettingsURL: URL {
        var url = settingsURL
        var hops = 0
        while hops < 8,
              let type = try? FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType,
              type == .typeSymbolicLink,
              let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: url.path(percentEncoded: false)) {
            let next = URL(filePath: destination, relativeTo: url.deletingLastPathComponent())
            url = next.standardizedFileURL
            hops += 1
        }
        return url
    }

    var settingsIsSymbolicLink: Bool {
        resolvedSettingsURL.path(percentEncoded: false) != settingsURL.path(percentEncoded: false)
    }

    // MARK: State

    var isClaudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false))
    }

    var widgetContainerExists: Bool {
        SnapshotStore.widgetContainerExists(home: home)
    }

    /// Whether the exporter still matches the one we installed.
    enum Integrity: Equatable {
        case matches
        case changed
        case unknown      // no hash: installed before the check existed
        case missing      // the exporter itself is gone

        /// The line the window prints beside "Exporter". Composed here rather
        /// than in the view so that two verdicts saying the same thing is
        /// something a check can notice — the window puts an executable file
        /// in the status line's path, and what it says about that file is the
        /// whole point of the type.
        func detail(locale: Locale = .autoupdatingCurrent) -> String {
            var resource: LocalizedStringResource
            switch self {
            case .matches: resource = LocalizedStringResource("matches the installed copy")
            case .changed: resource = LocalizedStringResource("modified since installation")
            case .unknown: resource = LocalizedStringResource("installed before checking existed")
            case .missing: resource = LocalizedStringResource("not installed")
            }
            resource.locale = locale
            return String(localized: resource)
        }

        /// Whether the tamper banner is raised. A hash mismatch outranks
        /// everything else the window might be saying.
        var raisesBanner: Bool { self == .changed }
    }

    func checkIntegrity() -> Integrity {
        guard let body = try? Data(contentsOf: exporterURL) else { return .missing }
        guard let expected = try? String(contentsOf: integrityURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !expected.isEmpty
        else { return .unknown }
        return Self.digest(of: body) == expected ? .matches : .changed
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func statusLineState() -> StatusLineState {
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String
        else { return .absent }
        return command == exporterURL.path(percentEncoded: false) ? .ours : .foreign(command)
    }

    func preflight() -> Preflight {
        let resolved = resolvedSettingsURL
        let isLink = settingsIsSymbolicLink
        let directory = resolved.deletingLastPathComponent()
        let fm = FileManager.default
        let targetExists = fm.fileExists(atPath: resolved.path(percentEncoded: false))
        // An atomic write puts a temporary file next to the target, so what
        // is needed is write access to the directory, not just the file.
        let writable = fm.isWritableFile(atPath: directory.path(percentEncoded: false))
            || (!targetExists && !fm.fileExists(atPath: directory.path(percentEncoded: false)))

        return Preflight(
            widgetContainerExists: widgetContainerExists,
            interpreter: findInterpreter(),
            settingsLinkTarget: isLink ? resolved : nil,
            canPreserveLink: !isLink || writable,
            settingsWritable: writable || !isClaudeCodePresent
        )
    }

    // MARK: Interpreter

    /// The first candidate that actually runs and answers "3".
    ///
    /// Running it is mandatory: on a clean macOS `/usr/bin/python3` exists but
    /// is a stub that pops up an offer to install the Command Line Tools.
    /// Without the check the exporter would silently do nothing while
    /// onboarding waited forever.
    func findInterpreter() -> URL? {
        for candidate in interpreterCandidates where
            FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
            if Self.reportsPython3(candidate) { return candidate }
        }
        return nil
    }

    private static func reportsPython3(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-c", "import sys; print(sys.version_info[0])"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // The Command Line Tools stub is interactive; give it no input.
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "3"
    }

    // MARK: Installing

    @discardableResult
    func install() throws -> Report {
        guard widgetContainerExists else { throw Failure.widgetContainerMissing }
        guard let interpreter = findInterpreter() else { throw Failure.pythonMissing }

        try writeExporter(interpreter: interpreter)
        let backup = try backupSettings()
        let surgical = try writeStatusLine()
        return Report(backup: backup, editWasSurgical: surgical, interpreter: interpreter)
    }

    private func writeExporter(interpreter: URL) throws {
        guard let templateURL,
              let body = try? String(contentsOf: templateURL, encoding: .utf8)
        else { throw Failure.templateMissing }

        var rendered = body
        // A bare substitution inside the quotes is a code-injection sink: a
        // path containing a quote or a newline escapes the literal, and the
        // file is then executed on every redraw. Substitute a finished
        // literal, quotes included.
        rendered = rendered.replacingOccurrences(
            of: "\"__GROUP_DIR__\"",
            with: Self.pythonStringLiteral(exchangeDirectory.path(percentEncoded: false))
        )
        rendered = Self.replacingShebang(in: rendered, with: interpreter)

        do {
            try createClaudeDirectoryIfNeeded()
            try rendered.write(to: exporterURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: exporterURL.path(percentEncoded: false)
            )
            try (Self.digest(of: Data(rendered.utf8)) + "\n")
                .write(to: integrityURL, atomically: true, encoding: .utf8)
        } catch {
            throw Failure.writeFailed(exporterURL, error)
        }
    }

    /// Escaped by JSON's rules. Python accepts the same escape sequences,
    /// `\uXXXX` included, so the result is a valid literal in both languages.
    static func pythonStringLiteral(_ value: String) -> String {
        // `.withoutEscapingSlashes` is mandatory: by default slashes come
        // out as `\/`, which is legal JSON but an unrecognised escape for
        // Python — and a warning on every single run.
        guard let data = try? JSONSerialization.data(
                withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(text.dropFirst().dropLast())
    }

    static func replacingShebang(in body: String, with interpreter: URL) -> String {
        var lines = body.components(separatedBy: "\n")
        let shebang = "#!" + interpreter.path(percentEncoded: false)
        if let first = lines.first, first.hasPrefix("#!") {
            lines[0] = shebang
        } else {
            lines.insert(shebang, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// We create the directory closed. We never touch the permissions of one
    /// that already exists — it is not ours.
    private func createClaudeDirectoryIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: claudeDirectory.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// The backup is always a regular file, even when the original is a
    /// symlink: a symlinked backup would point at the very file we are about
    /// to overwrite, leaving nothing to restore from.
    private func backupSettings() throws -> URL? {
        let source = resolvedSettingsURL
        guard let contents = try? Data(contentsOf: source) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        var backup = claudeDirectory.appending(path: "settings.json.bak-\(stamp)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) {
            backup = claudeDirectory.appending(path: "settings.json.bak-\(stamp)-\(attempt)")
            attempt += 1
        }

        do {
            try createClaudeDirectoryIfNeeded()
            try contents.write(to: backup, options: .atomic)
            // settings.json can hold environment variables and keys. The
            // backup must be no more readable than the original.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: backup.path(percentEncoded: false)
            )
        } catch {
            throw Failure.writeFailed(backup, error)
        }
        pruneBackups()
        return backup
    }

    /// Keeps the recent backups and deletes the rest — ours, and only ours.
    ///
    /// The prefix alone is not enough, and that was a defect rather than a
    /// nicety: `settings.json.bak-before-experiment` is a name a person types,
    /// it starts with the same eighteen characters, and it went in the bin on
    /// the sixth install without a word. What this project writes is the
    /// prefix followed by exactly `YYYYMMDD-HHMMSS`, so that is what it is
    /// allowed to delete. Anything else in that directory belongs to whoever
    /// put it there.
    /// A function rather than a stored `Regex`: `Regex` is not `Sendable`, and
    /// a static one in a type this concurrent does not compile under strict
    /// checking. The pattern is small enough to read as code.
    static func isOurBackupName(_ name: String) -> Bool {
        let prefix = "settings.json.bak-"
        guard name.hasPrefix(prefix) else { return false }
        let parts = name.dropFirst(prefix.count).split(separator: "-",
                                                       omittingEmptySubsequences: false)
        func digits(_ s: Substring, _ count: Int) -> Bool {
            s.count == count && s.allSatisfy { $0.isASCII && $0.isNumber }
        }
        switch parts.count {
        case 2:
            return digits(parts[0], 8) && digits(parts[1], 6)
        case 3:
            // Two installs inside one second: `backupSettings` appends `-2`,
            // `-3` and so on rather than overwriting. Those are ours too, and
            // leaving them out meant they could never be pruned — caught by
            // the rotation check, which had eight backups where five were
            // allowed. The counter has no fixed width, so it is only required
            // to be digits.
            return digits(parts[0], 8) && digits(parts[1], 6)
                && !parts[2].isEmpty && parts[2].allSatisfy { $0.isASCII && $0.isNumber }
        default:
            return false
        }
    }

    // Internal rather than private so the rule above can be checked directly
    // instead of through an install, which would need an interpreter and a
    // container to say anything about which files survive.
    func pruneBackups() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: claudeDirectory.path(percentEncoded: false))
        else { return }
        let backups = names
            .filter(Self.isOurBackupName)
            .sorted()
        guard backups.count > Self.backupsKept else { return }
        for name in backups.dropLast(Self.backupsKept) {
            try? fm.removeItem(at: claudeDirectory.appending(path: name))
        }
    }

    private func writeStatusLine() throws -> Bool {
        // Write through to the link's target, not to the link itself.
        let destination = resolvedSettingsURL
        let original = try? String(contentsOf: destination, encoding: .utf8)
        let value: [String: Any] = [
            "type": "command",
            "command": exporterURL.path(percentEncoded: false),
            "padding": 0,
        ]

        let text: String
        let surgical: Bool
        switch SettingsEditor.setting("statusLine", to: value, in: original) {
        case .surgical(let edited): text = edited; surgical = true
        case .rewritten(let rebuilt): text = rebuilt; surgical = false
        }

        do {
            try createClaudeDirectoryIfNeeded()
            try text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw Failure.writeFailed(destination, error)
        }
        return surgical
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: resolvedSettingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Removal

    /// What removal will do, and what will be left behind.
    struct RemovalPlan {
        let removesStatusLine: Bool
        let removesExporter: Bool
        let historyLineCount: Int
        /// The app bundle and the extension's container cannot be removed by
        /// the app itself.
        let manualLeftovers: [String]
    }

    struct RemovalReport {
        let statusLineRemoved: Bool
        let exporterRemoved: Bool
        let historyRemoved: Bool
        let backup: URL?
        /// Whether the key could be cut out without rebuilding the file.
        /// `nil` when nothing was edited, because there is then nothing to be
        /// surgical about.
        ///
        /// Installation has reported this since section 11 asked it to, and
        /// removal did not — the same file, the same risk of losing somebody's
        /// key order and indentation, and one of the two paths saying nothing.
        /// The asymmetry was an oversight, not a decision.
        let editWasSurgical: Bool?
    }

    func removalPlan() -> RemovalPlan {
        let history = (try? String(contentsOf: exchangeDirectory.appending(path: "history.jsonl"),
                                   encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: true).count ?? 0
        return RemovalPlan(
            removesStatusLine: statusLineState() == .ours,
            removesExporter: FileManager.default.fileExists(
                atPath: exporterURL.path(percentEncoded: false)),
            historyLineCount: history,
            manualLeftovers: [
                "/Applications/CCWidget.app",
                SnapshotStore.widgetContainerURL(home: home).path(percentEncoded: false),
            ]
        )
    }

    /// Undoes the installation.
    ///
    /// The `statusLine` key is deleted surgically rather than restored from a
    /// backup: other keys may have changed between install and removal, and
    /// rolling the whole file back would take those edits away. The backup
    /// stays a fallback, not the mechanism.
    @discardableResult
    func uninstall(removingHistory: Bool) throws -> RemovalReport {
        var backup: URL?
        var statusLineRemoved = false
        var editWasSurgical: Bool?

        if statusLineState() == .ours {
            backup = try backupSettings()
            let destination = resolvedSettingsURL
            let original = try? String(contentsOf: destination, encoding: .utf8)

            let outcome = SettingsEditor.removing("statusLine", from: original)
            let edited: String?
            switch outcome {
            case .surgical(let text): edited = text; editWasSurgical = true
            case .rewritten(let text): edited = text; editWasSurgical = false
            case .absent: edited = nil
            }

            if let edited {
                do {
                    try edited.write(to: destination, atomically: true, encoding: .utf8)
                    statusLineRemoved = true
                } catch {
                    throw Failure.writeFailed(destination, error)
                }
            }
        }

        let fm = FileManager.default
        let exporterRemoved = (try? fm.removeItem(at: exporterURL)) != nil
        try? fm.removeItem(at: integrityURL)

        var historyRemoved = false
        if removingHistory {
            historyRemoved = (try? fm.removeItem(
                at: exchangeDirectory.appending(path: "history.jsonl"))) != nil
            try? fm.removeItem(at: exchangeDirectory.appending(path: "snapshot.json"))
            // And the skip notice, which carries eight characters of a session
            // id and a timestamp. It was left behind: somebody asking for their
            // data to be removed got two files of three, and the third was the
            // only one with an identifier in it.
            // Named through the store rather than spelled again here, so the
            // two cannot drift apart.
            try? fm.removeItem(at: SnapshotStore(containerURL: exchangeDirectory).skipNoticeURL)
        }

        return RemovalReport(
            statusLineRemoved: statusLineRemoved,
            exporterRemoved: exporterRemoved,
            historyRemoved: historyRemoved,
            backup: backup,
            editWasSurgical: editWasSurgical
        )
    }

    // MARK: Manual instructions

    /// No `sed`: a path containing `|` breaks the delimiter and one
    /// containing a quote breaks the literal inside the script itself. Show
    /// the finished line instead.
    func manualInstructions() -> String {
        let interpreter = findInterpreter()?.path(percentEncoded: false) ?? "/usr/bin/python3"
        return """
        1. \(String(localized: "Copy the template to ~/.claude/ccwidget-export.py"))

        2. \(String(localized: "Replace its first line with:"))

        #!\(interpreter)

        3. \(String(localized: "Replace the GROUP_DIR line with exactly:"))

        GROUP_DIR = \(Self.pythonStringLiteral(exchangeDirectory.path(percentEncoded: false)))

        4. chmod +x ~/.claude/ccwidget-export.py

        5. \(String(localized: "Add this to ~/.claude/settings.json:"))

        "statusLine": {
          "type": "command",
          "command": \(Self.pythonStringLiteral(exporterURL.path(percentEncoded: false))),
          "padding": 0
        }
        """
    }
}
