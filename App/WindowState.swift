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
            // One key, not two joined with a separator at runtime. Section 10
            // forbids assembling display text from parts, and the medium
            // tile's footer was already fixed once for exactly this: read
            // aloud, "Data is stale" and "Launch Claude Code…" came out as two
            // unrelated items. It is also the only form a translator can
            // punctuate, since where the sentences meet is their business.
            //
            // The widget says the same thing in different words on purpose:
            // there it is a title over a message, two slots in a layout, so it
            // is two keys. Here it is one line of prose among three others
            // written the same way. Same rule, same information, phrasing that
            // fits the shape each surface has.
            return localized("The numbers are over a day old. Launch Claude Code in the terminal to refresh.", locale)
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

    // MARK: What the step says

    /// What the setup screen puts on the reader at one step: the line in bold,
    /// the paragraph under it, and the things they can press.
    ///
    /// Composed here rather than in the view for the reason the window's badge
    /// was: four steps whose only difference is a `Text` are four steps nothing
    /// can tell apart, and this was the last enum in the project whose
    /// consequence no check could reach.
    ///
    /// Two of the steps ask about the world before they know what to say —
    /// whether Claude Code is installed, whether the widget's container exists
    /// — so those arrive as parameters. A step is not always enough on its own,
    /// and pretending otherwise would make this a smaller truth than the
    /// screen's.
    struct Script: Equatable {
        let headline: String
        let explanation: String?
        /// Button and link titles, in the order they are offered.
        let actions: [String]
    }

    func script(claudeCodeIsPresent: Bool = true,
                widgetContainerExists: Bool = true,
                locale: Locale = .autoupdatingCurrent) -> Script {
        func t(_ resource: LocalizedStringResource) -> String {
            var copy = resource
            copy.locale = locale
            return String(localized: copy)
        }

        switch self {
        case .checkClaudeCode where claudeCodeIsPresent:
            return Script(headline: t("Claude Code detected."),
                          explanation: nil,
                          actions: [t("Continue")])
        case .checkClaudeCode:
            return Script(
                headline: t("Claude Code was not found."),
                explanation: t("This widget reads the Claude Code status line, so the terminal version has to be installed and used at least once."),
                actions: [t("Install Claude Code"), t("Check again")])

        case .install where !widgetContainerExists:
            return Script(
                headline: t("Add the widget to your desktop first."),
                explanation: t("The exchange directory is created by the system when the widget first runs. Right-click the desktop, choose Edit Widgets, add Usage Widget for Claude Code, then come back."),
                actions: [t("Check again")])
        case .install:
            return Script(
                headline: t("Setup writes the exporter to ~/.claude/ and adds one key to settings.json. Only that key changes — your formatting and key order are kept."),
                explanation: nil,
                actions: [t("Set up automatically"), t("Show manual instructions")])

        case .waitingForData:
            return Script(
                headline: t("Launch Claude Code and send any message."),
                explanation: t("The status line runs on every redraw, so the first numbers appear within seconds of the model replying."),
                actions: [])

        case .ready:
            // One action, and it is the way out. This step used to offer
            // none, and the setup screen was a dead end: the window swaps to
            // the status view only when the app becomes active again, so a
            // reader who finished setup and stayed in the app sat in front of
            // "live data is coming in" with nothing to press. Seen by the
            // owner on 21 August 2026, right after a release that had walked
            // through setup itself.
            return Script(
                headline: t("Live data is coming in."),
                explanation: t("If the widget is not on your desktop yet, right-click the desktop and choose Edit Widgets."),
                actions: [t("Show the status")])
        }
    }
}
