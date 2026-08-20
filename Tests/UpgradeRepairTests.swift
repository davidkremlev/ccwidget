import Foundation
import Testing

/// The upgrade repair: the decision table row by row, and the marker that
/// keeps it from undoing a person's removal.
///
/// The decision is arithmetic on four values, so the table is stated
/// directly; the doing — `perform` — is walked through a sandbox home, the
/// same way `InstallerTests` walks setup and removal.
@Suite("Upgrade repair")
struct UpgradeRepairTests {

    // MARK: The table

    /// Every `Decision` case is produced here, and the rows that matter are
    /// the near-misses: torn down by an upgrade versus removed on purpose
    /// are the same machine but for the marker.
    @Test("Torn-down setup with prior data is repaired; the same state behind the marker is not")
    func theMarkerSeparatesUpgradeFromChoice() {
        #expect(UpgradeRepair.decision(state: .absent, integrity: .missing,
                                       hasDataFromBefore: true, removedByChoice: false)
                == .reinstall)
        #expect(UpgradeRepair.decision(state: .absent, integrity: .missing,
                                       hasDataFromBefore: true, removedByChoice: true)
                == .leaveAlone(reason: "removed through the app on purpose; a marker records it"))
    }

    @Test("A machine never set up is left to its person")
    func freshMachinesAreLeftAlone() {
        let verdict = UpgradeRepair.decision(state: .absent, integrity: .missing,
                                             hasDataFromBefore: false, removedByChoice: false)
        #expect(verdict == .leaveAlone(reason: "never set up on this machine; setup is a person's decision"))
    }

    @Test("A working setup is recognised, hash or no hash")
    func workingSetupIsAlreadyConfigured() {
        for integrity in [Installer.Integrity.matches, .unknown] {
            #expect(UpgradeRepair.decision(state: .ours, integrity: integrity,
                                           hasDataFromBefore: true, removedByChoice: false)
                    == .alreadyConfigured)
        }
    }

    @Test("Our key over a missing or outdated exporter is repaired")
    func brokenOwnSetupIsRepaired() {
        for integrity in [Installer.Integrity.missing, .outdated] {
            #expect(UpgradeRepair.decision(state: .ours, integrity: integrity,
                                           hasDataFromBefore: false, removedByChoice: false)
                    == .reinstall)
        }
    }

    @Test("A hand-modified exporter is never overwritten quietly")
    func tamperedExporterIsLeftForTheBanner() {
        let verdict = UpgradeRepair.decision(state: .ours, integrity: .changed,
                                             hasDataFromBefore: true, removedByChoice: false)
        #expect(verdict == .leaveAlone(reason: "the exporter was modified by hand; the window's banner is the honest channel"))
    }

    @Test("A foreign status line with prior data is chained, exactly as the button would")
    func foreignLineWithDataIsRepaired() {
        #expect(UpgradeRepair.decision(state: .foreign("~/bin/statusline.sh"), integrity: .missing,
                                       hasDataFromBefore: true, removedByChoice: false)
                == .reinstall)
    }

    // MARK: The marker's lifecycle

    @Test("Remove leaves the marker, setting up again clears it")
    func removalWritesTheMarkerAndInstallClearsIt() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))

        _ = try inst.install()
        #expect(!inst.removedByChoiceMarkerExists, "a fresh install must not look like a removal")

        _ = try inst.uninstall(removingHistory: false)
        #expect(inst.removedByChoiceMarkerExists, "Remove left no record of the choice")

        _ = try inst.install()
        #expect(!inst.removedByChoiceMarkerExists, "setting up again is the opposite choice, and the marker outlived it")
    }

    // MARK: The doing

    /// The upgrade, end to end in a sandbox: set up, tear down the way the
    /// cask's uninstall script does — key and exporter gone, data kept, no
    /// marker — and let the repair run. The status line must come back as
    /// ours, and a second run must find nothing to do.
    @Test("perform restores a torn-down setup and is idempotent")
    func performRestoresAfterUpgrade() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        _ = try inst.install()

        // What the cask's uninstall script leaves behind on an upgrade —
        // without `uninstall(removingHistory:)`, whose marker means choice.
        let fm = FileManager.default
        try fm.removeItem(at: inst.exporterURL)
        let settingsURL = home.appending(path: ".claude/settings.json")
        var settings = try JSONSerialization.jsonObject(
            with: Data(contentsOf: settingsURL)) as? [String: Any] ?? [:]
        settings.removeValue(forKey: "statusLine")
        try JSONSerialization.data(withJSONObject: settings).write(to: settingsURL)
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: exchange.appending(path: "snapshot.json"))

        #expect(inst.statusLineState() == .absent, "the tear-down did not tear down")
        #expect(UpgradeRepair.perform(installer: inst) == 0)
        #expect(inst.statusLineState() == .ours, "the repair did not restore the key")
        #expect(inst.checkIntegrity() == .matches, "the repair did not restore the exporter")

        #expect(UpgradeRepair.perform(installer: inst) == 0, "a second run must be a no-op")
    }

    /// And the negative control: the same tear-down behind the marker stays
    /// torn down.
    @Test("perform refuses to undo a removal a person chose")
    func performHonoursTheMarker() throws {
        let home = sandbox()
        makeContainer(in: home)
        let inst = installer(home: home, template: makeTemplate(in: home))
        _ = try inst.install()
        _ = try inst.uninstall(removingHistory: false)
        let exchange = SnapshotStore.exchangeURL(home: home)
        try FileManager.default.createDirectory(at: exchange, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: exchange.appending(path: "snapshot.json"))

        #expect(UpgradeRepair.perform(installer: inst) == 0)
        #expect(inst.statusLineState() == .absent,
                "the repair reinstated a setup the person removed")
    }
}
