import SwiftUI

/// Accumulated weekly consumption with a dashed projection line. Section 7:
/// yellow means the quota lasts to the reset, red means it does not.
struct ForecastChart: View {
    let forecast: Forecast
    let window: LimitWindow

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // The 100% ceiling: without it there is no telling where the
                // line is heading.
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

    // MARK: Geometry

    /// The time axis runs to the reset, which makes it obvious at a glance
    /// whether consumption fits inside the window or hits the ceiling first.
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

        // The dashes run either to the ceiling or to the right edge,
        // whichever comes first.
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

// MARK: - The estimate block

struct ForecastBlock: View {
    let forecast: Forecast
    let window: LimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // "Estimate", not "Forecast": the word must promise exactly
                // as much as the method delivers.
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

    /// With "not enough data" the chart is not drawn at all.
    ///
    /// The axis stretches to the reset, which can be six days out, so a couple
    /// of points occupy a few percent of the width. The result is a stub on
    /// the left, indistinguishable from a drawing artifact: it says nothing
    /// and reads as broken. The "Not enough data yet" caption is enough.
    private var hasChart: Bool {
        if case .notEnoughData = forecast.outcome { return false }
        return forecast.points.count >= 2
    }

    /// "0.7 %/h". The unit goes through the catalog like everything else: an
    /// hour is not "h" in most of the six languages, and a caption that is
    /// half translated reads worse than one that is not translated at all.
    private func rateCaption(_ rate: Double) -> String {
        let number = rate.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(number) %/h",
                      comment: "Usage rate: a number followed by percent per hour")
    }

    @ViewBuilder
    private var caption: some View {
        switch forecast.outcome {
        case .notEnoughData:
            Text("Not enough data yet")
        case .flat:
            Text("Usage is flat")
        case .rateOnly:
            // A rate with no date: the speed is measured, the horizon did not
            // reach far enough to name one.
            Text("Rate only — too little history for a date")
        case .lastsUntilReset:
            Text("Lasts until reset")
        case .runsOut(let date):
            // The tilde is mandatory: this is an estimate, not a timetable.
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
