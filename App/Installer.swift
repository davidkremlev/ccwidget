import Foundation

/// Установка экспортёра в конфигурацию Claude Code. Раздел 11.
///
/// Все пути приходят снаружи — см. раздел 5.2.
struct Installer {
    let home: URL
    let exchangeDirectory: URL
    /// `nil` — шаблона нет, установка невозможна.
    let templateURL: URL?
    /// Кандидаты в интерпретаторы, в порядке предпочтения.
    var interpreterCandidates: [URL] = Installer.defaultInterpreters

    /// Системный Python идёт первым осознанно: `/usr/bin/python3`
    /// принадлежит root, а `/opt/homebrew/bin` — пользователю. Экспортёр
    /// исполняется десятки раз в минуту, и интерпретатор из каталога,
    /// доступного на запись кому угодно из-под этого же пользователя,
    /// расширяет поверхность без нужды.
    static let defaultInterpreters: [URL] = [
        URL(filePath: "/usr/bin/python3"),
        URL(filePath: "/opt/homebrew/bin/python3"),
        URL(filePath: "/usr/local/bin/python3"),
    ]

    static func live() -> Installer {
        Installer(
            home: FileManager.default.homeDirectoryForCurrentUser,
            exchangeDirectory: SnapshotStore.exchangeURL,
            templateURL: Bundle.main.url(forResource: "ccgauge-export.py", withExtension: "template")
        )
    }

    enum Failure: LocalizedError {
        case widgetContainerMissing
        case templateMissing
        case pythonMissing
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .widgetContainerMissing:
                return String(localized: "Add the widget to your desktop first, then run setup again.")
            case .templateMissing:
                return String(localized: "The exporter template is missing from the app bundle.")
            case .pythonMissing:
                return String(localized: "No working python3 was found. Install the Xcode Command Line Tools with: xcode-select --install")
            case .writeFailed(let url, let error):
                return String(localized: "Could not write \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    enum StatusLineState: Equatable {
        case absent
        case ours
        case foreign(String)
    }

    struct Report {
        let backup: URL?
        /// Ложь означает, что `settings.json` пересобран целиком.
        let editWasSurgical: Bool
        let interpreter: URL
    }

    /// Что установка сделает, до того как её запустят. Раздел 11 требует
    /// предупреждать заранее, а не отчитываться постфактум.
    struct Preflight {
        let widgetContainerExists: Bool
        let interpreter: URL?
        /// `settings.json` — символическая ссылка, и вот её цель.
        let settingsLinkTarget: URL?
        /// Ссылку удастся сохранить: цель доступна на запись.
        let canPreserveLink: Bool
        let settingsWritable: Bool

        var isReady: Bool {
            widgetContainerExists && interpreter != nil && settingsWritable
        }
    }

    // MARK: Пути

    var claudeDirectory: URL { home.appending(path: ".claude") }
    var settingsURL: URL { claudeDirectory.appending(path: "settings.json") }
    var exporterURL: URL { claudeDirectory.appending(path: "ccgauge-export.py") }

    var backupNamePattern: String { "settings.json.bak-YYYYMMDD-HHMMSS" }

