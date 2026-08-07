import SwiftUI

// MARK: - What the estimate block says

/// The estimate block's whole output, as data rather than as a view.
///
/// It used to live inside `ForecastBlock` as a `@ViewBuilder` and two private
/// computed properties, which meant that of the five `Forecast.Outcome` cases
/// no check could tell `.notEnoughData` from `.flat`, or `.lastsUntilReset`
/// from `.runsOut`: the only things a check could ask — `hasRate` and
/// `showsProjection` — are equal within each of those pairs. Everything that
/// actually separated them was a `Text` nobody could read back.
///
/// That is the shape the `.runsOut` defect lived in. It was documented as
/// "exhaustion falls before the reset" and implemented as "falls inside the
/// horizon", and eighteen checks on the estimate missed it because all
/// eighteen tested the arithmetic and none could look at the verdict. A
/// property that cannot be asked stays wrong longest.
///
/// So the block is composed here and rendered there, the same way the spoken
/// row label is built by `gaugeAnnouncement`.
struct EstimateStatement: Equatable {
    /// How loudly the block speaks. A named level rather than a `Color`,
    /// because a colour cannot be asked what it means — `CLAUDE.md` lists
    /// exactly that as the sign of a value that will be wrong for a long time.
    enum Emphasis: String, Equatable {
        case plain
        case warning
        case alarm
    }

    let caption: String
    let emphasis: Emphasis
    /// Whether the chart is drawn at all.
    let drawsChart: Bool
    /// Whether the dashed projection is drawn over it.
    let drawsProjection: Bool
}

extension EstimateStatement.Emphasis {
    var color: Color {
        switch self {
        case .plain: return .secondary
        case .warning: return .yellow
        case .alarm: return .red
        }
    }
}

extension Forecast.Outcome {
    /// Section 7: red means the quota does not last, yellow means it does,
    /// and everything without a date is said quietly.
    var emphasis: EstimateStatement.Emphasis {
        switch self {
        case .runsOut: return .alarm
        case .lastsUntilReset: return .warning
        case .rateOnly, .flat, .notEnoughData: return .plain
        }
    }
}

/// The locale is a parameter for the same reason the rate's and the reset
/// moment's are: a view rendering against `.environment(\.locale, …)` and a
/// string formatted against the process locale disagree with each other, and a
/// baseline taken on one machine then fails on another.
func estimateStatement(_ forecast: Forecast,
                       locale: Locale = .autoupdatingCurrent) -> EstimateStatement {
    func localized(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = locale
        return String(localized: copy)
    }

    let caption: String
    switch forecast.outcome {
    case .notEnoughData:
        caption = localized(LocalizedStringResource("Not enough data yet"))
    case .flat:
        caption = localized(LocalizedStringResource("Usage is flat"))
    case .rateOnly:
        // A rate with no date: the speed is measured, the horizon did not
        // reach far enough to name one.
        caption = localized(LocalizedStringResource("Rate only — too little history for a date"))
    case .lastsUntilReset:
        caption = localized(LocalizedStringResource("Lasts until reset"))
    case .runsOut(let date):
        // The tilde is mandatory: this is an estimate, not a timetable.
        let moment = CCWidgetFormat.resetMoment(date, locale: locale)
        caption = localized(LocalizedStringResource("Runs out ~\(moment)"))
    }

    // With "not enough data" the chart is not drawn at all. The axis stretches
    // to the reset, which can be six days out, so a couple of points occupy a
    // few percent of the width: a stub on the left, indistinguishable from a
    // drawing artifact. The caption says enough on its own.
    let drawsChart: Bool
    if case .notEnoughData = forecast.outcome {
        drawsChart = false
    } else {
        drawsChart = forecast.points.count >= 2
    }

    return EstimateStatement(caption: caption,
                             emphasis: forecast.outcome.emphasis,
                             drawsChart: drawsChart,
                             drawsProjection: forecast.showsProjection)
}

