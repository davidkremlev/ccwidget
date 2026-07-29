import Foundation

/// Установка экспортёра в конфигурацию Claude Code. Раздел 11.
enum Installer {
    enum Failure: LocalizedError {
        case widgetContainerMissing
        case templateMissing
        case settingsUnreadable(Error)
        case settingsMalformed
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .widgetContainerMissing:
                return String(localized: "Add the widget to your desktop first, then run setup again.")
            case .templateMissing:
                return String(localized: "The exporter template is missing from the app bundle.")
            case .settingsUnreadable(let error):
                return String(localized: "Could not read settings.json: \(error.localizedDescription)")
            case .settingsMalformed:
                return String(localized: "settings.json is not a JSON object.")
            case .writeFailed(let url, let error):
                return String(localized: "Could not write \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Что сейчас стоит в ключе `statusLine`.
    enum StatusLineState: Equatable {
        case absent
        case ours
        case foreign(String)
    }

    static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude")
    }
    static var settingsURL: URL { claudeDirectory.appending(path: "settings.json") }
    static var exporterURL: URL { claudeDirectory.appending(path: "ccgauge-export.py") }

    /// Шаг 1: Claude Code вообще установлен?
    static var isClaudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: settingsURL.path)
    }

    static func statusLineState() -> StatusLineState {
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String
        else { return .absent }
        return command == exporterURL.path ? .ours : .foreign(command)
    }

    // MARK: Установка

    /// Возвращает путь к резервной копии настроек, если она понадобилась.
    @discardableResult
    static func install() throws -> URL? {
        // Раздел 2.2: контейнер заводит система при первом запуске
        // расширения. Сами мы его не создаём — только проверяем.
        guard SnapshotStore.widgetContainerExists else {
            throw Failure.widgetContainerMissing
        }

        try writeExporter()
        let backup = try backupSettings()
        try writeStatusLine()
        return backup
    }

    private static func writeExporter() throws {
        guard let template = Bundle.main.url(
            forResource: "ccgauge-export.py", withExtension: "template"
        ), let body = try? String(contentsOf: template, encoding: .utf8) else {
            throw Failure.templateMissing
        }

        let rendered = body.replacingOccurrences(
            of: "__GROUP_DIR__",
            with: SnapshotStore.exchangeURL.path
        )
        do {
            try FileManager.default.createDirectory(
                at: claudeDirectory, withIntermediateDirectories: true
            )
            try rendered.write(to: exporterURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: exporterURL.path
            )
        } catch {
            throw Failure.writeFailed(exporterURL, error)
        }
    }

    /// Существующий `statusLine` затирать молча нельзя — копия делается
    /// всегда, когда файл вообще есть.
    private static func backupSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        // Имя файла, а не текст для человека: фиксированная локаль,
        // иначе в арабской или тайской локали получится нечитаемое имя.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        // Метка идёт с точностью до секунды, а установку можно запустить
        // дважды подряд. Копия не должна падать из-за совпадения имени —
        // тогда установка обрывается на ровном месте.
        let directory = settingsURL.deletingLastPathComponent()
        var backup = directory.appending(path: "settings.json.bak-\(stamp)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: backup.path) {
            backup = directory.appending(path: "settings.json.bak-\(stamp)-\(attempt)")
            attempt += 1
        }

        do {
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        } catch {
            throw Failure.writeFailed(backup, error)
        }
        return backup
    }

    private static func writeStatusLine() throws {
        var settings = readSettings() ?? [:]
        settings["statusLine"] = [
            "type": "command",
            "command": exporterURL.path,
            "padding": 0,
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            throw Failure.writeFailed(settingsURL, error)
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Ручная установка

    /// Для тех, кто не пускает приложение в свои конфиги.
    static func manualInstructions() -> String {
        """
        1. \(String(localized: "Render the exporter template:"))

        sed 's|__GROUP_DIR__|\(SnapshotStore.exchangeURL.path)|' \\
            ccgauge-export.py.template > ~/.claude/ccgauge-export.py
        chmod +x ~/.claude/ccgauge-export.py

        2. \(String(localized: "Add this to ~/.claude/settings.json:"))

        "statusLine": {
          "type": "command",
          "command": "\(exporterURL.path)",
          "padding": 0
        }
        """
    }
}
