import AppKit
import Foundation
import SwiftUI
import Testing

/// Tier 3 of the rendering plan: five pictures, and only five.
///
/// The estimate chart is the one thing in this widget whose correctness is a
/// shape rather than a string. It once drew a stub — a line a few pixels long
/// in the corner — in the state where it should have drawn nothing at all, and
/// no check that reads text would ever have noticed. Everything else the plan
/// covers is caught more cheaply by tiers 1 and 2, which is why this is five
/// images and not a grid of ninety-six.
///
/// One size, one appearance, one language, five outcomes. Adding a language
/// column here would multiply the files and catch nothing tier 1 does not
/// already catch.
@MainActor
/// Serialized on purpose. Rendering the same view twice gave different bytes
/// while the suites ran in parallel, and the screenshot tool — the same
/// renderer in a plain executable — is byte-for-byte stable across processes.
/// Whatever the shared state is, a baseline suite cannot race against one.
@Suite("Chart geometry", .serialized)
struct ChartBaselineTests {

    /// Baselines are only meaningful where the renderer is the one they were
    /// taken with. Whether `ImageRenderer` agrees across macOS versions is
    /// still unmeasured — the CI job that answers it is step zero of the plan
    /// — so until then the minimum-version runner skips this suite rather than
    /// failing for a reason that is not a defect.
    private static var skipped: Bool {
        ProcessInfo.processInfo.environment["CCWIDGET_SKIP_IMAGE_BASELINES"] == "1"
    }

    private static let baselines = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Baselines")

    /// The width of the large tile less the widget's padding. The height is
    /// the block's own: it is a caption, an optional chart and a verdict, and
    /// how tall that comes out is part of what is being checked.
    private static let width: CGFloat = 310

    /// Padding around the block, so the baseline is not flush to the edge.
    private static let inset: CGFloat = 8

    /// Pinned so the baselines are Retina-sized, and pinned rather than
    /// defaulted so nothing silently halves them.
    ///
    /// `ImageRenderer.scale` defaults to **1.0** and does not follow the main
    /// display — measured on a 1× monitor and a 2× built-in panel, and it is
    /// 1.0 on both. Baselines taken with one display primary verify unchanged
    /// with the other primary, byte for byte.
    ///
    /// The renderer does propagate this value into the view's
    /// `\.displayScale`, so pinning it pins everything that scales with it.
    private static let scale: CGFloat = 2

    // MARK: The five outcomes

    private func series(
        count: Int, stepMinutes: Double, from start: Int, per step: Double,
        resets: Date, now: Date, noise: (Int) -> Double = { _ in 0 }
    ) -> [HistoryEntry] {
        (0..<count).map { i in
            HistoryEntry(
                time: now.addingTimeInterval(-Double(count - 1 - i) * stepMinutes * 60),
                sevenDayUsed: Int((Double(start) + step * Double(i) + noise(i)).rounded()),
                resetsAt: resets)
        }
    }

