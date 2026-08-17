import Foundation

/// Which build of the app this is.
///
/// The window named the exporter's version, the snapshot's age and Claude Code's
/// version, and said nothing whatsoever about itself. On 17 August that cost an
/// afternoon twice over: the installed bundle reported `0.3.2` while carrying
/// work the `v0.3.2` tag does not contain, so "which build am I running" had to
/// be answered with `strings` on the binary and the modification date of the
/// executable — and the owner had asked exactly that question earlier the same
/// day about a file that was supposed to be inside it.
///
/// A version number alone cannot answer it. `MARKETING_VERSION` changes when
/// somebody decides to change it, which is once per release and never in
/// between, so every build made between two releases carries the same number
/// while containing different code. The commit is the part that identifies the
/// build, and it reaches the bundle through `CCWidgetCommit`, stamped by
/// `Scripts/release.sh` and empty in every other build.
///
/// Three cases rather than a string with holes in it, so that "there is no
/// commit" and "there is no version either" are answers a check can ask for
/// instead of shapes a reader has to recognise.
enum AppBuild: Equatable {
    /// A release: both the version and the commit that produced it.
    case stamped(version: String, commit: String)
    /// An ordinary build. Real version, no commit, and the row says so — a
    /// blank where the commit should be would read as a release whose stamp
    /// went missing.
    case unstamped(version: String)
    /// The bundle did not say. Reachable: `object(forInfoDictionaryKey:)`
    /// returns `nil` for a key that is not there, and a bundle can be edited
    /// after it is built.
    case unknown

    init(version: String?, commit: String?) {
        // Whitespace, because a build setting that is defined and empty arrives
        // as an empty string rather than as an absent key. Measured, not
        // assumed: an ordinary build leaves `CCWidgetCommit` in the plist with
        // an empty value, and a build passed `CCWIDGET_COMMIT=deadbee` leaves
        // `deadbee` — so the test for "no commit" has to be emptiness, and
        // `unknown` belongs to a bundle whose keys are gone rather than to any
        // build this project makes.
        let version = version?.trimmingCharacters(in: .whitespaces) ?? ""
        let commit = commit?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !version.isEmpty else { self = .unknown; return }
        self = commit.isEmpty ? .unstamped(version: version) : .stamped(version: version, commit: commit)
    }

    static var current: AppBuild {
        AppBuild(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                 commit: Bundle.main.object(forInfoDictionaryKey: "CCWidgetCommit") as? String)
    }

    func text(locale: Locale = .autoupdatingCurrent) -> String {
        func localized(_ resource: LocalizedStringResource) -> String {
            var copy = resource
            copy.locale = locale
            return String(localized: copy)
        }

        switch self {
        case .stamped(let version, let commit):
            // Interpolated rather than localized: a version and a short hash
            // are values, not words, and there is nothing here for a translator
            // to decide. The rule this does not break — section 10 — is about
            // gluing translated phrases together, which the case below does not
            // do either: it is one resource with the version inside it.
            return "\(version) (\(commit))"
        case .unstamped(let version):
            return localized(LocalizedStringResource("\(version) · not a release build"))
        case .unknown:
            return localized(LocalizedStringResource("unknown"))
        }
    }
}
