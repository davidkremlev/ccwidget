import SwiftUI

/// График накопленного расхода недели с пунктирной линией прогноза.
/// Раздел 7: жёлтая линия — хватит до сброса, красная — не хватит.
struct ForecastChart: View {
    let forecast: Forecast
    let window: LimitWindow

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Потолок в 100%: без него не видно, куда линия стремится.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: size.width, y: 0))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(.tertiary)

                if let history = historyPath(in: size) {
                    history.stroke(tint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                if forecast.showsProjection, let projection = projectionPath(in: size) {
                    projection.stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 3])
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Геометрия

    /// Ось времени тянется до сброса — так сразу видно, укладывается расход
    /// в окно или упирается в потолок раньше.
    private var axis: (start: Date, end: Date)? {
        guard let first = forecast.points.first else { return nil }
        let end = window.resetsAt
        guard end > first.time else { return nil }
        return (first.time, end)
    }

    private func x(_ date: Date, _ size: CGSize) -> CGFloat {
        guard let axis else { return 0 }
        let span = axis.end.timeIntervalSince(axis.start)
        let offset = date.timeIntervalSince(axis.start)
        return size.width * CGFloat(min(max(offset / span, 0), 1))
    }

    private func y(_ percent: Double, _ size: CGSize) -> CGFloat {
        size.height * CGFloat(1 - min(max(percent / 100, 0), 1))
    }

    private func historyPath(in size: CGSize) -> Path? {
        guard axis != nil, forecast.points.count >= 2 else { return nil }
        var path = Path()
        for (index, point) in forecast.points.enumerated() {
            let p = CGPoint(x: x(point.time, size), y: y(Double(point.sevenDayUsed), size))
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        return path
    }

    private func projectionPath(in size: CGSize) -> Path? {
        guard let axis,
              let last = forecast.points.last,
              let slope = forecast.slope,
              slope > 0
        else { return nil }

        // Пунктир идёт либо до потолка, либо до правого края — смотря
        // что случится раньше.
        let end = min(forecast.exhaustionAt ?? axis.end, axis.end)
        guard end > last.time else { return nil }

        let endPercent = Double(last.sevenDayUsed) + slope * end.timeIntervalSince(last.time)

        var path = Path()
        path.move(to: CGPoint(x: x(last.time, size), y: y(Double(last.sevenDayUsed), size)))
        path.addLine(to: CGPoint(x: x(end, size), y: y(endPercent, size)))
        return path
    }

    private var tint: Color {
        switch forecast.outcome {
        case .runsOut: return .red
        case .lastsUntilReset: return .yellow
        case .rateOnly, .flat, .notEnoughData: return .secondary
        }
    }
}

// MARK: - Блок прогноза целиком

struct ForecastBlock: View {
    let forecast: Forecast
    let window: LimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // «Estimate», не «Forecast»: слово должно обещать ровно
                // столько, сколько метод даёт.
                Text("Estimate")
                    .font(.caption.weight(.medium))
                Spacer(minLength: 4)
                if forecast.hasRate, let rate = forecast.percentPerHour {
                    Text(verbatim: rateCaption(rate))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if hasChart {
                ForecastChart(forecast: forecast, window: window)
                    .frame(height: 30)
            }

            caption
                .font(.caption2)
                .foregroundStyle(captionColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// При «данных мало» график не рисуется вовсе.
    ///
    /// Ось растянута до сброса — это может быть шесть дней вперёд, — и пара
    /// точек занимает считанные проценты ширины. Получается обрубок слева,
    /// неотличимый от артефакта отрисовки: он не сообщает ничего, но выглядит
    /// поломкой. Подписи «Not enough data yet» достаточно.
    private var hasChart: Bool {
        if case .notEnoughData = forecast.outcome { return false }
        return forecast.points.count >= 2
    }

    private func rateCaption(_ rate: Double) -> String {
        "\(rate.formatted(.number.precision(.fractionLength(1)))) %/h"
    }

    @ViewBuilder
    private var caption: some View {
        switch forecast.outcome {
        case .notEnoughData:
            Text("Not enough data yet")
        case .flat:
            Text("Usage is flat")
        case .rateOnly:
            // Темп без даты. Скорость измерена, горизонт до неё не дотянулся.
            Text("Rate only — too little history for a date")
        case .lastsUntilReset:
            Text("Lasts until reset")
        case .runsOut(let date):
            // Тильда обязательна: это оценка, а не расписание.
            Text("Runs out ~\(CCWidgetFormat.resetMoment(date))")
        }
    }

    private var captionColor: Color {
        switch forecast.outcome {
        case .runsOut: return .red
        case .lastsUntilReset: return .yellow
        case .rateOnly, .flat, .notEnoughData: return .secondary
        }
    }
}
