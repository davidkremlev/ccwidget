import Foundation
import WidgetKit

/// Раздел 2.4: следит за снимком и дёргает перезагрузку виджета.
///
/// Две вещи, без которых наблюдатель работает ровно один раз:
///
/// 1. **Экспортёр пишет через `os.replace`** — inode подменяется, и источник,
///    привязанный к старому дескриптору, после первой же записи получает
///    `.rename`/`.delete` и больше не срабатывает. Поэтому дескриптор
///    переоткрывается, а на случай, когда файла ещё нет, отдельно
///    отслеживается каталог.
/// 2. **Бюджет WidgetKit** — статуслайн перерисовывается десятки раз в минуту,
///    и перезагружать виджет на каждую запись значит сжечь бюджет за час
///    (раздел 2.3). Перезагрузка идёт только если изменились сами цифры
///    и с прошлой перезагрузки прошло не меньше минуты.
@MainActor
final class SnapshotWatcher: ObservableObject {
    /// Минимум между перезагрузками. Меньше — расточительно, больше —
    /// заметная задержка между «поработал» и «виджет обновился».
    static let minimumReloadInterval: TimeInterval = 60
    /// Экспортёр пишет снимок и историю подряд; ждём, пока уляжется.
    static let debounce: TimeInterval = 2

    @Published private(set) var lastReload: Date?
    @Published private(set) var reloadCount = 0
    @Published private(set) var freshness: Freshness?
    @Published private(set) var isRunning = false

    private let store: SnapshotStore
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var directoryDescriptor: CInt = -1
    private var debounceTask: Task<Void, Never>?
    private var freshnessTimer: Timer?
    private var lastSignature: String?

    init(store: SnapshotStore = .default()) {
        self.store = store
    }

    // MARK: Запуск

    func start() {
        guard !isRunning else { return }
        isRunning = true

        watchDirectory()
        watchFile()
        startFreshnessTimer()

        // Перезагрузка при запуске приложения. Помимо очевидной пользы —
        // показать свежие цифры сразу — она страхует случай, когда виджет
        // простоял с устаревшим таймлайном, пока приложение было закрыто.
        reload(reason: "app launch", force: true)
    }

    func stop() {
        debounceTask?.cancel()
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        fileSource?.cancel()
        directorySource?.cancel()
        fileSource = nil
        directorySource = nil
        isRunning = false
    }

    // MARK: Наблюдение

    /// Каталог переживает подмену файла и ловит появление снимка,
    /// которого ещё нет.
    private func watchDirectory() {
        directorySource?.cancel()
        directoryDescriptor = open(store.containerURL.path, O_EVTONLY)
        guard directoryDescriptor >= 0 else {
            ccgaugeStoreLog.error(
                "watcher: cannot open directory \(self.store.containerURL.path, privacy: .public)"
            )
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        let descriptor = directoryDescriptor
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleCheck(reason: "directory changed") }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
    }

    /// Дескриптор самого файла: даёт события записи без перебора каталога.
    private func watchFile() {
        fileSource?.cancel()
        fileDescriptor = open(store.snapshotURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        let descriptor = fileDescriptor
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let data = source.data
                // Подмена inode: дескриптор больше не указывает на снимок.
                if data.contains(.delete) || data.contains(.rename) {
                    self.watchFile()
                }
                self.scheduleCheck(reason: "snapshot changed")
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileSource = source
    }

    private func scheduleCheck(reason: String) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.debounce))
            guard !Task.isCancelled else { return }
            if self.fileSource == nil { self.watchFile() }
            self.reload(reason: reason, force: false)
        }
    }

    // MARK: Перезагрузка

    /// Цифры, при изменении которых виджету действительно есть что показать.
    /// Возраст снимка в подпись не входит: он меняется каждую секунду,
    /// а отрисовывается предгенерированным таймлайном без нашей помощи.
    private func signature(of snapshot: Snapshot) -> String {
        [
            snapshot.limits.fiveHour?.usedPercentage.description ?? "-",
            snapshot.limits.sevenDay?.usedPercentage.description ?? "-",
            snapshot.context?.usedPercentage?.description ?? "-",
        ].joined(separator: "|")
    }

    private func reload(reason: String, force: Bool) {
        let snapshot = try? store.load()
        if let snapshot {
            freshness = Freshness(age: snapshot.age())
        }

        if !force {
            guard let snapshot else { return }
            let current = signature(of: snapshot)
            guard current != lastSignature else { return }

            if let lastReload, Date().timeIntervalSince(lastReload) < Self.minimumReloadInterval {
                // Цифры новые, но бюджет беречь надо: досрочно не дёргаем,
                // а ждём — следующая запись экспортёра нас разбудит.
                ccgaugeStoreLog.debug("watcher: reload deferred, budget window")
                return
            }
            lastSignature = current
        } else if let snapshot {
            lastSignature = signature(of: snapshot)
        }

        WidgetCenter.shared.reloadAllTimelines()
        lastReload = Date()
        reloadCount += 1
        ccgaugeStoreLog.notice(
            "widget reload #\(self.reloadCount, privacy: .public) (\(reason, privacy: .public))"
        )
    }

    // MARK: Свежесть

    /// Раз в минуту пересчитываем возраст. Переход через порог раздела 2.4
    /// меняет вид виджета, поэтому его надо показать, не дожидаясь новых
    /// данных, — иначе устаревание останется незамеченным.
    private func startFreshnessTimer() {
        freshnessTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshFreshness() }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
    }

    private func refreshFreshness() {
        guard let snapshot = try? store.load() else { return }
        let updated = Freshness(age: snapshot.age())
        guard updated != freshness else { return }
        ccgaugeStoreLog.notice(
            "freshness changed to \(String(describing: updated), privacy: .public)"
        )
        freshness = updated
        WidgetCenter.shared.reloadAllTimelines()
        lastReload = Date()
        reloadCount += 1
    }
}
