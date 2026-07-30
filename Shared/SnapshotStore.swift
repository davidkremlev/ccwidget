import Foundation

public enum SnapshotStoreError: Error, CustomStringConvertible {
    case containerUnavailable
    case fileMissing(URL)
    case unreadable(URL, Error)
    case malformed(Error)
    case unsupportedSchema(found: Int, supported: Int)

    public var description: String {
        switch self {
        case .containerUnavailable:
            return "The exchange directory is unavailable"
        case .fileMissing(let url):
            return "Snapshot not found: \(url.path)"
        case .unreadable(let url, let error):
            return "Could not read \(url.path): \(error)"
        case .malformed(let error):
            return "Snapshot is corrupted: \(error)"
        case .unsupportedSchema(let found, let supported):
            return "Snapshot schema \(found) is newer than the supported \(supported)"
        }
    }
}

public struct SnapshotStore: Sendable {
    /// Exchange happens through the widget extension's own container — see
    /// section 2.2. An App Group was rejected: under ad-hoc signing the
    /// sandbox never grants the extension access to the group container.
    public static let widgetBundleIdentifier = "dev.illvminat.ccwidget.widget"
    public static let exchangeFolderName = "ccwidget"

    public let containerURL: URL

    public var snapshotURL: URL { containerURL.appending(path: "snapshot.json") }
    public var historyURL: URL { containerURL.appending(path: "history.jsonl") }

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

// MARK: - Freshness

public enum Freshness: Sendable {
    case fresh          // under 5 minutes
    case recent         // 5 to 60 minutes
    case stale          // over an hour
    case abandoned      // over a day

    public init(age: TimeInterval) {
        switch age {
        case ..<(5 * 60): self = .fresh
        case ..<(60 * 60): self = .recent
        case ..<(24 * 60 * 60): self = .stale
        default: self = .abandoned
        }
    }
}