/// Accumulated weekly consumption with a dashed projection line. Section 7:
/// yellow means the quota lasts to the reset, red means it does not.
struct ForecastChart: View {
    let forecast: Forecast
    let window: LimitWindow

    /// For the spoken description below: the same environment locale the
    /// block's own captions format against, so what is heard and what is drawn
    /// cannot come from two different locales.
    @Environment(\.locale) private var locale

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
        .accessibilityLabel(Text(verbatim: chartAnnouncement(forecast, window: window, locale: locale)))
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

    private var tint: Color { forecast.outcome.emphasis.color }
}

// MARK: - The estimate block

/// What VoiceOver should say for the estimate chart, in one piece.
///
/// The chart used to be `accessibilityHidden(true)`. Hiding is for decoration:
/// Apple's VoiceOver guidance asks for infographics to carry a concise
/// description of what they convey, and excludes only images that convey
/// nothing. The large tile is the only size that draws the estimate, so a
/// listener had the verdict beneath the chart and no idea what the picture
/// above it showed.
///
/// The verdict itself is not repeated here — it is a `Text` of its own right
/// below, and VoiceOver reads it. What the picture adds is the shape: how much
/// of the week is already spent, and how fast it is going.
///
/// A `String` and not a `Text`, for the same reason `gaugeAnnouncement` is:
/// a spoken form that cannot be read back is one nobody can check, and this
/// project has already shipped a backwards announcement that survived exactly
/// that way.
func chartAnnouncement(_ forecast: Forecast,
                       window: LimitWindow,
                       locale: Locale = .autoupdatingCurrent) -> String {
    func localized(_ resource: LocalizedStringResource) -> String {
        var copy = resource
        copy.locale = locale
        return String(localized: copy)
    }

    let name = localized(LocalizedStringResource("Week usage chart"))
    let used = Double(window.usedPercentage) / 100
    let value = used.formatted(.percent.locale(locale))

    guard forecast.hasRate, let rate = forecast.percentPerHour else {
        return [name, value].joined(separator: ", ")
    }
    return [name, value, rateCaption(rate, locale: locale)].joined(separator: ", ")
}

/// "0.7 %/h". The unit goes through the catalog like every other unit, and the
/// number through the environment's locale — the same pair the block prints on
/// screen, so the spoken rate and the drawn rate cannot drift apart.
func rateCaption(_ rate: Double, locale: Locale) -> String {
    let number = rate.formatted(.number.precision(.fractionLength(1)).locale(locale))
    var resource = LocalizedStringResource("\(number) %/h",
                                           comment: "Usage rate: a number followed by percent per hour")
    resource.locale = locale
    return String(localized: resource)
}

struct ForecastBlock: View {
    let forecast: Forecast
    let window: LimitWindow

    /// `.formatted()` reaches for the process locale, which the environment's
    /// locale is not obliged to match — and a baseline rendered on a Russian
    /// machine then says "0,4" where an American one says "0.4". Taking it
    /// from the environment is both the SwiftUI-native source and the one a
    /// check can set.
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // "Estimate", not "Forecast": the word must promise exactly
                // as much as the method delivers.
                Text("Estimate")
                    .font(.caption.weight(.medium))
                Spacer(minLength: 4)
                if forecast.hasRate, let rate = forecast.percentPerHour {
                    Text(verbatim: rateCaption(rate, locale: locale))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if statement.drawsChart {
                ForecastChart(forecast: forecast, window: window)
                    .frame(height: 30)
            }

            Text(verbatim: statement.caption)
                .font(.caption2)
                .foregroundStyle(statement.emphasis.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var statement: EstimateStatement {
        estimateStatement(forecast, locale: locale)
    }

    /// "0.7 %/h". The unit goes through the catalog like everything else: an
    /// hour is not "h" in most of the six languages, and a caption that is
    /// half translated reads worse than one that is not translated at all.
}
