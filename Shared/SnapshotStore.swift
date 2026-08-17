import Foundation

public enum SnapshotStoreError: Error, CustomStringConvertible {
    case fileMissing(URL)
    case unreadable(URL, Error)
    case malformed(Error)
    case unsupportedSchema(found: Int, supported: Int)
    /// The file is larger than anything this exchange can legitimately hold.
    case tooLarge(URL, bytes: Int)

    public var description: String {
        switch self {
        case .fileMissing(let url):
            return "Snapshot not found: \(url.path)"
        case .unreadable(let url, let error):
            return "Could not read \(url.path): \(error)"
        case .malformed(let error):
            return "Snapshot is corrupted: \(error)"
        case .unsupportedSchema(let found, let supported):
            return "Snapshot schema \(found) is newer than the supported \(supported)"
        case .tooLarge(let url, let bytes):
            return "\(url.lastPathComponent) is \(bytes) bytes, past the \(SnapshotStore.maximumSnapshotBytes) this reads"
        }
    }
}

public struct SnapshotStore: Sendable {
    /// The largest `snapshot.json` this will read. See `load()`.
    public static let maximumSnapshotBytes = 4 * 1024 * 1024

    /// Exchange happens through the widget extension's own container — see
    /// section 2.2. An App Group was rejected: under ad-hoc signing the
    /// sandbox never grants the extension access to the group container.
    public static let widgetBundleIdentifier = "dev.illvminat.ccwidget.widget"
    public static let exchangeFolderName = "ccwidget"

    public let containerURL: URL

    public var snapshotURL: URL { containerURL.appending(path: "snapshot.json") }
    public var historyURL: URL { containerURL.appending(path: "history.jsonl") }

    /// Left behind by the exporter while it is declining to write, and deleted
    /// the moment it writes again. Section 3.
    ///
    /// Skipping the write is a fallback, and a silent fallback turns a defect
    /// into an absence of data. On a session start the skip is expected and
    /// lasts seconds; the case it exists for is the one nobody has seen —
    /// `rate_limits` gone mid-session and not coming back. The exporter would
    /// then fall quiet for good, the snapshot would age, and the symptom would
    /// be indistinguishable from Claude Code not running.
    public var skipNoticeURL: URL { containerURL.appending(path: "export-skipped.json") }

    /// Where the exporter records that the status line it chains stopped
    /// working. Section 11: installing this widget must not cost somebody their
    /// prompt, and the failure mode of keeping that promise is a prompt that
    /// went blank for a reason only this file knows.
    public var chainNoticeURL: URL { containerURL.appending(path: "chain-failed.json") }

