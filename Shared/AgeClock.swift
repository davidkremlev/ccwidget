import Foundation

/// The clock the snapshot's age is measured against.
///
/// Neither surface can tell the time. The widget extension never asks: it
/// draws a timeline entry stamped when the timeline was built, which is up to
/// a minute before the pixels appear. The window does ask, but on a timer, so
/// what it holds is up to one tick old. Two quantised clocks, and until they
/// were made to share a grid they disagreed — the window said "updated 42
/// seconds ago" while the widget beside it said "1 minute ago", off the same
/// file, at the same moment.
///
/// So both measure an age from the same place: the start of the minute the
/// moment falls in. Reference-date arithmetic rather than `Calendar`, because
/// the grid wanted here is absolute — every machine's minute begins at the
/// same instant, whatever its time zone offset is.
public enum AgeClock {
    /// The resolution of everything that shows an age. It is the widget's
    /// timeline step because that is what actually limits it: a widget cannot
    /// change what it says more often than it is redrawn.
    public static let step: TimeInterval = 60

    /// The start of the minute containing `moment`.
    public static func anchor(_ moment: Date) -> Date {
        boundary(atOrBefore: moment, every: step)
    }

    /// The last point of a grid of `every` seconds at or before `moment`.
    public static func boundary(atOrBefore moment: Date, every: TimeInterval) -> Date {
        let seconds = moment.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / every).rounded(.down) * every)
    }

    /// The first point of that grid strictly after `moment`. A moment sitting
    /// exactly on a boundary gets the next one, not itself: this schedules
    /// timers, and a timer due now is a timer that has already fired.
    public static func boundary(after moment: Date, every: TimeInterval) -> Date {
        boundary(atOrBefore: moment, every: every).addingTimeInterval(every)
    }
}
