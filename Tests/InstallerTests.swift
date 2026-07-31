import Foundation
import Testing

@Suite("Installer")
struct InstallerTests {

    @Test("Installing refuses when the extension's container is missing")
    func refusesWithoutContainer() {
        let home = sandbox()
        let template = makeTemplate(in: home)
        write("{}", to: home)
        // The container is created by the system when the widget extension
        // first runs. Creating it ourselves would produce a directory the
        // sandbox will not let the extension read — see section 2.2.
        #expect(throws: (any Error).self, "installing refuses without the extension's container") {
            _ = try installer(home: home, template: template).install()
        }
        #expect(!FileManager.default.fileExists(
            atPath: SnapshotStore.widgetContainerURL(home: home).path),
                "the container directory was not created behind our back")
    }

    @Test("A clean install")
    func installsIntoAnUntouchedConfig() throws {
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
        #expect(inst.isClaudeCodePresent, "Claude Code is found")
        #expect(inst.statusLineState() == .absent, "the status line is not ours yet")

        let report = try inst.install()
        #expect(report.editWasSurgical, "the edit was surgical")
        #expect(report.backup != nil, "a backup was made")
        #expect(FileManager.default.fileExists(atPath: inst.exporterURL.path),
                "the exporter was written")
        #expect(posixMode(of: inst.exporterURL) & 0o111 != 0, "the exporter is executable")

        let body = try String(contentsOf: inst.exporterURL, encoding: .utf8)
        #expect(!body.contains("__GROUP_DIR__")
                && body.contains(SnapshotStore.exchangeURL(home: home).path),
                "the placeholder was substituted")

        let text = settings(home)
        #expect(text.contains("\"theme\": \"dark\"") && text.contains("\"language\": \"Russian\""),
                "the existing keys are intact")
        #expect(inst.statusLineState() == .ours, "the status line became ours")

        let backupText = try String(contentsOf: try #require(report.backup), encoding: .utf8)
        #expect(backupText.contains("\"theme\": \"dark\"") && !backupText.contains("statusLine"),
                "the backup holds the original")

        // Two installs inside the same second used to collide: the backup name
        // is built from a timestamp, and copyItem refuses an existing
        // destination. Found by the checks, not in review.
        let second = try inst.install()
        #expect(second.backup != nil, "a second install does not trip over the backup name")
        #expect(second.backup?.lastPathComponent != report.backup?.lastPathComponent,
                "the second backup has a different name")
    }

    @Test("Someone else's status line")
    func replacesForeignStatusLine() throws {
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

        var recognised: String?
        if case .foreign(let command) = inst.statusLineState() { recognised = command }
        #expect(recognised == "/someone/else.sh", "a foreign status line is recognised")

        _ = try inst.install()
        #expect(inst.statusLineState() == .ours, "a foreign status line is replaced")
    }

    @Test("Installing refuses when the template is missing from the bundle")
    func refusesWithoutTemplate() {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        #expect(throws: (any Error).self, "installing refuses without the template") {
            _ = try Installer(home: home,
                              exchangeDirectory: SnapshotStore.exchangeURL(home: home),
                              templateURL: nil).install()
        }
    }
}
