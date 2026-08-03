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
    /// Data under an hour old.
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

        switch Freshness(of: snapshot, at: now) {
        case .fresh: self = .working
        case .stale: self = .outdated
        case .abandoned: self = .abandoned
        }
    }

    /// Whether the window can draw bars at all. Everything else shows an
    /// explanation instead.
    ///
    /// `.abandoned` used to be on the other side of this. Section 2.4 says
    /// numbers over a day old are replaced by an invitation rather than shown,
    /// and the widget did that while the window went on drawing the bars — so
    /// the two cases the window has for old data, `.outdated` and
    /// `.abandoned`, came out of it identical: same badge, same colour, same
    /// bars. The window is where the comparison with the Usage panel happens,
    /// which makes day-old percentages worse there, not better.
    var showsData: Bool {
        switch self {
        case .working, .outdated: return true
        case .needsWidget, .needsSetup, .waiting, .abandoned: return false
        }
    }

    // MARK: What the window says

    /// How loudly the badge speaks. A named level rather than a `Color`: a
    /// colour cannot be asked what it means.
    enum Tone: String, Equatable {
        case good
        case quiet
        case attention
    }

    var tone: Tone {
        switch self {
        case .working: return .good
        case .waiting: return .quiet
        case .needsWidget, .needsSetup, .outdated, .abandoned: return .attention
        }
    }

    /// The badge text. Composed here rather than in the view for the reason
    /// this whole type left the view: a `Text` cannot be read back, and two
    /// states that produce the same one are two states nothing can tell apart.
    func badge(locale: Locale = .autoupdatingCurrent) -> String {
        switch self {
        case .needsWidget, .needsSetup: return localized("Setup needed", locale)
        case .waiting: return localized("Waiting", locale)
        case .working: return localized("Working", locale)
        case .outdated, .abandoned: return localized("Check needed", locale)
        }
    }

    /// What stands in place of the bars, or `nil` when the bars are drawn.
    func explanation(locale: Locale = .autoupdatingCurrent) -> String? {
        switch self {
        case .needsWidget:
            return localized("Add the widget to your desktop first. Right-click the desktop, choose Edit Widgets, then come back.", locale)
        case .needsSetup:
            return localized("The status line is not pointing at this app yet, so nothing is being written.", locale)
        case .waiting:
            return localized("Waiting for Claude Code to send data. Send any message in the terminal.", locale)
        case .abandoned:
            // The same words the widget uses. One rule, two surfaces: the
            // sentence a person reads about stale data should not depend on
            // which of our windows they happen to be looking at.
            return localized("Data is stale", locale)
                + " · " + localized("Launch Claude Code in the terminal to refresh.", locale)
        case .working, .outdated:
            return nil
        }
    }

    private func localized(_ resource: LocalizedStringResource, _ locale: Locale) -> String {
        var copy = resource
        copy.locale = locale
        return String(localized: copy)
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
