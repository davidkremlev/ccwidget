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

/// The zone everything is rendered in.
///
/// Pinned alongside the fixture and the moment, for the reason the two of them
/// are pinned: a reset that prints "Fri 5:10 AM" here and "Fri 12:10 AM"
/// somewhere else is not a reproducible picture. This was missed once already
/// and cost a red build — `chart-runs-out.png` had a time zone baked into it,
/// and the check that compared it failed the first time it ran on another
/// machine. See Docs/rendering-checks.md, "Step 0, answered".
let renderZone: TimeZone = {
    if let index = arguments.firstIndex(of: "--time-zone"), index + 1 < arguments.count,
       let zone = TimeZone(identifier: arguments[index + 1]) {
        return zone
    }
    // Live shots follow the machine, because they are a picture of that
    // machine. A fixture is a picture of nothing in particular and gets UTC.
    return fixture == nil ? .current : TimeZone(identifier: "UTC")!
}()
NSTimeZone.default = renderZone

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
/// `ImageRenderer.scale` defaults to **1.0** — measured, not documented: Apple
/// publishes the property and not its default. Measured on both a 1× and a 2×
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
        // Explicitly, as well as through the process default above: the views
        // read the zone from the environment, and what a check can set is what
        // a check can trust.
        .environment(\.timeZone, renderZone)
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

// Measured on macOS 26.6 through `TimelineProviderContext.displaySize`, not
// taken from a table: Apple publishes widget dimensions for iOS, iPadOS,
// visionOS and watchOS, and none for macOS. The previous numbers here —
// 158×158, 338×158, 338×354 — were the iOS row for a 393-point phone. Note
// that the large tile on a Mac is square, where on iOS it is taller than wide.
// See section 9 of SPEC.md.
let small = CGSize(width: 164, height: 164)
let medium = CGSize(width: 344, height: 164)
let large = CGSize(width: 344, height: 344)

for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
    shoot("small-\(suffix)", small, scheme) { SmallView(entry: entry) }
    shoot("medium-\(suffix)", medium, scheme) { MediumView(entry: entry) }
    shoot("large-\(suffix)", large, scheme) { LargeView(entry: entry) }
}

// MARK: The one image that goes somewhere else

/// A single 16:9 picture holding two of the tiles.
///
/// **Why one and why this shape.** Posted to X as two separate images, they are
/// laid side by side and *center-cropped to a tall slot* — roughly 7:8 each —
/// which cut the labels off the left edge of the wide medium tile and reduced
/// the square large one to a strip. A single image at 16:9 is shown whole.
/// Learned the hard way, on a published post, and then read rather than guessed;
/// the sources are in `SOURCES.md` under "how to do it right".
///
/// 800×450 points at `renderScale` 2 gives exactly the 1600×900 those sources
/// name. The tiles keep their real dimensions from section 9 — nothing here is
/// resized, because a tile drawn at the wrong size is no longer a picture of
/// the product.
/// **A second shape for a second platform.** Upwork's portfolio shows a 4:3
/// thumbnail — 1000×750 recommended, 400×300 minimum, 4000×4000 maximum, per
/// its help centre and community answers (`SOURCES.md`, read live, 18 August
/// 2026) — and a 16:9 image dropped into a 4:3 slot loses its edges the same
/// way the X post did. So the canvas is a parameter: 800×450 for X, 800×600
/// for the portfolio, at `renderScale` 2 either way. Same tiles, same
/// arithmetic; only the margins around them change.
@MainActor
func shootPoster(_ name: String, _ scheme: ColorScheme, canvas: CGSize = CGSize(width: 800, height: 450)) {
    let backdrop = scheme == .dark
        ? [Color(red: 0.09, green: 0.09, blue: 0.11), Color(red: 0.16, green: 0.15, blue: 0.19)]
        : [Color(red: 0.94, green: 0.94, blue: 0.96), Color(red: 0.86, green: 0.87, blue: 0.91)]

    /// One tile, dressed the way the system dresses it.
    func tile(_ size: CGSize, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(14)
            .frame(width: size.width, height: size.height)
            .background(scheme == .dark ? Color(white: 0.14) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // All three sizes, and the arithmetic is the reason it composes: the medium
    // and the small stacked with a 16-point gap come to 344 points, which is
    // exactly the height of the large one beside them. Nothing is scaled to
    // make that work.
    let body = HStack(alignment: .top, spacing: 40) {
        tile(large) { LargeView(entry: entry) }
        VStack(alignment: .leading, spacing: 16) {
            tile(medium) { MediumView(entry: entry) }
            tile(small) { SmallView(entry: entry) }
        }
    }
    .frame(width: canvas.width, height: canvas.height)
    .background(LinearGradient(colors: backdrop, startPoint: .topLeading, endPoint: .bottomTrailing))
    .environment(\.colorScheme, scheme)
    .environment(\.dynamicTypeSize, typeSize)
    .environment(\.timeZone, renderZone)

    let renderer = ImageRenderer(content: body)
    renderer.scale = renderScale
    renderer.isOpaque = true
    guard let png = encodePNG(renderer) else {
        FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
        return
    }
    let url = outDir.appending(path: "\(name).png")
    try! png.write(to: url)
    print("\(url.lastPathComponent)  \(Int(canvas.width * renderScale))×\(Int(canvas.height * renderScale))")
}

shootPoster("poster-dark", .dark)
shootPoster("poster-light", .light)
shootPoster("portfolio-dark", .dark, canvas: CGSize(width: 800, height: 600))
shootPoster("portfolio-light", .light, canvas: CGSize(width: 800, height: 600))
