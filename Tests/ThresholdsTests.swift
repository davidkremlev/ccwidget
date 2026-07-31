import Foundation
import SwiftUI
import Testing

/// The boundaries at which a row changes colour and shape, and the ages at
/// which the widget stops trusting its own numbers.
///
/// These are three-line switch statements and were the last untested logic in
/// the project. That is precisely why they are worth pinning: a threshold is
/// a number someone will one day nudge by one, and nothing else in the codebase
/// would notice. The checks below are written as boundaries — 49/50, 80/81,
/// 99/100 — because an off-by-one is the only mistake these can carry.
@Suite("Levels and freshness")
struct ThresholdsTests {

    private func window(_ used: Int) -> LimitWindow {
        LimitWindow(usedPercentage: used, resetsAt: Date())
    }

    private func context(_ used: Int?) -> ContextInfo {
        ContextInfo(usedPercentage: used, totalInputTokens: nil,
                    windowSize: nil, cacheHitRatio: nil)
    }

    // MARK: Limits

    @Test("A limit is healthy below half and warns from half",
          arguments: [(0, Level.healthy), (49, .healthy), (50, .warning), (80, .warning)])
    func limitHealthyToWarning(used: Int, expected: Level) {
        #expect(window(used).level == expected, "\(used) % used")
    }

    @Test("A limit turns critical at 81 and depleted only at 100",
          arguments: [(81, Level.critical), (99, .critical), (100, .depleted)])
    func limitCriticalToDepleted(used: Int, expected: Level) {
        #expect(window(used).level == expected, "\(used) % used")
    }

    /// The exporter rounds, but nothing stops a future field from arriving
    /// above 100 — and "104 % used" must not fall through to healthy.
    @Test("Past 100 stays depleted")
    func limitBeyondFull() {
        #expect(window(101).level == .depleted)
        #expect(window(250).level == .depleted)
    }

    // MARK: Context

    /// The context turns red at 70 where a limit is still yellow, and that is
    /// deliberate: past roughly 70 % the model starts losing the beginning of
    /// the conversation, which is worth seeing before it happens.
    @Test("The context warns earlier than a limit does",
          arguments: [(0, Level.healthy), (49, .healthy), (50, .warning),
                      (70, .warning), (71, .critical), (100, .critical)])
    func contextLevels(used: Int, expected: Level) {
        #expect(context(used).level == expected, "\(used) % full")
    }

    @Test("The context has no level when the field is absent")
    func contextWithoutValue() {
        // Nothing to draw is not the same as zero, and a green tick against a
        // missing measurement would be a lie.
        #expect(context(nil).level == nil)
    }

    @Test("The context never reaches depleted")
    func contextIsNeverDepleted() {
        // Filling the window costs nothing and blocks nothing — it is not a
        // quota, and the grey "you are out" state does not apply to it.
        for used in stride(from: 0, through: 100, by: 5) {
            #expect(context(used).level != .depleted, "\(used) % full")
        }
    }

    // MARK: Freshness

    @Test("Freshness follows the age",
          arguments: [(0.0, Freshness.fresh), (299, .fresh), (300, .recent),
                      (3599, .recent), (3600, .stale), (86_399, .stale),
                      (86_400, .abandoned)])
    func freshnessBoundaries(age: TimeInterval, expected: Freshness) {
        #expect(Freshness(age: age) == expected, "\(Int(age)) s old")
    }

    /// A clock that has gone backwards — a snapshot stamped in the future —
    /// must read as fresh rather than fall off the end of the switch.
    @Test("A snapshot from the future is fresh, not something else")
    func negativeAge() {
        #expect(Freshness(age: -60) == .fresh)
    }

    @Test("Dimming starts at stale, hiding only at abandoned")
    func dimmingAndHiding() {
        #expect(Freshness.fresh.isDimmed == false)
        #expect(Freshness.recent.isDimmed == false)
        #expect(Freshness.stale.isDimmed == true)
        #expect(Freshness.abandoned.isDimmed == true)

        // Numbers survive being dimmed; a widget that quietly shows
        // yesterday's percentages is worse than one that admits it has none.
        #expect(Freshness.fresh.hidesNumbers == false)
        #expect(Freshness.recent.hidesNumbers == false)
        #expect(Freshness.stale.hidesNumbers == false)
        #expect(Freshness.abandoned.hidesNumbers == true)
    }

    // MARK: Glyphs

    /// Colour must not be the only carrier of meaning. Four levels, four
    /// shapes — if two ever collide, the widget stops working for anyone who
    /// cannot separate green from red.
    @Test("Every level has its own symbol")
    func symbolsAreDistinct() {
        let symbols = [Level.healthy, .warning, .critical, .depleted].map(\.symbolName)
        #expect(Set(symbols).count == symbols.count, "\(symbols)")
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    /// The colours are the other half of the same promise. They are system
    /// colours on purpose — those adapt to light, dark and the accessibility
    /// settings without a palette of ours to maintain — but four levels still
    /// have to be four colours.
    @Test("Every level has its own colour")
    func coloursAreDistinct() {
        let colours = [Level.healthy, .warning, .critical, .depleted].map(\.color)
        #expect(Set(colours).count == colours.count, "\(colours)")
    }
}
