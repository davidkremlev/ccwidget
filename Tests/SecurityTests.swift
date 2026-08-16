import Foundation
import Testing

/// The cases in this suite are named after the findings that produced them, so
/// a failure here points straight at what was being defended against.
@Suite("Security")
struct SecurityTests {

    /// B: `~/.claude/settings.json` is a link into a dotfiles repository.
    /// Writing atomically would replace the link with a plain file and quietly
    /// detach the user's config from the repository they keep it in.
    @Test("Writing through a symlinked settings.json keeps the link")
    func followsSettingsSymlink() throws {
        let home = sandbox()
        let template = makeTemplate(in: home)
        makeContainer(in: home)
        let real = home.appending(path: "dotfiles/settings.json")
        try FileManager.default.createDirectory(
            at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "{\n  \"theme\": \"dark\"\n}\n".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: ".claude/settings.json"), withDestinationURL: real)

        let inst = installer(home: home, template: template)
        #expect(inst.preflight().settingsLinkTarget != nil,
                "the link is spotted before anything is written")

        let report = try inst.install()
        #expect(isSymlink(inst.settingsURL), "the link survives")

        let target = try String(contentsOf: real, encoding: .utf8)
        #expect(target.contains("statusLine"), "the write landed on the link's target")
        #expect(target.contains("\"theme\": \"dark\""), "the target's existing key is intact")
        #expect(report.backup.map { !isSymlink($0) } ?? false,
                "the backup is a plain file, not a link")

        let backup = try String(contentsOf: try #require(report.backup), encoding: .utf8)
        #expect(backup.contains("\"theme\"") && !backup.contains("statusLine"),
                "the backup holds the target's original")
    }

    /// C: a link planted where the history truncation writes its temporary
    /// file. Without O_NOFOLLOW the truncation would write the history through
    /// the link and over whatever is on the other end.
    @Test("History truncation refuses to write through a planted symlink")
    func truncationRefusesSymlink() throws {
        let home = sandbox()
        makeContainer(in: home)
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        let victim = home.appending(path: "victim.txt")
        try "PRECIOUS DATA".write(to: victim, atomically: true, encoding: .utf8)

        let store = HistoryStore(url: exchange.appending(path: "history.jsonl"))
        let lines = (0..<2500).map { #"{"t":\#($0),"sevenDay":1,"resetsAt":9}"# }
        try lines.joined(separator: "\n").write(to: store.url, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: exchange.appending(path: "history.jsonl.tmp"), withDestinationURL: victim)

        _ = store.truncateIfNeeded()
        let survived = try String(contentsOf: victim, encoding: .utf8)
        #expect(survived == "PRECIOUS DATA", "truncation does not write through a link")
    }

    /// D: the exchange directory is substituted into a Python source file. A
    /// path holding a quote and a newline must not be able to close the string
    /// and start a statement.
    @Test("A hostile path cannot escape the generated Python literal")
    func pathLiteralIsInert() {
        let hostile = "/tmp/x\"\nimport os; os.system(\"touch /tmp/PWNED\")\nJUNK = \""
        let literal = Installer.pythonStringLiteral(hostile)

        // The property is not "there are no backslashes" — an earlier version
        // of this check looked for those and would have passed the escaped
        // slashes that broke the real exporter. The property is that the
        // literal parses back into exactly the path we put in.
        let decoded = (try? JSONSerialization.jsonObject(
            with: Data("[\(literal)]".utf8))) as? [String]
        #expect(decoded?.first == hostile,
                "the literal decodes back into the original path")
        #expect(!literal.contains("\n"), "the literal is a single line")

        let rendered = Installer.replacingShebang(
            in: "#!/usr/bin/env python3\nGROUP_DIR = \"__GROUP_DIR__\"\n",
            with: URL(filePath: "/usr/bin/python3")
        ).replacingOccurrences(of: "\"__GROUP_DIR__\"", with: literal)

        #expect(rendered.hasPrefix("#!/usr/bin/python3\n"),
                "the shebang was replaced with an absolute path")
        #expect(rendered.components(separatedBy: "\n").count == 3,
                "the injection added no new lines")
    }
}
