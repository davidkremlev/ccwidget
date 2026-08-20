import AppKit
import SwiftUI

// The application's entry, spelled out so that one flag can be answered
// before AppKit exists. `--reinstall-exporter` is what the Homebrew cask's
// postflight runs right after an upgrade has torn setup down; it must decide,
// write, and exit without a window, a Dock icon, or a login-item check —
// which is why it is handled here and not in the app delegate, where the
// process is already an application. Everything else is the ordinary launch.
if CommandLine.arguments.contains(UpgradeRepair.flag) {
    exit(UpgradeRepair.perform(installer: .live()))
}
CCWidgetApp.main()
