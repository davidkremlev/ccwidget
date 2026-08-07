// Did the tile actually draw anything?
//
// Every check in Tests/ runs where WidgetKit does not exist. Twice in one day
// that gap cost hours: in the morning the extension crashed inside
// `_ArchivedViewHost` on every render with 227 checks green, and in the
// evening the medium tile went black — no crash, no error, nothing in the log
// — while three separate rendering paths in the test process drew it
// perfectly. Both defects were about size requirements during WidgetKit's
// archiving step, and neither is reachable from a test process.
//
// This is the instrument that sees the live tile. A widget placed in
// Notification Center owns a real window, and a real window can be captured
// and counted. The desktop tile cannot: it is composited, has no window of its
// own, and the Dock layer captures empty.
//
// Usage:  swift Scripts/tile-probe.swift            # look for our tile
//         swift Scripts/tile-probe.swift image.png  # judge a file instead
//
// Exit codes: 0 drew something, 1 blank, 2 no window to judge by.

import AppKit
import CoreGraphics
import Foundation

/// The share of pixels brighter than this counts as drawn content.
///
/// Measured, not guessed. On 7 August 2026 the same tile was captured on four
/// builds: broken it held 0.023 % bright pixels (13 of 55 816 — antialiasing
/// on the rounded corner), and the three working ones held 4.90 %, 5.12 % and
/// 5.00 %. That tile carries roughly eight lines of text, so one line is about
/// 0.6 % — the threshold below is therefore "less than two lines of text on a
/// tile", which is not a tile anybody would ship, and it sits twenty times
/// above the blank reading rather than halfway between two numbers.
let brightnessCutoff: CGFloat = 0.5
let minimumInkShare = 1.0

/// Our tile's window carries the widget's display name. Both spellings are
/// ours: Notification Center caches the name from when the widget was added,
/// and this one still says "Gauge for Claude Code" months after the rename —
/// the same metadata cache that keeps the old gallery icon.
let windowNameNeedles = ["Claude Code"]

/// Whose window counts as a tile. Notification Center hosts the widget; our
/// own app hosts a status window with a similar name and similar content, and
/// judging that one would answer a different question entirely.
let notificationCenterBundle = "com.apple.notificationcenterui"

struct Reading {
    let bright: Int
    let total: Int
    var share: Double { total > 0 ? Double(bright) / Double(total) * 100 : 0 }
}

func measure(_ image: CGImage) -> Reading {
    let rep = NSBitmapImageRep(cgImage: image)
    var bright = 0, total = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                  c.alphaComponent > 0.05 else { continue }
            total += 1
            let luma = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if luma > brightnessCutoff { bright += 1 }
        }
    }
    return Reading(bright: bright, total: total)
}

func judge(_ reading: Reading, _ what: String) -> Never {
    let share = String(format: "%.3f", reading.share)
    if reading.total == 0 {
        print("?? \(what) captured nothing at all — the window went away mid-capture.")
        exit(2)
    }
    if reading.share >= minimumInkShare {
        print("==> The tile drew: \(share) % of it is text and bars (\(reading.bright) of \(reading.total) pixels).")
        exit(0)
    }
    print("!! The tile is blank: \(share) % bright pixels, against \(String(format: "%.1f", minimumInkShare)) % expected.")
    print("   It renders as a dark rectangle with nothing on it. Nothing crashes")
    print("   and nothing is logged, so this is invisible to every other check.")
    print("   Suspect a size requirement in a widget view — `.fixedSize()`,")
    print("   `GeometryReader`, a hard `.frame` — which WidgetKit's archiving")
    print("   step cannot satisfy. SPEC section 9.")
    exit(1)
}

// A file to judge, for checking the check itself against a known capture.
if CommandLine.arguments.count > 1 {
    let path = CommandLine.arguments[1]
    guard let image = NSImage(contentsOfFile: path)?
        .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("?? \(path) is not an image this can read."); exit(2)
    }
    judge(measure(image), path)
}

guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
    print("?? The window list is not available. Screen Recording permission for"); print("   this terminal is what grants it: System Settings › Privacy & Security.")
    exit(2)
}

// The name alone is not enough, and getting that wrong once is instructive:
// the app's own status window is also called "Usage Widget for Claude Code",
// so a name-only filter measured the window instead of the tile and reported
// a healthy 5 % while the tile was black. The window has to belong to
// Notification Center — that is what makes it a widget rather than a window.
let candidates = windows.filter { window in
    let name = (window[kCGWindowName as String] as? String) ?? ""
    guard windowNameNeedles.contains(where: { name.localizedCaseInsensitiveContains($0) }) else {
        return false
    }
    let pid = (window[kCGWindowOwnerPID as String] as? pid_t) ?? 0
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == notificationCenterBundle
}

guard let window = candidates.first,
      let id = window[kCGWindowNumber as String] as? Int else {
    print("?? No widget window to judge by, and that is not a pass.")
    print()
    print("   This check reads the tile from a window, and only a widget in")
    print("   Notification Center has one. The desktop tile is composited and")
    print("   cannot be captured: its Dock layer comes back empty.")
    print()
    print("   To make this answerable: open Notification Center, scroll to the")
    print("   bottom, Edit Widgets, and add this widget at the medium size.")
    print("   Then run this again.")
    exit(2)
}

let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
let size = "\(Int(bounds["Width"] ?? 0))×\(Int(bounds["Height"] ?? 0))"

// One window, by its id — never the screen. The desktop behind it belongs to
// whoever is working, and a check has no business photographing it.
// `CGWindowListCreateImage` would have done this in-process; it is gone on
// macOS 26 in favour of ScreenCaptureKit, and `screencapture -l` is the short
// way to the same picture.
let capture = URL(fileURLWithPath: NSTemporaryDirectory())
    .appending(path: "ccwidget-tile-\(getpid()).png")
let task = Process()
task.executableURL = URL(filePath: "/usr/sbin/screencapture")
task.arguments = ["-x", "-o", "-l", String(id), capture.path]
try? task.run()
task.waitUntilExit()
defer { try? FileManager.default.removeItem(at: capture) }

guard let image = NSImage(contentsOf: capture)?
    .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("?? The window is listed but did not capture. Screen Recording")
    print("   permission for this terminal is what allows it:")
    print("   System Settings › Privacy & Security › Screen Recording.")
    exit(2)
}

let name = (window[kCGWindowName as String] as? String) ?? "?"
print("==> Reading the live tile: «\(name)», \(size)")
judge(measure(image), "the tile")
