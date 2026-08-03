import SwiftUI
import AppKit

// README screenshots. A tool rather than a one-off render: they have to be
// re-shootable with a single command, otherwise the first layout change makes
// them stale and the README starts lying.
//
//   swiftc -swift-version 6 -target arm64-apple-macos14.0 \
//       Shared/*.swift Widget/{Provider,Components,SmallView,MediumView,LargeView,ForecastChart}.swift \
//       Tools/ccwidget-screenshots/main.swift -o .build/ccwidget-screenshots
//   ./.build/ccwidget-screenshots Docs/screenshots -AppleLocale en_US -AppleLanguages "(en)"
//
// The locale is set explicitly: the README is in English while numbers and
// dates follow the system region (section 10). Without -AppleLocale the shots
// come out with localized durations under English captions.

let arguments = CommandLine.arguments
let outDir = URL(filePath: arguments.count > 1 && !arguments[1].hasPrefix("-")
                 ? arguments[1] : "Docs/screenshots")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Optional `--type-size <name>`, e.g. `--type-size accessibility3`.
///
/// macOS has no system-wide setting that would do this for us. Its
/// accessibility "Text size" applies only to applications listed in that
/// pane — Apple's own, plus whatever has opted in — so a third-party app and
/// its widget cannot be checked by turning a switch on. Rendering at the size
/// is the only way to find out whether the layout survives it.
let typeSize: DynamicTypeSize = {
    guard let index = arguments.firstIndex(of: "--type-size"),
          index + 1 < arguments.count else { return .large }
    switch arguments[index + 1] {
    case "xSmall": return .xSmall
    case "small": return .small
    case "large": return .large
    case "xLarge": return .xLarge
    case "xxLarge": return .xxLarge
    case "xxxLarge": return .xxxLarge
    case "accessibility1": return .accessibility1
    case "accessibility2": return .accessibility2
    case "accessibility3": return .accessibility3
    case "accessibility4": return .accessibility4
    case "accessibility5": return .accessibility5
    default: return .large
    }
}()

/// Optional `--fixture <directory>`: a `snapshot.json` and a `history.jsonl`
/// committed to the repository, plus a fixed moment to render them at.
///
/// Live data is the default and stays the default for the README, whose
/// screenshots claim to be real. Baselines cannot use it: two runs six seconds
/// apart differ by a third of a percent of the pixels, because the countdown
/// ticks and the age moves. That is not a macOS problem and no tolerance
/// solves it — the fixture removes it.
let fixture: URL? = {
    guard let index = arguments.firstIndex(of: "--fixture"), index + 1 < arguments.count
    else { return nil }
    return URL(filePath: arguments[index + 1])
}()

/// The moment everything is rendered at. Fixed alongside the fixture, because
/// a snapshot with a frozen capture time and a moving "now" is exactly as
/// unreproducible as live data.
let now: Date = {
    guard let index = arguments.firstIndex(of: "--now"), index + 1 < arguments.count,
          let seconds = TimeInterval(arguments[index + 1])
    else { return fixture == nil ? Date() : Date(timeIntervalSince1970: 1_700_000_000) }
    return Date(timeIntervalSince1970: seconds)
}()

let store = fixture.map { SnapshotStore(containerURL: $0) } ?? SnapshotStore.default()
let snapshot = try? store.load()
let history = HistoryStore(store: store).load()
let week = snapshot?.limits.sevenDay
let forecast = week.map { Forecast.make(history: history, window: $0, now: now) }
let entry = CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: forecast)

guard snapshot != nil else {
    let message = fixture == nil
        ? "no snapshot yet — run Claude Code first\n"
        : "the fixture has no readable snapshot.json\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

/// Corner radius of desktop widgets on macOS.
let cornerRadius: CGFloat = 20

/// Pinned so the images are Retina-sized, and pinned rather than defaulted so
/// nothing silently halves them.
///
/// `ImageRenderer.scale` defaults to **1.0** — measured on both a 1× and a 2×
/// main display, and it is 1.0 on each. It does *not* follow the screen, which
/// is the thing this comment used to claim; the claim was inherited from how
/// `NSImage` behaves and never checked. Removing the pin does not make the
/// output depend on the hardware — it makes it half size everywhere.
///
/// What the renderer does propagate is this value into the view's
/// `\.displayScale`, so pinning it pins everything that scales with it —
/// hairlines, capsule edges, text hinting. A probe that renders its own
/// `\.displayScale` reads back whatever is set here.
let renderScale: CGFloat = 2

/// sRGB explicitly.
///
/// Also measured on both panels — the external monitor with its own profile
/// and the built-in one — and the renderer produced sRGB on each, so this
/// conversion is currently a no-op. It stays because "currently" is doing a
/// lot of work in that sentence: a wide-gamut panel on somebody else's desk is
/// exactly what would make it stop being one, and the cost of the line is
/// nothing.
@MainActor
func encodePNG(_ renderer: ImageRenderer<some View>) -> Data? {
    guard let cgImage = renderer.cgImage else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
    return srgb.representation(using: .png, properties: [:])
}

@MainActor
func shoot(_ name: String, _ size: CGSize, _ scheme: ColorScheme, @ViewBuilder _ content: () -> some View) {
    let body = content()
        .padding(14)
        .frame(width: size.width, height: size.height)
        .background(scheme == .dark ? Color(white: 0.14) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .environment(\.colorScheme, scheme)
        .environment(\.dynamicTypeSize, typeSize)
        // Margin around it: a rounded corner must not touch the image edge.
        .padding(12)

    let renderer = ImageRenderer(content: body)
    renderer.scale = renderScale
    renderer.isOpaque = false
    guard let png = encodePNG(renderer) else {
        FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
        return
    }
    let url = outDir.appending(path: "\(name).png")
    try! png.write(to: url)
    print("\(url.lastPathComponent)  \(Int(size.width))×\(Int(size.height))")
}

let small = CGSize(width: 158, height: 158)
let medium = CGSize(width: 338, height: 158)
let large = CGSize(width: 338, height: 354)

for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
    shoot("small-\(suffix)", small, scheme) { SmallView(entry: entry) }
    shoot("medium-\(suffix)", medium, scheme) { MediumView(entry: entry) }
    shoot("large-\(suffix)", large, scheme) { LargeView(entry: entry) }
}
