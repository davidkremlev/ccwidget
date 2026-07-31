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

let store = SnapshotStore.default()
let snapshot = try? store.load()
let history = HistoryStore(store: store).load()
let now = Date()
let week = snapshot?.limits.sevenDay
let forecast = week.map { Forecast.make(history: history, window: $0, now: now) }
let entry = CCWidgetEntry(date: now, snapshot: snapshot, failure: nil, forecast: forecast)

guard snapshot != nil else {
    FileHandle.standardError.write(Data("no snapshot yet — run Claude Code first\n".utf8))
    exit(1)
}

/// Corner radius of desktop widgets on macOS.
let cornerRadius: CGFloat = 20

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
    renderer.scale = 2
    renderer.isOpaque = false
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
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
