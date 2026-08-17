import Foundation
import WidgetKit

// Can a process that is not the app reload the widget?
//
// **No, and this is what says so.** The answer decides an architecture, so it is
// a tool rather than a memory.
//
// The plan it killed: a small background executable shipped inside the app
// bundle, registered as a launch agent, running the same `SnapshotWatcher` the
// window runs — the freshness of an open window without the window. It was
// built, it was installed inside the bundle at Contents/MacOS/, and it does not
// work. WidgetKit refuses:
//
//     widgets:  unavailable — Error Domain=ChronoCoreErrorDomain Code=27
//
// and `reloadAllTimelines()` from it changes nothing. Measured end to end with a
// control: a fresh snapshot was written, the tile went on showing the previous
// one twenty seconds later, the executable asked for a reload, and twenty-five
// seconds after that the tile still showed the previous one — only the countdown
// had ticked, which the system draws by itself.
//
// `Bundle.main` inside the bundle *is* the app — `dev.illvminat.ccwidget`,
// /Applications/CCWidget.app — so sharing a bundle is not enough. Nothing in
// Apple's documentation describes ChronoCoreErrorDomain at all; this is
// measured, on macOS 26.5, and marked as measured in SOURCES.md.
//
// What follows from it: the only process that can reload this widget is the app
// itself, so background freshness has to be the app running in the background,
// not a helper beside it. See SPEC 2.4.
//
//   swiftc -swift-version 6 -target arm64-apple-macos14.0 \
//       Shared/*.swift Tools/ccwidget-widgetkit-probe/main.swift \
//       -o .build/ccwidget-widgetkit-probe
//   cp .build/ccwidget-widgetkit-probe /Applications/CCWidget.app/Contents/MacOS/
//   /Applications/CCWidget.app/Contents/MacOS/ccwidget-widgetkit-probe
//
// Copying it into the bundle invalidates the app's signature, which is why it
// ships nowhere: it is run by hand, on a development build, to re-establish the
// fact when somebody doubts it.
//
@MainActor
func probe() {
    print("bundle:     \(Bundle.main.bundleIdentifier ?? "none — WidgetCenter will refuse")")
    print("path:       \(Bundle.main.bundlePath)")
    print("snapshot:   \(SnapshotStore.default().snapshotURL.path(percentEncoded: false))")

    let waiting = DispatchSemaphore(value: 0)
    WidgetCenter.shared.getCurrentConfigurations { result in
        switch result {
        case .success(let widgets):
            print("widgets:    \(widgets.count) configured")
            for widget in widgets {
                print("              kind=\(widget.kind) family=\(widget.family)")
            }
        case .failure(let error):
            // The interesting failure. ChronoCoreErrorDomain 27 means this
            // process is not something WidgetKit will talk to.
            print("widgets:    unavailable — \(error)")
        }
        waiting.signal()
    }
    _ = waiting.wait(timeout: .now() + 5)

    WidgetCenter.shared.reloadAllTimelines()
    print("reload:     asked for one; watch the log for `timeline built`")
}

MainActor.assumeIsolated { probe() }
