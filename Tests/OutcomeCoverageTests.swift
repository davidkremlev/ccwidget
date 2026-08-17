import Foundation
import AppKit
import ServiceManagement
import Testing

/// Every case of every enum, produced on purpose.
///
/// A case that no check expects is wrong forever by construction: there is
/// nothing to notice when the branch that should produce it stops producing
/// it. That is exactly how `.runsOut` came to be named for quotas that
/// survive their window — `.lastsUntilReset` existed in the type and in a
/// switch, and no check ever asked for it.
///
/// So this suite is organised by *result* rather than by scenario. The
/// scenarios live with their subjects; what lives here is the guarantee that
/// none of the results is unreachable.
@Suite("Every enum case is produced")
struct OutcomeCoverageTests {

    // MARK: LaunchKind — whether a person opened the app

    /// A login item that opened a window at every login would be the behaviour
    /// this project complains about elsewhere. The signal is documented — the
    /// launch notification's `launchIsDefaultUserInfoKey` — and the case that
    /// matters is the missing key: nothing said about the launch has to mean a
    /// person did it, or an ordinary double-click would start a hidden app.
    @Test("It stays out of the way only when it runs at login and nobody asked",
          arguments: [("a person opened it, item on", true, true, false),
                      ("something started it, item on", false, true, true),
                      ("a person opened it, item off", true, false, false),
                      ("something started it, item off", false, false, false)])
    @MainActor
    func staysOutOfTheWayOnlyWhenBoth(name: String, isDefault: Bool,
                                      runsAtLogin: Bool, hides: Bool) {
        let userInfo: [AnyHashable: Any] = [LaunchKind.key: isDefault]
        #expect(LaunchKind.staysOutOfTheWay(userInfo: userInfo, key: LaunchKind.key,
                                            runsAtLogin: runsAtLogin) == hides, "\(name)")
    }

    /// Two cases that would each have hidden a window somebody asked for. The
    /// missing key: absence has to mean a person, or an ordinary double-click
    /// starts a hidden app. And not running at login: `open` from a terminal is
    /// reported as not-default — measured — so without this condition the app
    /// hid itself on a launch that was plainly a person's doing.
    @MainActor
    @Test("Neither a silent notification nor a terminal launch hides a window")
    func neitherSilenceNorATerminalLaunchHides() {
        #expect(!LaunchKind.staysOutOfTheWay(userInfo: nil, key: LaunchKind.key, runsAtLogin: true))
        #expect(!LaunchKind.staysOutOfTheWay(userInfo: [:], key: LaunchKind.key, runsAtLogin: true))
        #expect(!LaunchKind.staysOutOfTheWay(userInfo: ["other": 1], key: LaunchKind.key,
                                             runsAtLogin: true))
        #expect(!LaunchKind.staysOutOfTheWay(userInfo: [LaunchKind.key: false],
                                             key: LaunchKind.key, runsAtLogin: false),
                "not registered to run at login, so nothing to hide for")
    }

    // MARK: LoginItem.State — every one produced from what SMAppService says

    /// The mapping is the whole of this type, and it is the kind of mapping that
    /// looks obviously right and is wrong in one place: `requiresApproval` means
    /// registered-and-waiting, not failed, and treating it as off would make the
    /// switch flick back by itself.
    /// `notFound` is the one that matters, and the one that was wrong. It is
    /// what `mainApp` reports before it has ever been registered — the state
    /// every user starts in — and it was mapped to "unavailable", which hid the
    /// switch and made the feature unreachable for everybody. Measured against
    /// the framework: notFound, register, enabled.
    @Test("Every SMAppService status becomes the state it means",
          arguments: [(SMAppService.Status.notRegistered, LoginItem.State.off),
                      (.enabled, .on),
                      (.requiresApproval, .waitingForApproval),
                      (.notFound, .off)])
    func everyStatusMapsToItsState(status: SMAppService.Status, expected: LoginItem.State) {
        let item = LoginItem(read: { status }, enable: {}, disable: {})
        #expect(item.state == expected)
    }

    /// And the switch does what it says: on registers, off unregisters, and
    /// neither is called for the other.
    @Test("The switch calls register and unregister, and not the other way round")
    @MainActor func theSwitchCallsTheRightThing() {
        final class Calls { var enabled = 0; var disabled = 0 }
        let calls = Calls()
        var status = SMAppService.Status.notRegistered
        let item = LoginItem(read: { status },
                             enable: { calls.enabled += 1; status = .enabled },
                             disable: { calls.disabled += 1; status = .notRegistered })
        let model = StatusModel(loginItem: item)

        model.setBackgroundUpdates(true)
        #expect(calls.enabled == 1 && calls.disabled == 0)
        #expect(model.loginItem.state.isOn, "and the switch reads as on")
        #expect(model.loginItem.state == .on)
        #expect(model.notice == nil,
                """
                nothing to announce: the line beside the switch already says the \
                state, and saying it again at the foot of the window printed the \
                same sentence twice — \(model.notice ?? "nil")
                """)

        model.setBackgroundUpdates(false)
        #expect(calls.enabled == 1 && calls.disabled == 1)
        #expect(model.loginItem.state == .off)
    }

    /// The case that looks like nothing happening. `register()` succeeds and the
    /// item still waits for the person, so the notice has to send them onward
    /// rather than report success.
    @Test("Registering into approval says so instead of claiming success")
    @MainActor func approvalIsReported() {
        var status = SMAppService.Status.notRegistered
        let item = LoginItem(read: { status },
                             enable: { status = .requiresApproval },
                             disable: { status = .notRegistered })
        let model = StatusModel(loginItem: item)

        model.setBackgroundUpdates(true)
        #expect(model.loginItem.state == .waitingForApproval)
        #expect(model.loginItem.state.needsSettings, "and the window offers the way there")
        #expect(model.notice == nil,
                "the line and the button say it; a third copy at the foot of the window does not")
    }

    /// A failure from `SMAppService` reaches the person rather than the log.
    @Test("A refusal to register is reported")
    @MainActor func aRefusalIsReported() {
        struct Refused: LocalizedError {
            var errorDescription: String? { "Operation not permitted" }
        }
        let item = LoginItem(read: { .notRegistered },
                             enable: { throw Refused() },
                             disable: {})
        let model = StatusModel(loginItem: item)
        model.setBackgroundUpdates(true)
        #expect(model.notice == "Operation not permitted")
    }

    // MARK: Installer.Integrity

    @Test("matches, after a clean install")
    func integrityMatches() throws {
        let home = sandbox()
        let inst = installer(home: home, template: makeTemplate(in: home))
        makeContainer(in: home)
        write("{}", to: home)
        _ = try inst.install()
        #expect(inst.checkIntegrity() == .matches)
    }

    /// The state an upgrade produces, and the reason it had to exist: installing
    /// a new app does not rewrite the exporter — setup does — so without this
    /// the old file goes on running and the hash check, comparing the file to
    /// its own recorded hash, says "matches" and means nothing.
    ///
    /// Two versions of one installer, because the alternative is shipping two
    /// apps to find out.
    @Test("outdated, when the app was upgraded but setup was not run again")
    func integrityOutdated() throws {
        let home = sandbox()
        let template = makeTemplate(in: home)
        makeContainer(in: home)
        write("{}", to: home)

        let old = installer(home: home, template: template).asVersion("0.3.1")
        _ = try old.install()
        #expect(old.checkIntegrity() == .matches, "the version that wrote it is content")
        #expect(old.installedExporterVersion() == "0.3.1", "and the stamp says who wrote it")

        let new = installer(home: home, template: template).asVersion("0.4.0")
        #expect(new.checkIntegrity() == .outdated,
                "the newer app can tell the exporter is not one of its own")
        #expect(new.checkIntegrity().raisesBanner,
                "and says so where somebody will see it, not in a details table")

        _ = try new.install()
        #expect(new.checkIntegrity() == .matches, "pressing the button settles it")
        #expect(new.installedExporterVersion() == "0.4.0")
    }

    /// An exporter written before stamping existed carries no version at all,
    /// and that is not the same as a mismatch — but it is still not one of
    /// ours, and the answer is the same button.
    @Test("outdated, when the exporter predates version stamping")
    func integrityOutdatedWithoutAStamp() throws {
        let home = sandbox()
        // A template with no stamp in it, which is what the releases before
        // 0.3.2 shipped.
        let unstamped = home.appending(path: "old.template")
        try #"#!/usr/bin/env python3\#nGROUP_DIR = "__GROUP_DIR__"\#nCHAINED = __CHAINED__\#n"#
            .write(to: unstamped, atomically: true, encoding: .utf8)
        let inst = installer(home: home, template: unstamped).asVersion("0.4.0")
        makeContainer(in: home)
        write("{}", to: home)
        _ = try inst.install()

        #expect(inst.installedExporterVersion() == nil)
        #expect(inst.checkIntegrity() == .outdated,
                "no stamp is not a match, and pretending otherwise is how this hid")
    }

    @Test("changed, when something rewrote the exporter")
    func integrityChanged() throws {
        let home = sandbox()
        let inst = installer(home: home, template: makeTemplate(in: home))
        makeContainer(in: home)
        write("{}", to: home)
        _ = try inst.install()
        try "#!/bin/sh\necho hacked\n".write(to: inst.exporterURL, atomically: true, encoding: .utf8)
        #expect(inst.checkIntegrity() == .changed)
    }

    /// Installed by a build that predates the hash. Not an error and not
    /// tampering — the interface has to be able to say so rather than pick
    /// one of the two.
    @Test("unknown, when the exporter is there but no hash is")
    func integrityUnknown() throws {
        let home = sandbox()
        let inst = installer(home: home, template: makeTemplate(in: home))
        makeContainer(in: home)
        write("{}", to: home)
        _ = try inst.install()
        try FileManager.default.removeItem(at: inst.integrityURL)
        #expect(inst.checkIntegrity() == .unknown)
    }

    @Test("missing, when the exporter is gone")
    func integrityMissing() {
        let home = sandbox()
        let inst = installer(home: home, template: makeTemplate(in: home))
        #expect(inst.checkIntegrity() == .missing)
    }

    // MARK: Installer.Failure

    /// `Installer.Failure` carries a `URL` and an `Error`, so it is not
    /// `Equatable` and `#expect(throws:)` cannot take a value. Matching the
    /// case by hand also states the property more exactly: it is the case
    /// that matters, not the payload.
    private func failure(from body: () throws -> Void) -> Installer.Failure? {
        do { try body(); return nil } catch { return error as? Installer.Failure }
    }

    /// The existing installer checks assert only that *something* was thrown.
    /// Which failure it is decides what the user is told, and telling someone
    /// to add a widget when the real problem is a missing interpreter wastes
    /// their afternoon.
    @Test("widgetContainerMissing, before the widget has ever run")
    func failureContainerMissing() {
        let home = sandbox()
        write("{}", to: home)
        let thrown = failure {
            _ = try installer(home: home, template: makeTemplate(in: home)).install()
        }
        guard case .widgetContainerMissing? = thrown else {
            Issue.record("expected widgetContainerMissing, got \(String(describing: thrown))")
            return
        }
    }

    @Test("templateMissing, when the app bundle has no template")
    func failureTemplateMissing() {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        let thrown = failure {
            _ = try Installer(home: home,
                              exchangeDirectory: SnapshotStore.exchangeURL(home: home),
                              templateURL: nil).install()
        }
        guard case .templateMissing? = thrown else {
            Issue.record("expected templateMissing, got \(String(describing: thrown))")
            return
        }
    }

    /// On a clean macOS `/usr/bin/python3` exists and is a stub that offers to
    /// install the Command Line Tools instead of running. Every candidate
    /// failing is therefore a real state, not a hypothetical one.
    @Test("pythonMissing, when no candidate interpreter runs")
    func failurePythonMissing() {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        var inst = installer(home: home, template: makeTemplate(in: home))
        inst.interpreterCandidates = [
            URL(filePath: "/nonexistent/python3"),
            URL(filePath: "/usr/bin/false"),
        ]
        let thrown = failure { _ = try inst.install() }
        guard case .pythonMissing? = thrown else {
            Issue.record("expected pythonMissing, got \(String(describing: thrown))")
            return
        }
    }

    @Test("writeFailed, when the destination cannot be written")
    func failureWriteFailed() throws {
        let home = sandbox()
        makeContainer(in: home)
        write("{}", to: home)
        // A directory where the exporter should go: the write cannot succeed
        // and cannot be mistaken for anything else.
        let inst = installer(home: home, template: makeTemplate(in: home))
        try FileManager.default.createDirectory(at: inst.exporterURL,
                                                withIntermediateDirectories: true)
        let thrown = failure { _ = try inst.install() }
        guard case .writeFailed(let url, _)? = thrown else {
            Issue.record("expected writeFailed, got \(String(describing: thrown))")
            return
        }
        #expect(url == inst.exporterURL, "the failure names the file it could not write")
    }

    // MARK: SettingsEditor.RemovalOutcome

    @Test("surgical, when the key can be cut out cleanly")
    func removalSurgical() {
        let original = """
        {
          "theme": "dark",
          "statusLine": { "type": "command", "command": "/x.py" },
          "language": "Russian"
        }
        """
        guard case .surgical(let edited) = SettingsEditor.removing("statusLine", from: original) else {
            Issue.record("expected a surgical removal")
            return
        }
        #expect(!edited.contains("statusLine"))
        #expect(edited.contains("  \"language\": \"Russian\""), "formatting survives")
    }

    /// A file the surgical path cannot handle still has to lose the key —
    /// with the user told that the rest of the file was rebuilt.
    ///
    /// The key here is spelled with an escape: `\u004C` is `L`, so a JSON
    /// parser reads the name as `statusLine` while a search through the text
    /// for `"statusLine"` finds nothing. Contrived to write by hand, entirely
    /// ordinary from a generator that escapes on output — and exactly the
    /// shape the surgical path must refuse rather than guess at.
    @Test("rewritten, when the surgical path cannot be trusted")
    func removalRewritten() {
        let original = #"{"status\u004Cine":{"type":"command"},"theme":"dark"}"#
        switch SettingsEditor.removing("statusLine", from: original) {
        case .rewritten(let text):
            #expect(!text.contains("statusLine") && !text.contains("u004C"))
            #expect(text.contains("dark"), "the neighbours survive the rebuild")
        case .surgical:
            Issue.record("an escaped key name was cut textually; that cut cannot be trusted")
        case .absent:
            Issue.record("the key was there, spelled with an escape")
        }
    }

    @Test("absent, when there is no such key")
    func removalAbsent() {
        guard case .absent = SettingsEditor.removing("statusLine", from: #"{"theme":"dark"}"#) else {
            Issue.record("expected .absent")
            return
        }
    }

    // MARK: SnapshotStoreError

    private func store(_ body: String?) -> SnapshotStore {
        let dir = sandbox().appending(path: "exchange")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let body {
            try! body.write(to: dir.appending(path: "snapshot.json"),
                            atomically: true, encoding: .utf8)
        }
        return SnapshotStore(containerURL: dir)
    }

    @Test("fileMissing, before anything has been written")
    func errorFileMissing() {
        var thrown: Error?
        do { _ = try store(nil).load() } catch { thrown = error }
        guard case .fileMissing? = thrown as? SnapshotStoreError else {
            Issue.record("expected fileMissing, got \(String(describing: thrown))")
            return
        }
    }

    @Test("malformed, when the JSON does not parse")
    func errorMalformed() {
        var thrown: Error?
        do { _ = try store("{ not json").load() } catch { thrown = error }
        guard case .malformed? = thrown as? SnapshotStoreError else {
            Issue.record("expected malformed, got \(String(describing: thrown))")
            return
        }
    }

    /// A newer schema is refused rather than guessed at: drawing from fields
    /// whose meaning may have changed is worse than drawing a dash.
    @Test("unsupportedSchema, when the exporter is newer than the widget")
    func errorUnsupportedSchema() {
        let future = ccwidgetSupportedSchemaVersion + 1
        var thrown: Error?
        do {
            _ = try store(#"{"schemaVersion":\#(future),"capturedAt":0,"limits":{}}"#).load()
        } catch { thrown = error }

        guard case .unsupportedSchema(let found, let supported)? = thrown as? SnapshotStoreError else {
            Issue.record("expected unsupportedSchema, got \(String(describing: thrown))")
            return
        }
        #expect(found == future)
        #expect(supported == ccwidgetSupportedSchemaVersion)
    }

    /// A file that exists and cannot be read is a different problem from one
    /// that is not there, and the log has to be able to tell them apart —
    /// "permission denied" and "no such file" look identical otherwise.
    @Test("unreadable, when the file exists but cannot be opened")
    func errorUnreadable() throws {
        let dir = sandbox().appending(path: "exchange")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "snapshot.json")
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        var thrown: Error?
        do { _ = try SnapshotStore(containerURL: dir).load() } catch { thrown = error }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        guard case .unreadable? = thrown as? SnapshotStoreError else {
            Issue.record("expected unreadable, got \(String(describing: thrown))")
            return
        }
    }
}

