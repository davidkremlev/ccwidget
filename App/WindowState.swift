import Foundation

/// Which of six things the window is currently saying.
///
/// It used to be computed inside `StatusView`, as a private property of a
/// view, which made five of its six cases unreachable by any check — and a
/// case nothing expects is wrong forever by construction (see `CLAUDE.md`).
/// It is not view code: it is a decision about what the state of the world
/// means, taken from four values the model already publishes.
///
/// The view now renders a state it is handed, which is the same rule that put
/// the installer's paths and the watcher's clock behind parameters.
enum WindowState: Equatable {
    /// The system has never created the extension's container, so the widget
    /// has never run and nothing can have been written.
    case needsWidget
    /// The status line does not point at us, so nothing is being written now.
    case needsSetup
    /// Everything is in place and the first snapshot has not arrived.
    case waiting
    /// Fresh or recent data.
    case working
    /// Over an hour old.
    case outdated
    /// Over a day old.
    case abandoned

    /// The order of the questions is the whole content of this type.
    ///
    /// Setup comes before data because a missing snapshot means something
    /// different when nothing is configured to write one: "waiting" would be a
    /// lie, and a person would wait for it.
    init(containerExists: Bool, statusLineIsOurs: Bool, snapshot: Snapshot?, now: Date) {
        if !containerExists { self = .needsWidget; return }
        if !statusLineIsOurs { self = .needsSetup; return }
        guard let snapshot else { self = .waiting; return }

        switch Freshness(age: snapshot.age(at: now)) {
        case .fresh, .recent: self = .working
        case .stale: self = .outdated
        case .abandoned: self = .abandoned
        }
    }

    /// Whether the window can draw bars at all. Everything else shows an
    /// explanation instead.
    var showsData: Bool {
        switch self {
        case .working, .outdated, .abandoned: return true
        case .needsWidget, .needsSetup, .waiting: return false
        }
    }
}

/// Which of four steps the setup screen is on.
///
/// Extracted for the same reason and with the same consequence: the
/// transitions were four assignments scattered through a four-hundred-line
/// view, and no check could reach any of them.
enum OnboardingStep: Equatable {
    case checkClaudeCode
    case install
    case waitingForData
    case ready

    /// The first step is skipped when there is nothing to check: Claude Code
    /// is already installed, so asking the reader to confirm it wastes their
    /// time and teaches them to click through without reading.
    static func start(claudeCodeIsPresent: Bool) -> OnboardingStep {
        claudeCodeIsPresent ? .install : .checkClaudeCode
    }

    /// The reader pressed Continue, or the check found Claude Code.
    func afterCheckingClaudeCode(present: Bool) -> OnboardingStep {
        guard self == .checkClaudeCode, present else { return self }
        return .install
    }

    /// Installing succeeded. It does not mean data exists yet — the status
    /// line runs on the next redraw, not on this one.
    func afterInstalling() -> OnboardingStep {
        self == .install ? .waitingForData : self
    }

    /// The first snapshot landed.
    func afterFirstSnapshot() -> OnboardingStep {
        self == .waitingForData ? .ready : self
    }
}
