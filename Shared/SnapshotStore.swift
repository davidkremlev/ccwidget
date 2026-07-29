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
            return "Каталог обмена недоступен"
        case .fileMissing(let url):
            return "Снимок не найден: \(url.path)"
        case .unreadable(let url, let error):
            return "Не удалось прочитать \(url.path): \(error)"
        case .malformed(let error):
            return "Снимок повреждён: \(error)"
        case .unsupportedSchema(let found, let supported):
            return "Схема снимка \(found) новее поддерживаемой \(supported)"
        }
    }
}

public struct SnapshotStore: Sendable {
    /// Обмен идёт через собственный контейнер расширения виджета — см. 2.2.
    /// App Group отвергнута: расширению в песочнице её контейнер при
    /// ad-hoc подписи не выдаётся.
    public static let widgetBundleIdentifier = "dev.illvminat.ccgauge.widget"
    public static let exchangeFolderName = "ccgauge"

    public let containerURL: URL

    public var snapshotURL: URL { containerURL.appending(path: "snapshot.json") }
    public var historyURL: URL { containerURL.appending(path: "history.jsonl") }

    public init(containerURL: URL) {
        self.containerURL = containerURL
    }

    /// Каталог обмена.
    ///
    /// Внутри песочницы домашний каталог процесса **и есть** его контейнер,
    /// поэтому расширение добирается до обменного каталога коротким путём,
    /// а всё, что снаружи, — длинным, через `~/Library/Containers`.
    /// Ветвление обязательно: сложить один путь с другим значит удвоить его.
    public static var exchangeURL: URL {
        if isSandboxed {
            return URL(filePath: NSHomeDirectory())
                .appending(path: "Library/Application Support/\(exchangeFolderName)")
        }
        return exchangeURL(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// То же от заданного корня. Раздел 5.2: код, работающий с путями
    /// пользователя, обязан принимать корень параметром — иначе его
    /// нельзя проверить, не тронув настоящий домашний каталог.
    public static func exchangeURL(home: URL) -> URL {
        widgetContainerURL(home: home)
            .appending(path: "Data/Library/Application Support/\(exchangeFolderName)")
    }

    /// Контейнер целиком, каким его видно снаружи песочницы.
    /// Создаёт его система при первом запуске расширения, создавать
    /// самостоятельно запрещено — см. 2.2.
    public static var widgetContainerURL: URL {
        widgetContainerURL(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public static func widgetContainerURL(home: URL) -> URL {
        home.appending(path: "Library/Containers/\(widgetBundleIdentifier)")
    }

    /// Система уже завела контейнер расширения? Если нет, виджет ни разу
    /// не запускался, и установщику нечего подставлять в шаблон.
    ///
    /// Проверяется `Data/Library/Application Support` — этот подкаталог
    /// создаёт система, и по нему видно, что контейнер настоящий.
    public static var widgetContainerExists: Bool {
        // Изнутри песочницы вопрос лишён смысла: мы уже в контейнере.
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
        ccgaugeStoreLog.debug(
            "exchange dir \(url.path, privacy: .public); sandboxed=\(isSandboxed, privacy: .public)"
        )
        return SnapshotStore(containerURL: url)
    }

    /// Внутри песочницы домашняя папка процесса подменена на контейнер.
    public static var isSandboxed: Bool {
        NSHomeDirectory().contains("/Library/Containers/")
    }

    /// Что процесс на самом деле видит в контейнере. Нужно, когда система
    /// контейнер выдала, а файл всё равно не открывается: без этого
    /// «нет доступа» и «нет файла» неотличимы.
    public func describeAccess() -> String {
        let fm = FileManager.default
        var parts: [String] = [
            "sandboxed=\(Self.isSandboxed)",
            "home=\(NSHomeDirectory())",
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

    /// Каждый разбор получает свою копилку: диагностика относится
    /// к конкретному снимку, а не накапливается за всё время работы.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.userInfo[.ccgaugeDiagnostics] = DiagnosticsCollector()
        return decoder
    }

    /// Читает и разбирает снимок. Снимок с неизвестной схемой отвергается —
    /// лучше прочерк, чем нарисованная чушь.
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
        guard snapshot.schemaVersion <= ccgaugeSupportedSchemaVersion else {
            throw SnapshotStoreError.unsupportedSchema(
                found: snapshot.schemaVersion,
                supported: ccgaugeSupportedSchemaVersion
            )
        }
        return snapshot
    }
}

// MARK: - Свежесть

public enum Freshness: Sendable {
    case fresh          // менее 5 минут
    case recent         // 5–60 минут
    case stale          // более 60 минут
    case abandoned      // более 24 часов

    public init(age: TimeInterval) {
        switch age {
        case ..<(5 * 60): self = .fresh
        case ..<(60 * 60): self = .recent
        case ..<(24 * 60 * 60): self = .stale
        default: self = .abandoned
        }
    }
}
