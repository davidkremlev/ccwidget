import AppKit
import Foundation

/// Reading a rendered image, quickly.
///
/// Every composition check asks the same three questions of a picture — is there
/// ink here, how many bands of it are there, how long is the longest horizontal
/// run — and they all used `NSBitmapImageRep.colorAt(x:y:)`, which allocates an
/// `NSColor` per pixel. That is what took the whole suite from 85 seconds to
/// 330: the screen checks alone read about forty million pixels.
///
/// The same numbers come out of the bitmap's own bytes. Nothing here changes what
/// is measured, only what it costs to measure — the thresholds and the counts are
/// the ones the checks were calibrated against, and the falsifications that
/// proved them still fail in the same places.
struct PixelReader {
    let width: Int
    let height: Int
    private let bytes: [UInt8]
    private let rowBytes: Int
    private let samples: Int
    private let hasAlpha: Bool

    init?(_ rep: NSBitmapImageRep) {
        guard rep.bitsPerSample == 8, !rep.isPlanar, let data = rep.bitmapData else { return nil }
        width = rep.pixelsWide
        height = rep.pixelsHigh
        rowBytes = rep.bytesPerRow
        samples = rep.samplesPerPixel
        hasAlpha = rep.hasAlpha
        bytes = Array(UnsafeBufferPointer(start: data, count: rowBytes * height))
    }

    /// Ink drawn on transparency — the tiles, which are rendered with no
    /// background. Anything opaque is something the view drew.
    func isInkByAlpha(_ x: Int, _ y: Int, threshold: Double = 0.15) -> Bool {
        guard hasAlpha else { return true }
        let alpha = bytes[y * rowBytes + x * samples + samples - 1]
        return Double(alpha) / 255 > threshold
    }

    /// Ink drawn on white — the window and the setup screen, which are rendered
    /// with a background so that dimmed grey still counts as something.
    func isInkOnWhite(_ x: Int, _ y: Int, threshold: Double = 0.9) -> Bool {
        let i = y * rowBytes + x * samples
        let limit = UInt8(threshold * 255)
        return bytes[i] < limit || bytes[i + 1] < limit || bytes[i + 2] < limit
    }

    /// The two predicates as plain functions, because a method with a default
    /// argument cannot be passed as one.
    var inkByAlpha: (Int, Int) -> Bool { { self.isInkByAlpha($0, $1) } }
    var inkOnWhite: (Int, Int) -> Bool { { self.isInkOnWhite($0, $1) } }

    /// Rows that contain ink, grouped into bands separated by rows that do not.
    func bands(_ isInk: (Int, Int) -> Bool) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for y in 0..<height {
            var any = false
            for x in 0..<width where !any { if isInk(x, y) { any = true } }
            switch (any, start) {
            case (true, nil): start = y
            case (false, let s?): out.append(s..<y); start = nil
            default: break
            }
        }
        if let s = start { out.append(s..<height) }
        return out
    }

    func inkShare(_ isInk: (Int, Int) -> Bool) -> Double {
        var ink = 0
        for y in 0..<height {
            for x in 0..<width where isInk(x, y) { ink += 1 }
        }
        return Double(ink) / Double(width * height) * 100
    }

    /// The longest horizontal run of ink in a row, and the widest such run
    /// anywhere.
    func longestRun(in rows: Range<Int>, _ isInk: (Int, Int) -> Bool) -> Int {
        var widest = 0
        for y in rows {
            var run = 0
            for x in 0..<width {
                run = isInk(x, y) ? run + 1 : 0
                widest = max(widest, run)
            }
        }
        return widest
    }

    func longestRun(_ isInk: (Int, Int) -> Bool) -> Int {
        longestRun(in: 0..<height, isInk)
    }
}
