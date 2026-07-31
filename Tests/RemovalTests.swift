import Foundation
import Testing

@Suite("Removal and integrity")
struct RemovalTests {

    @Test("A full round trip: install, tamper, repair, remove")
    func removesWhatItInstalled() throws {
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
        _ = try inst.install()
        #expect(inst.statusLineState() == .ours, "the status line is ours after installing")
        #expect(FileManager.default.fileExists(
            atPath: inst.integrityURL.path(percentEncoded: false)), "the hash was written")
        #expect(inst.checkIntegrity() == .matches, "the integrity check passes")

        // The exporter runs on every status line redraw. If something else has
        // rewritten it, the user has to be told before anything else happens.
        try "#!/bin/sh\necho hacked\n".write(to: inst.exporterURL, atomically: true, encoding: .utf8)
        #expect(inst.checkIntegrity() == .changed, "a swapped exporter is noticed")
        _ = try inst.install()
        #expect(inst.checkIntegrity() == .matches, "reinstalling repairs the integrity")

        let plan = inst.removalPlan()
        #expect(plan.removesStatusLine, "the removal plan sees our status line")
        #expect(plan.removesExporter, "the removal plan sees the exporter")

        let report = try inst.uninstall(removingHistory: false)
        #expect(report.statusLineRemoved, "the statusLine key was removed")
        #expect(!FileManager.default.fileExists(
            atPath: inst.exporterURL.path(percentEncoded: false)), "the exporter was deleted")
        #expect(!FileManager.default.fileExists(
            atPath: inst.integrityURL.path(percentEncoded: false)), "the hash was deleted")
        #expect(inst.statusLineState() == .absent, "the status line is no longer ours")

        // Removal deletes one key rather than restoring the backup: the user
        // may have changed other keys since installing, and rolling the file
        // back would take those edits away.
        let text = settings(home)
        #expect(text.contains("\"theme\": \"dark\"") && text.contains("\"language\": \"Russian\"")
                && text.contains("\"defaultMode\": \"auto\""),
                "the neighbouring keys are intact after removal")
        #expect(text.contains("  \"language\": \"Russian\""), "the neighbours keep their formatting")
        #expect(parseJSON(text) != nil, "the file is still valid JSON")
        #expect(!text.contains(",\n}") && !text.contains(", }"), "no trailing comma is left behind")
        #expect(report.backup != nil, "removal made a backup")

        if let backup = report.backup {
            #expect(posixMode(of: backup) == 0o600, "the backup is locked down to 0600")
        }
    }

    /// Regression: a status line of ours that is already installed must not
    /// read as foreign. A live run showed "Another status line is already
    /// configured" pointing at our own exporter — the culprit was not the code
    /// but an app left over under the old name. This catches that, and any
    /// future drift between what we write into the config and what we compare
    /// against.
    @Test("Our own status line is not mistaken for someone else's")
    func recognisesItsOwnStatusLine() throws {
        let home = sandbox()
        let template = makeTemplate(in: home)
        makeContainer(in: home)
        write("{}", to: home)

        _ = try installer(home: home, template: template).install()

        // A fresh instance, as on the app's next launch.
        let fresh = installer(home: home, template: template)
        #expect(fresh.statusLineState() == .ours,
                "our own status line is recognised after installing")

        var foreignWarning = false
        if case .foreign = fresh.statusLineState() { foreignWarning = true }
        #expect(!foreignWarning, "no foreign status line warning")

        let stored = ((try? JSONSerialization.jsonObject(
            with: Data(contentsOf: fresh.settingsURL)) as? [String: Any])
            .flatMap { ($0?["statusLine"] as? [String: Any])?["command"] as? String }) ?? ""
        #expect(stored == fresh.exporterURL.path(percentEncoded: false),
                "the recorded path matches the computed one")

        _ = try fresh.install()
        #expect(fresh.statusLineState() == .ours,
                "reinstalling leaves the status line ours")
    }

    @Test("Removal leaves someone else's status line alone")
    func leavesForeignStatusLineAlone() {
        let home = sandbox()
        let template = makeTemplate(in: home)
        makeContainer(in: home)
        write(#"{"statusLine":{"type":"command","command":"/someone/else.sh"}}"#, to: home)
        let inst = installer(home: home, template: template)
        _ = try? inst.uninstall(removingHistory: false)
        #expect(settings(home).contains("/someone/else.sh"),
                "a foreign status line is left alone")
    }

    @Test("Backups rotate instead of piling up")
    func rotatesBackups() throws {
        let home = sandbox()
        let template = makeTemplate(in: home)
        makeContainer(in: home)
        write("{}", to: home)
        let inst = installer(home: home, template: template)
        for _ in 0..<8 { _ = try? inst.install() }

        let names = try FileManager.default.contentsOfDirectory(
            atPath: inst.claudeDirectory.path(percentEncoded: false))
            .filter { $0.hasPrefix("settings.json.bak-") }
        #expect(names.count <= Installer.backupsKept, "no more than five backups are kept")
    }
}
