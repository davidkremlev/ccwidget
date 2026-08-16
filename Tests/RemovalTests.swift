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

    // MARK: A file that had to be rebuilt

    /// The other half of the removal, and the one nothing produced.
    ///
    /// `RemovalReport.editWasSurgical` was added so that removal could say
    /// what installation has always said — the file was rebuilt, key order and
    /// indentation are gone, the backup has the original. Nothing produced the
    /// `false` value through the real path: the guard on
    /// `SettingsEditor.RemovalOutcome` compares the three outcomes directly,
    /// which says nothing about whether `uninstall` carries one of them out.
    /// A case nothing expects is wrong forever by construction.
    ///
    /// The key is spelled with an escape — `\u004C` is `L` — so a JSON parser
    /// reads it as `statusLine` while a search through the text for
    /// `"statusLine"` finds nothing. Contrived to write by hand, entirely
    /// ordinary from a generator that escapes on output.
    @Test("Removal reports a settings.json it had to rebuild")
    func removalReportsARebuiltFile() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        let command = inst.exporterURL.path(percentEncoded: false)
        write(#"{"status\u004Cine":{"type":"command","command":"\#(command)"},"theme":"dark"}"#,
              to: home)

        #expect(inst.statusLineState() == .ours,
                "the fixture is wrong: the escaped key still has to parse as ours")

        let report = try inst.uninstall(removingHistory: false)
        #expect(report.statusLineRemoved, "the key went")
        #expect(report.editWasSurgical == false,
                "the file was rebuilt and the report says it was not")
        #expect(!settings(home).contains("statusLine") && !settings(home).contains("u004C"),
                "the key survived the rebuild")
        #expect(settings(home).contains("dark"), "the neighbours did not")
    }

    /// And the surgical half, so the field is produced both ways rather than
    /// only in the direction that raises a warning.
    @Test("Removal reports a settings.json it could cut cleanly")
    func removalReportsASurgicalEdit() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        write(#"{"theme":"dark"}"#, to: home)
        _ = try inst.install()

        let report = try inst.uninstall(removingHistory: false)
        #expect(report.statusLineRemoved)
        #expect(report.editWasSurgical == true, "a tidy file needs no rebuilding")
    }

    /// Nothing to remove: no edit happened, so there is nothing to be surgical
    /// about and the report says so rather than guessing.
    @Test("Removal with nothing of ours in the file reports no edit")
    func removalWithoutOurKeyReportsNoEdit() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        write(#"{"theme":"dark"}"#, to: home)

        let report = try inst.uninstall(removingHistory: false)
        #expect(!report.statusLineRemoved)
        #expect(report.editWasSurgical == nil)
    }

    /// The sentence has to reach the person, not just the report. This is the
    /// step the original asymmetry hid: installation composed a warning from
    /// its report and removal composed nothing from its own.
    @MainActor
    @Test("The window tells the user their settings.json was rebuilt")
    func theWindowRepeatsTheWarning() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        let command = inst.exporterURL.path(percentEncoded: false)
        write(#"{"status\u004Cine":{"type":"command","command":"\#(command)"},"theme":"dark"}"#,
              to: home)

        // A watcher pointed at the sandbox and told to reload nothing: the
        // real one reads the developer's own container and asks WidgetKit to
        // reload, which is not something a check may do.
        let model = StatusModel(
            installer: inst,
            watcher: SnapshotWatcher(
                store: SnapshotStore(containerURL: SnapshotStore.exchangeURL(home: home)),
                read: { throw CocoaError(.fileNoSuchFile) },
                reloadWidgets: {}))

        model.uninstall(removingHistory: false)

        let notice = try #require(model.notice)
        #expect(notice.contains("rewritten"),
                "the report knew the file was rebuilt and the window did not say so: \"\(notice)\"")
    }

    /// Removing the history has to remove all of it. `export-skipped.json`
    /// carries eight characters of a session id and a timestamp, and it was
    /// staying behind: somebody asking for their data to be deleted got two
    /// files of three, and the third was the only one with an identifier in it.
    @Test("Removing the history takes the skip notice with it")
    func removingHistoryTakesTheSkipNotice() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        let exchange = inst.exchangeDirectory
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)

        let store = SnapshotStore(containerURL: exchange)
        for (url, text) in [(store.snapshotURL, "{}"),
                            (exchange.appending(path: "history.jsonl"), "{}\n"),
                            (store.skipNoticeURL, #"{"sessionId":"a1b2c3d4","since":0}"#)] {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        _ = try inst.uninstall(removingHistory: true)

        let left = try FileManager.default.contentsOfDirectory(
            atPath: exchange.path(percentEncoded: false))
        #expect(!left.contains("export-skipped.json"),
                "a session identifier survived a request to delete the data: \(left)")
        #expect(!left.contains("history.jsonl"))
        #expect(!left.contains("snapshot.json"))
    }

    /// And the other way: keeping the history keeps all of it, including the
    /// notice. A removal that deletes more than it was asked to is the same
    /// class of defect as one that deletes less.
    @Test("Keeping the history keeps the skip notice too")
    func keepingHistoryKeepsTheSkipNotice() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        let exchange = inst.exchangeDirectory
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        let store = SnapshotStore(containerURL: exchange)
        try #"{"sessionId":"a1b2c3d4"}"#.write(to: store.skipNoticeURL,
                                               atomically: true, encoding: .utf8)

        _ = try inst.uninstall(removingHistory: false)

        #expect(FileManager.default.fileExists(atPath: store.skipNoticeURL.path(percentEncoded: false)),
                "the notice went with a removal that was told to keep the history")
    }
}