    /// Куда на самом деле писать настройки.
    ///
    /// Если `~/.claude/settings.json` — ссылка в репозиторий dotfiles, писать
    /// надо по цели. Иначе атомарная запись подменит саму ссылку обычным
    /// файлом: связь с dotfiles молча рвётся, настоящий конфиг остаётся без
    /// `statusLine`, а причина неочевидна.
    var resolvedSettingsURL: URL {
        var url = settingsURL
        var hops = 0
        while hops < 8,
              let type = try? FileManager.default.attributesOfItem(
                atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType,
              type == .typeSymbolicLink,
              let destination = try? FileManager.default.destinationOfSymbolicLink(
                atPath: url.path(percentEncoded: false)) {
            let next = URL(filePath: destination, relativeTo: url.deletingLastPathComponent())
            url = next.standardizedFileURL
            hops += 1
        }
        return url
    }

    var settingsIsSymbolicLink: Bool {
        resolvedSettingsURL.path(percentEncoded: false) != settingsURL.path(percentEncoded: false)
    }

    // MARK: Состояние

    var isClaudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false))
    }

    var widgetContainerExists: Bool {
        SnapshotStore.widgetContainerExists(home: home)
    }

    func statusLineState() -> StatusLineState {
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String
        else { return .absent }
        return command == exporterURL.path(percentEncoded: false) ? .ours : .foreign(command)
    }

    func preflight() -> Preflight {
        let resolved = resolvedSettingsURL
        let isLink = settingsIsSymbolicLink
        let directory = resolved.deletingLastPathComponent()
        let fm = FileManager.default
        let targetExists = fm.fileExists(atPath: resolved.path(percentEncoded: false))
        // Атомарная запись создаёт временный файл рядом с целью, значит
        // нужен доступ на запись в каталог, а не только в файл.
        let writable = fm.isWritableFile(atPath: directory.path(percentEncoded: false))
            || (!targetExists && !fm.fileExists(atPath: directory.path(percentEncoded: false)))

        return Preflight(
            widgetContainerExists: widgetContainerExists,
            interpreter: findInterpreter(),
            settingsLinkTarget: isLink ? resolved : nil,
            canPreserveLink: !isLink || writable,
            settingsWritable: writable || !isClaudeCodePresent
        )
    }

    // MARK: Интерпретатор

    /// Первый кандидат, который действительно запускается и отвечает «3».
    ///
    /// Проверка обязательна: на чистой macOS `/usr/bin/python3` существует,
    /// но это заглушка, вызывающая предложение поставить Command Line Tools.
    /// Без проверки экспортёр молча не работал бы, а онбординг показывал бы
    /// бесконечное ожидание.
    func findInterpreter() -> URL? {
        for candidate in interpreterCandidates where
            FileManager.default.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
            if Self.reportsPython3(candidate) { return candidate }
        }
        return nil
    }

    private static func reportsPython3(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-c", "import sys; print(sys.version_info[0])"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Заглушка Command Line Tools интерактивна — ввод ей не даём.
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let data = try? pipe.fileHandleForReading.readToEnd(),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "3"
    }

    // MARK: Установка

    @discardableResult
    func install() throws -> Report {
        guard widgetContainerExists else { throw Failure.widgetContainerMissing }
        guard let interpreter = findInterpreter() else { throw Failure.pythonMissing }

        try writeExporter(interpreter: interpreter)
        let backup = try backupSettings()
        let surgical = try writeStatusLine()
        return Report(backup: backup, editWasSurgical: surgical, interpreter: interpreter)
    }

    private func writeExporter(interpreter: URL) throws {
        guard let templateURL,
              let body = try? String(contentsOf: templateURL, encoding: .utf8)
        else { throw Failure.templateMissing }

        var rendered = body
        // Голая замена внутри кавычек — сток для внедрения кода: путь
        // с кавычкой или переводом строки выходит за литерал, а файл
        // затем исполняется на каждую перерисовку. Подставляем готовый
        // литерал вместе с кавычками.
        rendered = rendered.replacingOccurrences(
            of: "\"__GROUP_DIR__\"",
            with: Self.pythonStringLiteral(exchangeDirectory.path(percentEncoded: false))
        )
        rendered = Self.replacingShebang(in: rendered, with: interpreter)

        do {
            try createClaudeDirectoryIfNeeded()
            try rendered.write(to: exporterURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: exporterURL.path(percentEncoded: false)
            )
        } catch {
            throw Failure.writeFailed(exporterURL, error)
        }
    }

    /// Экранирование по правилам JSON. Python принимает те же escape-последовательности,
    /// включая `\uXXXX`, поэтому результат — корректный литерал в обоих языках.
    static func pythonStringLiteral(_ value: String) -> String {
        // `.withoutEscapingSlashes` обязателен: по умолчанию слэши уходят
        // как `\/`, что для JSON законно, а для Python — нераспознанная
        // escape-последовательность и предупреждение на каждый запуск.
        guard let data = try? JSONSerialization.data(
                withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(text.dropFirst().dropLast())
    }

    static func replacingShebang(in body: String, with interpreter: URL) -> String {
        var lines = body.components(separatedBy: "\n")
        let shebang = "#!" + interpreter.path(percentEncoded: false)
        if let first = lines.first, first.hasPrefix("#!") {
            lines[0] = shebang
        } else {
            lines.insert(shebang, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// Каталог создаём закрытым. Права уже существующего не трогаем —
    /// он не наш.
    private func createClaudeDirectoryIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: claudeDirectory.path(percentEncoded: false)) else { return }
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Копия всегда обычный файл, даже если оригинал — ссылка: копия-ссылка
    /// указывает на файл, который мы вот-вот перезапишем, и восстанавливать
    /// из неё нечего.
    private func backupSettings() throws -> URL? {
        let source = resolvedSettingsURL
        guard let contents = try? Data(contentsOf: source) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        var backup = claudeDirectory.appending(path: "settings.json.bak-\(stamp)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: backup.path(percentEncoded: false)) {
            backup = claudeDirectory.appending(path: "settings.json.bak-\(stamp)-\(attempt)")
            attempt += 1
        }

        do {
            try createClaudeDirectoryIfNeeded()
            try contents.write(to: backup, options: .atomic)
        } catch {
            throw Failure.writeFailed(backup, error)
        }
        return backup
    }

    private func writeStatusLine() throws -> Bool {
        // Пишем по цели ссылки, а не по ней самой.
        let destination = resolvedSettingsURL
        let original = try? String(contentsOf: destination, encoding: .utf8)
        let value: [String: Any] = [
            "type": "command",
            "command": exporterURL.path(percentEncoded: false),
            "padding": 0,
        ]

        let text: String
        let surgical: Bool
        switch SettingsEditor.setting("statusLine", to: value, in: original) {
        case .surgical(let edited): text = edited; surgical = true
        case .rewritten(let rebuilt): text = rebuilt; surgical = false
        }

        do {
            try createClaudeDirectoryIfNeeded()
            try text.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw Failure.writeFailed(destination, error)
        }
        return surgical
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: resolvedSettingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Ручная установка

    /// Без `sed`: путь с символом `|` ломает разделитель, а с кавычкой —
    /// литерал в самом скрипте. Показываем готовую строку целиком.
    func manualInstructions() -> String {
        let interpreter = findInterpreter()?.path(percentEncoded: false) ?? "/usr/bin/python3"
        return """
        1. \(String(localized: "Copy the template to ~/.claude/ccgauge-export.py"))

        2. \(String(localized: "Replace its first line with:"))

        #!\(interpreter)

        3. \(String(localized: "Replace the GROUP_DIR line with exactly:"))

        GROUP_DIR = \(Self.pythonStringLiteral(exchangeDirectory.path(percentEncoded: false)))

        4. chmod +x ~/.claude/ccgauge-export.py

        5. \(String(localized: "Add this to ~/.claude/settings.json:"))

        "statusLine": {
          "type": "command",
          "command": \(Self.pythonStringLiteral(exporterURL.path(percentEncoded: false))),
          "padding": 0
        }
        """
    }
}
