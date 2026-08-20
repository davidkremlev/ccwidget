import Foundation

/// Setup, restored after the upgrade that removed it.
///
/// A Homebrew upgrade runs the cask's uninstall script on its way past, and
/// the script removes the exporter and the `statusLine` key — correctly, so
/// that a plain `brew uninstall` does not leave a status line running a file
/// that is gone. The cost fell on upgrades: every one of them tore setup down
/// and waited for a person to open the window and press one button. Seen on
/// this machine at both 0.3.4 upgrades on 21 August 2026.
///
/// So the cask's postflight now runs the freshly installed binary with
/// `--reinstall-exporter`, and this type decides what that run does. The
/// decision is separate from the doing for the usual reason: the decision is
/// arithmetic a check can walk case by case, and the doing is `Installer`.
enum UpgradeRepair {
    static let flag = "--reinstall-exporter"

    /// What the headless run decided, and why. Every case is produced by a
    /// check in `UpgradeRepairTests`, and every case differs in what the run
    /// does and logs: `alreadyConfigured` and `leaveAlone` touch nothing and
    /// say different things; `reinstall` writes the exporter and the key.
    enum Decision: Equatable {
        /// The status line is ours and the exporter is the one we wrote.
        case alreadyConfigured
        /// Setup was torn down — by the upgrade, or the exporter is missing
        /// or from an older version — and there is prior data to honour.
        case reinstall
        /// Nothing here is ours to restore: a machine that was never set up,
        /// a person's explicit removal, or a tampered exporter that the
        /// window must show loudly rather than this run overwrite quietly.
        case leaveAlone(reason: String)
    }

    /// The table. Inputs are values, not an `Installer`, so the checks state
    /// each row directly.
    ///
    /// The one subtlety is `removedByChoice`: after **Remove…, keep history**
    /// the machine looks exactly like a machine an upgrade just tore down —
    /// no key, no exporter, data on disk. Restoring setup there would undo a
    /// person's explicit decision. The Remove button therefore leaves a
    /// marker, and this table refuses to act while the marker stands. Setting
    /// up again clears it.
    static func decision(state: Installer.StatusLineState,
                         integrity: Installer.Integrity,
                         hasDataFromBefore: Bool,
                         removedByChoice: Bool) -> Decision {
        if state == .ours {
            switch integrity {
            case .matches, .unknown:
                // `.unknown` is an exporter from before the hash existed; it
                // works, and replacing a working setup is not a repair.
                return .alreadyConfigured
            case .missing, .outdated:
                return .reinstall
            case .changed:
                // The tamper banner asks the person to look at the file
                // before anything touches it. A silent overwrite here would
                // destroy exactly what it asks them to look at.
                return .leaveAlone(reason: "the exporter was modified by hand; the window's banner is the honest channel")
            }
        }
        if removedByChoice {
            return .leaveAlone(reason: "removed through the app on purpose; a marker records it")
        }
        if hasDataFromBefore {
            // The upgrade case, and the reinstall-after-uninstall case: data
            // from an earlier setup, and no record of anyone choosing to
            // remove it. A foreign status line is not an obstacle — install
            // chains it, exactly as pressing the button would.
            return .reinstall
        }
        return .leaveAlone(reason: "never set up on this machine; setup is a person's decision")
    }

    /// The headless run. Returns a process exit code; `install()` failing is
    /// reported loudly (section: тишина запрещена) but still exits 0 — the
    /// cask's postflight must not fail the whole upgrade over a repair the
    /// window can offer again.
    static func perform(installer: Installer) -> Int32 {
        let verdict = decision(state: installer.statusLineState(),
                               integrity: installer.checkIntegrity(),
                               hasDataFromBefore: installer.hasDataFromBefore,
                               removedByChoice: installer.removedByChoiceMarkerExists)
        switch verdict {
        case .alreadyConfigured:
            log("already configured; nothing to repair")
            return 0
        case .leaveAlone(let reason):
            log("leaving setup alone: \(reason)")
            return 0
        case .reinstall:
            do {
                _ = try installer.install()
                log("setup restored after upgrade")
                return 0
            } catch {
                log("repair failed: \(String(describing: error)); the window will offer setup")
                return 0
            }
        }
    }

    private static func log(_ line: String) {
        ccwidgetStoreLog.notice("upgrade repair: \(line, privacy: .public)")
        print("upgrade repair: \(line)")
    }
}
