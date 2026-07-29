import Foundation

/// Прогноз исчерпания недельной квоты. Раздел 7.
///
/// Врать хуже, чем молчать: при нехватке данных или при остановившемся
/// расходе прогноз не строится вовсе.
public struct Forecast: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Точек мало или они слишком кучно легли по времени.
        case notEnoughData
        /// Наклон не положительный — расход стоит.
        case flat
        /// Исчерпание позже сброса: хватит до сброса.
        case lastsUntilReset
        /// Исчерпание раньше сброса — с моментом.
        case runsOut(at: Date)
    }

    public let outcome: Outcome
    /// Точки текущего окна, по которым считали. Ими же рисуется график.
    public let points: [HistoryEntry]
    /// Процентов в секунду. `nil`, когда регрессию не строили.
    public let slope: Double?
    /// Момент достижения 100% — даже если он позже сброса.
    public let exhaustionAt: Date?

    // Раздел 7: пороги достоверности.
    public static let minimumPoints = 5
    public static let minimumSpan: TimeInterval = 30 * 60
    /// Период полуспада веса. Вчерашний марафон не должен портить
    /// сегодняшний прогноз, но и обнулять историю нельзя.
    public static let weightHalfLife: TimeInterval = 12 * 3600

    public static func make(
        history: [HistoryEntry],
        window: LimitWindow,
        now: Date = Date()
    ) -> Forecast {
        // 1. Только текущее окно: при сбросе процент падает скачком,
        //    и регрессия по смешанным окнам даст мусор.
        let points = history.filter { entry in
            guard let resets = entry.resetsAt else { return false }
            return abs(resets.timeIntervalSince(window.resetsAt)) < 1
        }

        // 2. Мало точек или узкий разброс — прогноза нет.
        guard points.count >= minimumPoints,
              let first = points.first,
              let last = points.last,
              last.time.timeIntervalSince(first.time) >= minimumSpan
        else {
            return Forecast(outcome: .notEnoughData, points: points, slope: nil, exhaustionAt: nil)
        }

        // 3. Взвешенная регрессия наименьших квадратов.
        let origin = first.time
        var sumW = 0.0, sumWX = 0.0, sumWY = 0.0
        for p in points {
            let age = last.time.timeIntervalSince(p.time)
            let w = pow(0.5, age / weightHalfLife)
            sumW += w
            sumWX += w * p.time.timeIntervalSince(origin)
            sumWY += w * Double(p.sevenDayUsed)
        }
        guard sumW > 0 else {
            return Forecast(outcome: .notEnoughData, points: points, slope: nil, exhaustionAt: nil)
        }
        let meanX = sumWX / sumW
        let meanY = sumWY / sumW

        var sxy = 0.0, sxx = 0.0
        for p in points {
            let age = last.time.timeIntervalSince(p.time)
            let w = pow(0.5, age / weightHalfLife)
            let dx = p.time.timeIntervalSince(origin) - meanX
            sxy += w * dx * (Double(p.sevenDayUsed) - meanY)
            sxx += w * dx * dx
        }
        guard sxx > 0 else {
            return Forecast(outcome: .flat, points: points, slope: 0, exhaustionAt: nil)
        }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        // 4. Расход стоит — прогноза нет.
        guard slope > 0 else {
            return Forecast(outcome: .flat, points: points, slope: slope, exhaustionAt: nil)
        }

        // 5. Экстраполяция до 100%.
        let secondsTo100 = (100 - intercept) / slope
        let exhaustion = origin.addingTimeInterval(max(secondsTo100, 0))

        // 6. Сравнение со сбросом.
        let outcome: Outcome = exhaustion > window.resetsAt
            ? .lastsUntilReset
            : .runsOut(at: max(exhaustion, now))

        return Forecast(outcome: outcome, points: points, slope: slope, exhaustionAt: exhaustion)
    }

    /// Расход в процентах за час — для подписи.
    public var percentPerHour: Double? {
        slope.map { $0 * 3600 }
    }
}