/// Which build the app admits to being.
///
/// Every case is produced here, because the row is the only place the answer
/// appears and a row that lies is worse than no row: on 17 August the installed
/// bundle said `0.3.2` while carrying work the `v0.3.2` tag does not have, and
/// nothing in the app could say so.
@Suite("The build the app admits to")
struct AppBuildTests {

    private let english = Locale(identifier: "en_US_POSIX")

    @Test("A release names its commit")
    func aReleaseNamesItsCommit() {
        let build = AppBuild(version: "0.3.3", commit: "2ccab9f")
        #expect(build == .stamped(version: "0.3.3", commit: "2ccab9f"))
        #expect(build.text(locale: english) == "0.3.3 (2ccab9f)")
    }

    /// An empty build setting arrives as an empty string, not as a missing key,
    /// which is why this is trimmed rather than compared to `nil`.
    @Test("An ordinary build says it is not a release, rather than leaving a blank",
          arguments: ["", "   "])
    func anOrdinaryBuildSaysSo(commit: String) {
        let build = AppBuild(version: "0.3.3", commit: commit)
        #expect(build == .unstamped(version: "0.3.3"))
        #expect(build.text(locale: english) == "0.3.3 · not a release build")
    }

    @Test("No commit at all is the same answer as an empty one")
    func absentCommitIsTheSame() {
        #expect(AppBuild(version: "0.3.3", commit: nil) == .unstamped(version: "0.3.3"))
    }

    @Test("A bundle that will not say its version says exactly that",
          arguments: [nil, "", " "])
    func noVersionIsNamed(version: String?) {
        let build = AppBuild(version: version, commit: "2ccab9f")
        #expect(build == .unknown)
        #expect(build.text(locale: english) == "unknown")
    }

    /// The three readings must differ on screen, not merely as values — the row
    /// exists to be read.
    @Test("The three readings are three different sentences")
    func theThreeReadingsDiffer() {
        let texts = [AppBuild.stamped(version: "0.3.3", commit: "2ccab9f"),
                     .unstamped(version: "0.3.3"),
                     .unknown].map { $0.text(locale: english) }
        #expect(Set(texts).count == 3, "\(texts)")
    }

    /// And the running bundle answers. In a test bundle there is no
    /// `CCWidgetCommit`, so this is `unknown` or `unstamped` and never
    /// `stamped` — which is the point: a check cannot be fooled into thinking a
    /// test host is a release.
    @Test("The running bundle gives an answer of its own")
    func theRunningBundleAnswers() {
        #expect(AppBuild.current != .stamped(version: "0.3.3", commit: "2ccab9f"))
        #expect(!AppBuild.current.text(locale: english).isEmpty)
    }
}
