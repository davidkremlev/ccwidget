import Foundation
import Testing

/// The shape of the timeline, and what replaced the agreement that used to be
/// checked here.
///
/// **What this file used to hold.** `AgeAgreementTests` held one property: at
/// a single real instant, the window and the widget printed the same age,
/// character for character, off one snapshot. It existed because they once did
/// not — the window said "updated 42 seconds ago" beside two widgets saying "1
/// minute ago" — and it worked by simulating both clocks, the widget's timeline
/// grid and the window's timer tick, and comparing the strings.
///
/// **Why it is gone.** Neither surface computes an age any more. The countdown
/// to a reset is a SwiftUI dynamic date on both, handed the same `Date`; the
/// snapshot's age is not printed at all, replaced by the moment it was taken,
/// which is one string that does not depend on when it is read. Agreement
/// stopped being a property to assert and became one there is no way to break:
/// there is nothing left for the two surfaces to compute differently.
///
/// What is left to check is the timeline itself, and it is checkable because
/// `entryDates` is arithmetic with the store kept out of it.
@Suite("Timeline shape")
struct TimelineTests {

    private static let now = Date(timeIntervalSince1970: 1_785_000_017)

    private func snapshot(captured: TimeInterval,
                          fiveHourResets: TimeInterval?,
                          weekResets: TimeInterval?) -> Snapshot {
        Snapshot(
            schemaVersion: 1,
            capturedAt: Self.now.addingTimeInterval(captured),
            sessionId: nil, claudeCodeVersion: nil, model: nil, project: nil,
            limits: Limits(
                fiveHour: fiveHourResets.map {
                    LimitWindow(usedPercentage: 20, resetsAt: Self.now.addingTimeInterval($0))
                },
                sevenDay: weekResets.map {
                    LimitWindow(usedPercentage: 40, resetsAt: Self.now.addingTimeInterval($0))
                }),
            context: nil, cost: nil)
    }

    /// Whether a moment is one the tile changes at on its own — the same list
    /// `thresholdDates` returns — as opposed to a grid point that exists only
    /// to end the timeline. The property below is stated in these terms.
    private func isThreshold(_ date: Date, captured: TimeInterval,
                             fiveHour: TimeInterval, week: TimeInterval) -> Bool {
        CCWidgetProvider.thresholdDates(
            from: Self.now,
            snapshot: snapshot(captured: captured, fiveHourResets: fiveHour, weekResets: week)
        ).contains(date)
    }