    /// Why the chained status line last failed, and since when. `nil` when
    /// nothing is chained or it is working, which is almost always.
    public func loadChainNotice() -> ChainNotice? {
        guard let data = try? Data(contentsOf: chainNoticeURL) else { return nil }
        do {
            return try JSONDecoder().decode(ChainNotice.self, from: data)
        } catch {
            ccwidgetParseLog.error(
                "chain notice unreadable: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// When the exporter last started declining to write, and why. `nil` when
    /// it is writing normally, which is almost always.
    public func loadSkipNotice() -> SkipNotice? {
        guard let data = try? Data(contentsOf: skipNoticeURL) else { return nil }
        do {
            return try JSONDecoder().decode(SkipNotice.self, from: data)
        } catch {
            ccwidgetParseLog.error(
                "skip notice unreadable: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    /// The exchange directory.
    ///
    /// Inside the sandbox a process's home directory **is** its container, so
    /// the extension reaches the exchange directory by the short path while
    /// everything outside takes the long one through `~/Library/Containers`.
    /// The branch is mandatory: adding one path to the other doubles it.
    public static var exchangeURL: URL {
        if isSandboxed {
            return URL(filePath: NSHomeDirectory())
                .appending(path: "Library/Application Support/\(exchangeFolderName)")
        }
        return exchangeURL(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// The same from a given root. Section 5.2: code that touches the user's
    /// paths must take the root as a parameter — otherwise it cannot be
    /// tested without touching a real home directory.
    public static func exchangeURL(home: URL) -> URL {
        widgetContainerURL(home: home)
            .appending(path: "Data/Library/Application Support/\(exchangeFolderName)")
    }

    /// The whole container as seen from outside the sandbox. The system
    /// creates it when the extension first runs; creating it ourselves is
    /// forbidden — see section 2.2.
    public static var widgetContainerURL: URL {
        widgetContainerURL(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public static func widgetContainerURL(home: URL) -> URL {
        home.appending(path: "Library/Containers/\(widgetBundleIdentifier)")
    }

    /// Has the system created the extension's container yet? If not, the
    /// widget has never run and the installer has no path to substitute into
    /// the template.
    ///
    /// The check looks for `Data/Library/Application Support`: the system
    /// creates that subdirectory, so its presence means the container is
    /// genuine rather than something we made up.
    public static var widgetContainerExists: Bool {
        // From inside the sandbox the question is moot: we are already in it.
        if isSandboxed { return true }
        return widgetContainerExists(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public static func widgetContainerExists(home: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: widgetContainerURL(home: home)
                .appending(path: "Data/Library/Application Support").path,
            isDirectory: &isDirectory
        )
        return exists && isDirectory.boolValue
    }

    public static func `default`() -> SnapshotStore {
        let url = exchangeURL
        ccwidgetStoreLog.debug(
            "exchange dir \(url.path, privacy: .private); sandboxed=\(isSandboxed, privacy: .public)"
        )
        return SnapshotStore(containerURL: url)
    }

    /// Inside the sandbox the process's home directory is its container.
    public static var isSandboxed: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    /// What the process actually sees in the container. Needed when the
    /// system hands over the container and the file still will not open:
    /// without this, "permission denied" and "no such file" look the same.
    public func describeAccess() -> String {
        let fm = FileManager.default
        var parts: [String] = [
            "sandboxed=\(Self.isSandboxed)",
            "home=<private>",
            "dirExists=\(fm.fileExists(atPath: containerURL.path))",
            "fileExists=\(fm.fileExists(atPath: snapshotURL.path))",
            "readable=\(fm.isReadableFile(atPath: snapshotURL.path))",
        ]
        do {
            let names = try fm.contentsOfDirectory(atPath: containerURL.path)
            parts.append("listing=[\(names.sorted().joined(separator: ", "))]")
        } catch {
            parts.append("listing failed: \((error as NSError).domain)/\((error as NSError).code)")
        }
        return parts.joined(separator: "; ")
    }

    /// Every parse gets its own collector: diagnostics belong to one
    /// snapshot rather than piling up across the process's lifetime.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.userInfo[.ccwidgetDiagnostics] = DiagnosticsCollector()
        return decoder
    }

    /// Reads and parses the snapshot. One with an unknown schema is
    /// rejected — a dash beats drawing nonsense.
    public func load() throws -> Snapshot {
        let url = snapshotURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SnapshotStoreError.fileMissing(url)
        }
        // Read what the exchange can legitimately hold, and no more.
        //
        // The exporter caps its input at one mebibyte, and the exporter's own
        // comment records why: a gigabyte of input once landed in the snapshot
        // whole and killed the widget extension on read. That cap is on the
        // writing side only. Any other writer — a second tool, a future bug in
        // ours, any process running as this user — reproduces the crash, and a
        // widget that dies on every render shows a stale frame that looks
        // merely old. A reader with no limit is a defect this project has
        // already suffered once, from the other end.
        //
        // Four mebibytes: the largest snapshot ever observed is under four
        // kilobytes, so this is a thousandfold headroom and still three orders
        // of magnitude below the size that did the damage.
        let size = (try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))[.size] as? Int) ?? nil
        if let size, size > Self.maximumSnapshotBytes {
            throw SnapshotStoreError.tooLarge(url, bytes: size)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SnapshotStoreError.unreadable(url, error)
        }
        let snapshot: Snapshot
        do {
            snapshot = try Self.makeDecoder().decode(Snapshot.self, from: data)
        } catch {
            throw SnapshotStoreError.malformed(error)
        }
        guard snapshot.schemaVersion <= ccwidgetSupportedSchemaVersion else {
            throw SnapshotStoreError.unsupportedSchema(
                found: snapshot.schemaVersion,
                supported: ccwidgetSupportedSchemaVersion
            )
        }
        return snapshot
    }
}

/// Why the status line this one chains stopped working, and since when.
public struct ChainNotice: Decodable, Sendable {
    public let since: Date
    public let reason: String

    private enum CodingKeys: String, CodingKey { case since, reason }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        since = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .since))
        reason = try c.decode(String.self, forKey: .reason)
    }

    public func age(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(since))
    }
}

/// Why the exporter wrote nothing, and since when.
public struct SkipNotice: Decodable, Sendable {
    public let since: Date
    public let reason: String
    /// The session whose redraw first declined. A session start explains
    /// itself; the same session still silent an hour later does not.
    public let sessionId: String?

    private enum CodingKeys: String, CodingKey {
        case since, reason, sessionId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        since = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .since))
        reason = try c.decode(String.self, forKey: .reason)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
    }

    public func age(at now: Date = Date()) -> TimeInterval { now.timeIntervalSince(since) }
}

// MARK: - Freshness

/// How old the snapshot is, in as many levels as the widget has appearances —
/// three, and not one more.
///
/// There used to be four. `fresh` was under five minutes and `recent` was five
/// to sixty, and the pair drew identically: not dimmed, numbers shown. The
/// difference had a purpose while the caption said "just now" under five
/// minutes; when that wording went, the purpose went with it and the case
/// stayed. A distinction that produces no observable difference is a lie about
/// how complicated the thing is — it has to be maintained, it made the watcher
/// reload a timeline that would come back looking exactly the same, and it
/// left a reason in `SPEC` 2.3 that had quietly stopped being true.
///
/// `everyLevelLooksDifferent` holds the rule that replaced it: no two levels
/// may draw the same. Add a fourth and it fails until the fourth is visible.
public enum Freshness: Sendable {
    case fresh          // under an hour
    case stale          // an hour to a day
    case abandoned      // over a day

    public init(age: TimeInterval) {
        switch age {
        case ..<(60 * 60): self = .fresh
        case ..<(24 * 60 * 60): self = .stale
        default: self = .abandoned
        }
    }

    /// How every surface should ask. The moment is snapped to the start of its
    /// minute first, by `AgeClock`, for the same reason the age caption is:
    /// the window's clock and the widget's are quantised differently, and two
    /// surfaces landing either side of a threshold dim at different times off
    /// one file. That is the same defect as "42 seconds ago" beside "1 minute
    /// ago", told in colour instead of in words.
    ///
    /// Only the moment is snapped, not the age. The caption floors the age as
    /// well because it prints a number and a number must not claim precision
    /// it has not got; this prints nothing, so there is nothing to round and
    /// no reason to move a threshold by up to a minute.
    public init(of snapshot: Snapshot, at moment: Date) {
        self.init(age: AgeClock.anchor(moment).timeIntervalSince(snapshot.capturedAt))
    }
}