    /// A fixed moment, for the same reason the screenshot tool takes one: a
    /// chart drawn against a moving clock is a different chart every run.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func scenario(_ name: String) -> (Forecast, LimitWindow) {
        switch name {
        case "not-enough-data":
            let resets = now.addingTimeInterval(20 * 3600)
            let window = LimitWindow(usedPercentage: 60, resetsAt: resets)
            let saw: (Int) -> Double = { $0 % 2 == 0 ? -18 : 18 }
            return (Forecast.make(history: series(count: 30, stepMinutes: 10, from: 30, per: 0.2,
                                                  resets: resets, now: now, noise: saw),
                                  window: window, now: now), window)
        case "flat":
            let resets = now.addingTimeInterval(20 * 3600)
            let window = LimitWindow(usedPercentage: 55, resetsAt: resets)
            return (Forecast.make(history: series(count: 20, stepMinutes: 15, from: 55, per: 0,
                                                  resets: resets, now: now),
                                  window: window, now: now), window)
        case "rate-only":
            let resets = now.addingTimeInterval(6.9 * 24 * 3600)
            let window = LimitWindow(usedPercentage: 3, resetsAt: resets)
            return (Forecast.make(history: series(count: 13, stepMinutes: 10, from: 1, per: 0.15,
                                                  resets: resets, now: now),
                                  window: window, now: now), window)
        case "lasts-until-reset":
            let resets = now.addingTimeInterval(140 * 3600)
            let window = LimitWindow(usedPercentage: 11, resetsAt: resets)
            return (Forecast.make(history: series(count: 40, stepMinutes: 40, from: 1, per: 0.25,
                                                  resets: resets, now: now),
                                  window: window, now: now), window)
        default:
            let resets = now.addingTimeInterval(5 * 24 * 3600)
            let window = LimitWindow(usedPercentage: 80, resetsAt: resets)
            return (Forecast.make(history: series(count: 15, stepMinutes: 20, from: 60, per: 1.4,
                                                  resets: resets, now: now),
                                  window: window, now: now), window)
        }
    }

    // MARK: Rendering

    /// `ForecastBlock` rather than `ForecastChart`, and the distinction is not
    /// cosmetic. The decision *not* to draw the chart lives in the block, and
    /// the first version of this suite rendered the chart directly — so its
    /// "not enough data" baseline pinned the geometry of a stub that nobody is
    /// ever shown. A baseline of a view the product does not display is worse
    /// than none: it would have failed the day somebody fixed something.
    private func render(_ name: String) -> Data? {
        let (forecast, window) = scenario(name)
        let view = ForecastBlock(forecast: forecast, window: window)
            .frame(width: Self.width)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Self.inset)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))

        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.scale
        renderer.isOpaque = true

        // sRGB explicitly. The renderer produced sRGB on a monitor whose own
        // profile is anything but, which suggests it always does — but a
        // wide-gamut panel is exactly what would prove that wrong on somebody
        // else's desk, and a baseline is not the place to find out.
        guard let cgImage = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let srgb = rep.converting(to: .sRGB, renderingIntent: .default) ?? rep
        return srgb.representation(using: .png, properties: [:])
    }

    @Test("The chart matches its baseline in every outcome",
          arguments: ["not-enough-data", "flat", "rate-only", "lasts-until-reset", "runs-out"])
    func chartMatchesBaseline(name: String) throws {
        guard !Self.skipped else { return }

        let produced = try #require(render(name), "\(name) did not render")
        let url = Self.baselines.appending(path: "chart-\(name).png")

        guard let existing = try? Data(contentsOf: url) else {
            try FileManager.default.createDirectory(at: Self.baselines,
                                                    withIntermediateDirectories: true)
            try produced.write(to: url)
            Issue.record("no baseline for \(name); one was written — look at it and commit it")
            return
        }

        if produced != existing {
            try? produced.write(to: url.appendingPathExtension("actual"))
        }
        #expect(produced == existing,
                "chart-\(name).png differs; compare it with the .actual beside it")
    }

    /// The pinning itself, held by the committed files rather than by the code
    /// that wrote them.
    ///
    /// Without this a future edit could drop `renderer.scale` — it looks like
    /// a default, and the checks would keep passing on whichever machine
    /// regenerated the baselines — and the images would silently start
    /// depending on which monitor was primary. The rule from CLAUDE.md
    /// applies: a value that cannot be read back stays wrong longest.
    @Test("Every baseline is at the pinned scale and in sRGB",
          arguments: ["not-enough-data", "flat", "rate-only", "lasts-until-reset", "runs-out"])
    func baselinesArePinned(name: String) throws {
        guard !Self.skipped else { return }

        let url = Self.baselines.appending(path: "chart-\(name).png")
        let data = try Data(contentsOf: url)
        let rep = try #require(NSBitmapImageRep(data: data))

        let expectedWidth = Int((Self.width + 2 * Self.inset) * Self.scale)
        #expect(rep.pixelsWide == expectedWidth,
                "\(name): \(rep.pixelsWide) px wide, expected \(expectedWidth) at \(Self.scale)×")
        #expect(rep.colorSpace.localizedName?.contains("sRGB") == true,
                "\(name): colour space is \(rep.colorSpace.localizedName ?? "unknown")")
    }

    /// The outcomes have to be the ones they claim to be, or five images would
    /// be five pictures of the same thing.
    @Test("Each scenario produces the outcome it is named for",
          arguments: [("not-enough-data", "notEnoughData"), ("flat", "flat"),
                      ("rate-only", "rateOnly"), ("lasts-until-reset", "lastsUntilReset"),
                      ("runs-out", "runsOut")])
    func scenariosProduceTheirOutcomes(name: String, expected: String) {
        let (forecast, _) = scenario(name)
        let actual: String
        switch forecast.outcome {
        case .notEnoughData: actual = "notEnoughData"
        case .flat: actual = "flat"
        case .rateOnly: actual = "rateOnly"
        case .lastsUntilReset: actual = "lastsUntilReset"
        case .runsOut: actual = "runsOut"
        }
        #expect(actual == expected, "\(name) produced \(actual)")
    }

    /// The stub the tier exists for. The axis runs to the reset, which can be
    /// six days away, so a couple of hours of points occupy a few per cent of
    /// the width — a mark on the left that says nothing and reads as broken.
    ///
    /// The refusal has to be checked with points present, or it checks the
    /// wrong thing: an empty chart is easy, a chart with data that must still
    /// not be drawn is the case.
    @Test("With too little data the chart is not drawn at all")
    func noChartWithoutData() {
        let (forecast, _) = scenario("not-enough-data")
        #expect(!forecast.showsProjection)
        #expect(forecast.points.count >= 2,
                "the fixture must have points, or this checks the wrong refusal")
    }
}