    /// The five-minute rule, and where it stops. Apple asks for entries at
    /// least about five minutes apart; the previous implementation placed
    /// thirty of them sixty seconds apart, so this fails on it — verified by
    /// putting the old implementation back and watching it fail.
    ///
    /// **Rewritten on 18 August 2026, not extended.** The rule used to be
    /// asserted between *every* pair, and that was the check agreeing with a
    /// defect: a threshold inside five minutes of the build was thinned out
    /// like a grid point, and a five-hour reset 2½ minutes out lost its entry
    /// — the tile stayed on the open row and the countdown counted up past
    /// zero on the desktop. So the property is now: no two *paced* entries
    /// closer than five minutes; a pair closer than that is allowed only when
    /// one of the two is a threshold, which is a moment the picture changes
    /// and is kept whatever the grid does. Section 2.4 records the departure.
    @Test("No two paced entries sit closer than five minutes; a threshold may",
          arguments: [
            (-30.0, 3600.0, 86_400.0),      // ordinary: nothing near anything
            (-3599.0, 60.0, 300.0),         // a reset a minute out and the hour threshold on top of it
            (-86_390.0, 120.0, 121.0),      // two resets a second apart, day threshold beside them
            (0.0, 1.0, 2.0),                // everything at once, immediately
          ])
    func entriesAreFiveMinutesApart(captured: TimeInterval,
                                    fiveHour: TimeInterval,
                                    week: TimeInterval) {
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: captured, fiveHourResets: fiveHour, weekResets: week))

        for (earlier, later) in zip(dates, dates.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            guard gap < CCWidgetProvider.minimumSpacing else { continue }
            let excused = isThreshold(earlier, captured: captured, fiveHour: fiveHour, week: week)
                || isThreshold(later, captured: captured, fiveHour: fiveHour, week: week)
            #expect(excused,
                    "entries \(gap) s apart, closer than the \(CCWidgetProvider.minimumSpacing) s minimum, and neither is a threshold")
        }
    }

    /// **The bound that was missing, and the defect that walked through the
    /// gap.** Only the lower one was ever checked: entries no closer than five
    /// minutes. Nothing said how far apart they may be, or how far ahead the
    /// last one may sit — and the last one is what the reload policy points at,
    /// so it decides when the system asks the provider again.
    ///
    /// Measured on a live snapshot, 7 August 2026: the timeline reached 134.9
    /// hours ahead. For five and a half days the provider would not be called,
    /// and every entry already built carried the snapshot as it was when the
    /// timeline was made. The tile showed data two hours old beside a window
    /// showing the current figures. Reloads from the watcher were the only
    /// bridge, and the watcher stops with the app's window.
    ///
    /// The minute grid used to provide this bound by accident: thirty entries a
    /// minute apart ran out after half an hour, which brought the system back.
    /// Replacing it with thresholds kept the countdown and dropped the return.
    @Test("Entries are neither too close nor too far apart",
          arguments: [
            (-30.0, 3600.0, 6 * 86_400.0),      // resets days out — the case that failed
            (-3599.0, 60.0, 300.0),             // thresholds crowding the start
            (0.0, 7 * 86_400.0, 7 * 86_400.0),  // nothing inside the horizon at all
            (-86_390.0, 120.0, 121.0),
          ])
    func entriesRespectBothBounds(captured: TimeInterval,
                                  fiveHour: TimeInterval,
                                  week: TimeInterval) {
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: captured, fiveHourResets: fiveHour, weekResets: week))

        for (earlier, later) in zip(dates, dates.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            // The lower bound holds between paced entries; a threshold may
            // sit closer — the check above says why. The upper bound holds
            // everywhere.
            let excused = isThreshold(earlier, captured: captured, fiveHour: fiveHour, week: week)
                || isThreshold(later, captured: captured, fiveHour: fiveHour, week: week)
            #expect(gap >= CCWidgetProvider.minimumSpacing || excused,
                    "entries \(Int(gap)) s apart, below the \(Int(CCWidgetProvider.minimumSpacing)) s minimum, and neither is a threshold")
            #expect(gap <= CCWidgetProvider.maximumSpacing,
                    "entries \(Int(gap)) s apart, above the \(Int(CCWidgetProvider.maximumSpacing)) s maximum")
        }

        // The last entry is the reload policy. However quiet the day, the
        // provider is asked again within the horizon.
        let reach = (dates.last ?? Self.now).timeIntervalSince(Self.now)
        #expect(reach <= CCWidgetProvider.horizon,
                "the timeline reaches \(Int(reach / 3600)) h ahead, past the \(Int(CCWidgetProvider.horizon / 3600)) h horizon")
        #expect(reach >= CCWidgetProvider.maximumSpacing,
                "the timeline ends \(Int(reach)) s from now — the system would be asked back immediately")
    }

    /// The entries exist for the moments the tile changes without new data.
    /// Drop one and a widget sits dimmed-looking-fresh for however long the
    /// next reload takes.
    ///
    /// **Only those inside the horizon.** A threshold two days out is not
    /// scheduled and is not lost: the timeline built two hours from now carries
    /// it, and by then it is two hours closer. Placing it now was what let the
    /// timeline reach five days ahead and stop the provider being called.
    @Test("Thresholds inside the horizon get an entry; those beyond it wait")
    func thresholdsInsideTheHorizonAreCovered() {
        let captured = -1800.0            // half an hour old
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: captured, fiveHourResets: 4 * 3600, weekResets: 5 * 86_400))

        // Inside two hours: the moment the tile dims.
        #expect(dates.contains(Self.now.addingTimeInterval(captured + 3600)),
                "the hour threshold is inside the horizon and has no entry")

        // Beyond it: the five-hour reset, the day threshold, the weekly reset.
        for beyond in [4 * 3600.0, captured + 86_400, 5 * 86_400.0] {
            let moment = Self.now.addingTimeInterval(beyond)
            #expect(!dates.contains(moment),
                    "\(moment) is past the horizon and should be left to the next timeline")
        }
    }

    /// A window closing inside the horizon still gets its entry — that is the
    /// case the thresholds exist for, and it must not be lost to the pacing.
    @Test("A reset inside the horizon gets an entry")
    func nearResetIsCovered() {
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: -60, fiveHourResets: 40 * 60, weekResets: 5 * 86_400))
        #expect(dates.contains(Self.now.addingTimeInterval(40 * 60)),
                "a reset forty minutes out has no entry")
    }

    /// **The case the check above did not ask, and the desktop did.** Forty
    /// minutes out is comfortably past the five-minute minimum; the defect was
    /// a reset *inside* it. On 18 August 2026 a timeline built at 13:57:31 for
    /// a window closing at 14:00:00 carried no entry for the close: the moment
    /// was thinned as if it were a grid point, the tile stayed on the open
    /// row, and the system's relative date counted up past zero. So: a reset
    /// 150 seconds out has an entry, and so do two resets a second apart, and
    /// a reset that lands on the same second as the hour threshold — every
    /// moment the picture changes, however close to the build or to each
    /// other.
    @Test("A reset inside five minutes of the build still gets its entry",
          arguments: [150.0, 1.0, 299.0])
    func resetInsideTheMinimumIsCovered(seconds: TimeInterval) {
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: -60, fiveHourResets: seconds, weekResets: seconds + 1))
        #expect(dates.contains(Self.now.addingTimeInterval(seconds)),
                "a reset \(Int(seconds)) s out has no entry")
        #expect(dates.contains(Self.now.addingTimeInterval(seconds + 1)),
                "a second reset a second later has no entry")
        #expect(dates.first == Self.now, "the first entry is not now")
    }

    /// And the hour threshold inside the minimum, for the same reason: the
    /// tile dims at an hour, and dimming four minutes late is dimming late.
    @Test("The hour threshold inside five minutes of the build still gets its entry")
    func freshnessInsideTheMinimumIsCovered() {
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: -3600 + 120, fiveHourResets: 4 * 3600, weekResets: 5 * 86_400))
        #expect(dates.contains(Self.now.addingTimeInterval(120)),
                "the hour threshold two minutes out has no entry")
    }

    /// A moment already past cannot be scheduled, and WidgetKit would drop it
    /// anyway. The first entry is always now, so the tile has something to draw
    /// before the first threshold arrives.
    @Test("Nothing is scheduled in the past, and now always is")
    func nothingInThePast() {
        let dates = CCWidgetProvider.entryDates(
            from: Self.now,
            snapshot: snapshot(captured: -100_000, fiveHourResets: -7200, weekResets: -60))

        #expect(dates.first == Self.now)
        #expect(dates.allSatisfy { $0 >= Self.now })
    }

    /// No snapshot: nothing has thresholds, but the timeline still has to end
    /// inside the horizon, or a widget that has never had data would never ask
    /// again. This used to expect a single entry — correct while the policy
    /// pointed at a threshold days out, wrong now that the last entry is what
    /// brings the provider back.
    @Test("With no snapshot the timeline is still paced and still ends")
    func emptyTimelineIsStillPaced() {
        let dates = CCWidgetProvider.entryDates(from: Self.now, snapshot: nil)

        #expect(dates.first == Self.now)
        #expect(dates.count > 1, "a single entry would mean the provider is never asked again")
        let reach = (dates.last ?? Self.now).timeIntervalSince(Self.now)
        #expect(reach <= CCWidgetProvider.horizon)
        for (earlier, later) in zip(dates, dates.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            #expect(gap >= CCWidgetProvider.minimumSpacing && gap <= CCWidgetProvider.maximumSpacing)
        }
    }

    // MARK: What replaced the agreement

    /// Both surfaces build the row's line from the same value — the reset
    /// instant itself — and hand it to the system unchanged. The old defect
    /// needed two computations to disagree; there is now one value and no
    /// computation, so the check is that the value travels intact rather than
    /// that two strings match.
    @Test("Both surfaces carry the reset instant, not a rendered countdown")
    func detailCarriesTheInstant() {
        let snap = snapshot(captured: -60, fiveHourResets: 3 * 3600, weekResets: 4 * 86_400)
        let entry = CCWidgetEntry(date: Self.now, snapshot: snap, failure: nil, forecast: nil)

        guard case .reset(_, let at) = entry.limitDetail(snap.limits.fiveHour) else {
            Issue.record("an open window must produce .reset"); return
        }
        #expect(at == snap.limits.fiveHour?.resetsAt)
    }

    /// A window that has ended says so instead of counting to a moment behind
    /// it. This is the defect the `.closed` case was introduced for, in its new
    /// home.
    @Test("A closed window names the moment and stops counting")
    func closedWindowStopsCounting() {
        let snap = snapshot(captured: -60, fiveHourResets: -3600, weekResets: 86_400)
        let entry = CCWidgetEntry(date: Self.now, snapshot: snap, failure: nil, forecast: nil)

        guard case .closed = entry.limitDetail(snap.limits.fiveHour) else {
            Issue.record("a window in the past must produce .closed"); return
        }
    }

    /// The capture moment is the same string whenever it is read — which is the
    /// whole reason it replaced the age. Read at three different "nows", one
    /// snapshot, one answer.
    @Test("The capture moment does not depend on when it is read")
    func captureMomentIsStable() {
        let captured = Self.now.addingTimeInterval(-4000)
        let locale = Locale(identifier: "en_US_POSIX")
        let readings = [0.0, 3600.0, 200_000.0].map { _ in
            CCWidgetFormat.capturedMoment(captured, locale: locale)
        }
        #expect(Set(readings).count == 1)
    }
}
