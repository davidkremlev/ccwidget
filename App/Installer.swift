import Foundation

/// Установка экспортёра в конфигурацию Claude Code. Раздел 11.
///
/// Все пути приходят снаружи — см. раздел 5.2. Установщик, вычислявший
/// домашний каталог сам, невозможно проверить, не тронув настоящий конфиг;
/// проверено на себе.
struct Installer {
    let home: URL
    let exchangeDirectory: URL
    /// `nil` — шаблона нет, установка невозможна.
    let templateURL: URL?

    /// Боевая конфигурация: настоящий дом, настоящий контейнер, шаблон из бандла.
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
        case writeFailed(URL, Error)

        var errorDescription: String? {
            switch self {
            case .widgetContainerMissing:
                return String(localized: "Add the widget to your desktop first, then run setup again.")
            case .templateMissing:
                return String(localized: "The exporter template is missing from the app bundle.")
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

    /// Что установка сделала на самом деле.
    struct Report {
        let backup: URL?
        /// Ложь означает, что `settings.json` пересобран целиком.
        let editWasSurgical: Bool
    }

    // MARK: Пути

    var claudeDirectory: URL { home.appending(path: ".claude") }
    var settingsURL: URL { claudeDirectory.appending(path: "settings.json") }
    var exporterURL: URL { claudeDirectory.appending(path: "ccgauge-export.py") }

    /// Шаблон имени резервной копии — показывается до нажатия кнопки.
    var backupNamePattern: String { "settings.json.bak-YYYYMMDD-HHMMSS" }

    // MARK: Состояние

    var isClaudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: settingsURL.path)
    }

    /// Раздел 2.2: контейнер заводит система, сами мы его не создаём.
    var widgetContainerExists: Bool {
        SnapshotStore.widgetContainerExists(home: home)
    }

    func statusLineState() -> StatusLineState {
        guard let settings = readSettings(),
              let line = settings["statusLine"] as? [String: Any],
              let command = line["command"] as? String
        else { return .absent }
        return command == exporterURL.path ? .ours : .foreign(command)
    }

    // MARK: Установка

    @discardableResult
    func install() throws -> Report {
        guard widgetContainerExists else { throw Failure.widgetContainerMissing }

        try writeExporter()
        let backup = try backupSettings()
        let surgical = try writeStatusLine()
        return Report(backup: backup, editWasSurgical: surgical)
    }

    private func writeExporter() throws {
        guard let templateURL,
              let body = try? String(contentsOf: templateURL, encoding: .utf8)
        else { throw Failure.templateMissing }

        let rendered = body.replacingOccurrences(
            of: "__GROUP_DIR__", with: exchangeDirectory.path
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

    private func backupSettings() throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }

        // Имя файла, а не текст для человека: фиксированная локаль.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        // Метка идёт с точностью до секунды, а установку можно запустить
        // дважды подряд. Копия не должна падать из-за совпадения имени.
        var backup = claudeDirectory.appending(path: "settings.json.bak-\(stamp)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: backup.path) {
            backup = claudeDirectory.appending(path: "settings.json.bak-\(stamp)-\(attempt)")
            attempt += 1
        }

        do {
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        } catch {
            throw Failure.writeFailed(backup, error)
        }
        return backup
    }

    /// Возвращает `true`, если удалось обойтись точечной правкой.
    private func writeStatusLine() throws -> Bool {
        let original = try? String(contentsOf: settingsURL, encoding: .utf8)
        let value: [String: Any] = [
            "type": "command",
            "command": exporterURL.path,
            "padding": 0,
        ]

        let text: String
        let surgical: Bool
        switch SettingsEditor.setting("statusLine", to: value, in: original) {
        case .surgical(let edited): text = edited; surgical = true
        case .rewritten(let rebuilt): text = rebuilt; surgical = false
        }

        do {
            try FileManager.default.createDirectory(
                at: claudeDirectory, withIntermediateDirectories: true
            )
            try text.write(to: settingsURL, atomically: true, encoding: .utf8)
        } catch {
            throw Failure.writeFailed(settingsURL, error)
        }
        return surgical
    }

    private func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Ручная установка

    func manualInstructions() -> String {
        """
        1. \(String(localized: "Render the exporter template:"))

        sed 's|__GROUP_DIR__|\(exchangeDirectory.path)|' \\
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
