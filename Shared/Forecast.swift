import Foundation

/// Оценка исчерпания недельной квоты. Раздел 7.
///
/// Именно оценка, а не предсказание, и в интерфейсе она так и называется.
/// Врать хуже, чем молчать, но молчать там, где есть что измерить, — тоже
/// плохо: у измерения и у экстраполяции разная цена ошибки, и они разделены.
public struct Forecast: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Точек мало, разброс узкий или линия не описывает данные.
        case notEnoughData
        /// Наклон не положительный — расход стоит.
        case flat
        /// Темп измерен, но до конца окна дальше, чем позволяет база.
        /// Показываем скорость без даты: скорость — измерение,
        /// дата была бы догадкой.
        case rateOnly
        /// Исчерпание позже сброса, и сам сброс в пределах горизонта.
        case lastsUntilReset
        /// Исчерпание раньше сброса и в пределах горизонта.
        case runsOut(at: Date)
    }

    public let outcome: Outcome
    /// Точки текущего окна, по которым считали. Ими же рисуется график.
    public let points: [HistoryEntry]
    /// Процентов в секунду. `nil`, когда регрессию не строили.
    public let slope: Double?
    /// Момент достижения 100% — даже когда показывать его нельзя.
    public let exhaustionAt: Date?
    /// Доля объяснённой дисперсии. `nil`, когда регрессию не строили.
    public let fitQuality: Double?
    /// Длина базы наблюдений.
    public let observationSpan: TimeInterval

    // MARK: Пороги достоверности

    /// При дедупликации раз в десять минут десять точек означают, что они
    /// не из одной вспышки активности.
    public static let minimumPoints = 10

    /// Два часа. Полчаса давали экстраполяцию в триста раз дальше базы.
    public static let minimumSpan: TimeInterval = 2 * 3600

    /// Ниже этого линия не описывает данные, и уверенная дата вводит
    /// в заблуждение сильнее, чем прочерк.
    public static let minimumFitQuality = 0.7

    /// Дата называется, только если до неё не дальше десяти длин базы.
    /// Два часа наблюдений дают горизонт в двадцать часов, не в неделю.
    public static let horizonMultiplier: Double = 10

    /// Период полуспада веса: вчерашний марафон не должен портить
    /// сегодняшнюю оценку, но и обнулять историю нельзя.
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

        func giveUp(_ span: TimeInterval = 0) -> Forecast {
            Forecast(outcome: .notEnoughData, points: points, slope: nil,
                     exhaustionAt: nil, fitQuality: nil, observationSpan: span)
        }

        // 2. Мало точек или узкая база — считать нечего.
        guard points.count >= minimumPoints,
              let first = points.first,
              let last = points.last
        else { return giveUp() }

        let span = last.time.timeIntervalSince(first.time)
        guard span >= minimumSpan else { return giveUp(span) }

        // Плато определяем по целым процентам, а не по дисперсии: при
        // одинаковых значениях средневзвешенное выходит на волос мимо,
        // дисперсия получается микроскопически положительной, наклон —
        // микроскопически ненулевым, и случай уезжал в «данных мало».
        let values = points.map(\.sevenDayUsed)
        guard let lowest = values.min(), let highest = values.max(), highest > lowest else {
            return Forecast(outcome: .flat, points: points, slope: 0,
                            exhaustionAt: nil, fitQuality: nil, observationSpan: span)
        }

        // 3. Взвешенная регрессия наименьших квадратов.
        let origin = first.time
        func weight(_ point: HistoryEntry) -> Double {
            pow(0.5, last.time.timeIntervalSince(point.time) / weightHalfLife)
        }

        var sumW = 0.0, sumWX = 0.0, sumWY = 0.0
        for p in points {
            let w = weight(p)
            sumW += w
            sumWX += w * p.time.timeIntervalSince(origin)
            sumWY += w * Double(p.sevenDayUsed)
        }
        guard sumW > 0 else { return giveUp(span) }
        let meanX = sumWX / sumW
        let meanY = sumWY / sumW

        var sxy = 0.0, sxx = 0.0
        for p in points {
            let w = weight(p)
            let dx = p.time.timeIntervalSince(origin) - meanX
            sxy += w * dx * (Double(p.sevenDayUsed) - meanY)
            sxx += w * dx * dx
        }
        guard sxx > 0 else {
            return Forecast(outcome: .flat, points: points, slope: 0,
                            exhaustionAt: nil, fitQuality: nil, observationSpan: span)
        }

        let slope = sxy / sxx
        let intercept = meanY - slope * meanX

        // 4. Насколько линия вообще описывает данные.
        var ssResidual = 0.0, ssTotal = 0.0
        for p in points {
            let w = weight(p)
            let x = p.time.timeIntervalSince(origin)
            let y = Double(p.sevenDayUsed)
            let predicted = intercept + slope * x
            ssResidual += w * (y - predicted) * (y - predicted)
            ssTotal += w * (y - meanY) * (y - meanY)
        }
        let quality = ssTotal > 0 ? max(0, 1 - ssResidual / ssTotal) : 0

        // 5. Расход стоит — оценивать нечего.
        guard slope > 0 else {
            return Forecast(outcome: .flat, points: points, slope: slope,
                            exhaustionAt: nil, fitQuality: quality, observationSpan: span)
        }

        // 6. Линия не описывает данные — молчим. Но наклон и R² сохраняем:
        //    иначе отладочная утилита не покажет, из-за чего именно отказ,
        //    и «данных мало» станет неотличимо от «линия кривая».
        guard quality >= minimumFitQuality else {
            return Forecast(outcome: .notEnoughData, points: points, slope: slope,
                            exhaustionAt: nil, fitQuality: quality, observationSpan: span)
        }

        // 7. Экстраполяция до 100%.
        let secondsTo100 = (100 - intercept) / slope
        let exhaustion = origin.addingTimeInterval(max(secondsTo100, 0))

        // 8. Горизонт. Дальше десяти длин базы утверждать нельзя ничего —
        //    ни даты исчерпания, ни того, что квоты хватит до сброса.
        //    Второе — такая же экстраполяция, как и первое.
        let maxHorizon = span * horizonMultiplier
        let toExhaustion = exhaustion.timeIntervalSince(last.time)
        let toReset = window.resetsAt.timeIntervalSince(last.time)

        let outcome: Outcome
        if toExhaustion <= maxHorizon {
            outcome = .runsOut(at: max(exhaustion, now))
        } else if toReset <= maxHorizon {
            // Исчерпание за горизонтом, а сброс внутри — значит сброс
            // наступит раньше, и это утверждение база выдерживает.
            outcome = .lastsUntilReset
        } else {
            outcome = .rateOnly
        }

        return Forecast(outcome: outcome, points: points, slope: slope,
                        exhaustionAt: exhaustion, fitQuality: quality,
                        observationSpan: span)
    }

    /// Расход в процентах за час — измерение, а не экстраполяция.
    /// Честно при любой длине базы, поэтому показывается и тогда,
    /// когда даты назвать нельзя.
    public var percentPerHour: Double? {
        slope.map { $0 * 3600 }
    }

    /// Есть ли что показывать в виде скорости.
    public var hasRate: Bool {
        switch outcome {
        case .rateOnly, .lastsUntilReset, .runsOut: return (percentPerHour ?? 0) > 0
        case .flat, .notEnoughData: return false
        }
    }

    /// Рисовать ли пунктир прогноза. При `.rateOnly` — нет: линия до ста
    /// процентов и есть та самая неназванная дата, только нарисованная.
    public var showsProjection: Bool {
        if case .runsOut = outcome { return true }
        if case .lastsUntilReset = outcome { return true }
        return false
    }
}
