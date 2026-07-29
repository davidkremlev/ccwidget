import SwiftUI
import WidgetKit

/// Одна измеряемая величина в виде, готовом к отрисовке.
/// Полоска всегда равна показанному числу — иначе взгляд ловит расхождение.
struct GaugeMetric {
    let fraction: Double
    let value: String
    let auxiliary: String?
    let level: Level
}

extension CCGaugeEntry {
    var isDimmed: Bool { freshness?.isDimmed ?? false }
    var hidesNumbers: Bool { freshness?.hidesNumbers ?? false }

    /// Все три строки показывают израсходованное — см. раздел 8.
    /// Полоска заполняется по мере расхода, как и у контекста,
    /// и совпадает с панелью Usage без вычитания из ста.
    func limitMetric(_ window: LimitWindow?) -> GaugeMetric? {
        guard !hidesNumbers, let window else { return nil }
        return GaugeMetric(
            fraction: Double(window.usedPercentage) / 100,
            value: CCGaugeFormat.percent(window.usedPercentage),
            auxiliary: CCGaugeFormat.countdown(window.timeUntilReset(at: date)),
            level: window.level
        )
    }

    /// Контекст и раньше показывал заполнение — трогать нечего.
    var contextMetric: GaugeMetric? {
        guard !hidesNumbers,
              let context = snapshot?.context,
              let used = context.usedPercentage,
              let level = context.level
        else { return nil }
        return GaugeMetric(
            fraction: Double(used) / 100,
            value: CCGaugeFormat.percent(used),
            auxiliary: context.totalInputTokens.map(CCGaugeFormat.tokens),
            level: level
        )
    }
}

// MARK: - Полоска

struct Bar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Шапка

/// В шапке только модель.
///
/// Имя проекта отсюда убрано намеренно: экспортёр глобальный, все сессии
/// пишут в один снимок, и проект относится к последней отрисовавшейся
/// сессии — а не к виджету целиком. В заголовке оно читалось как «этот
/// виджет про проект X», что неверно. Теперь оно стоит рядом со строкой
/// контекста, к которой действительно относится (раздел 13, вариант A).
struct WidgetHeader: View {
    let entry: CCGaugeEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.snapshot?.model.map(Self.caption) ?? "Gauge for Claude Code")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
        }
    }

    static func caption(_ model: ModelInfo) -> String {
        [model.displayName, model.effort].compactMap { $0 }.joined(separator: " · ")
    }
}

extension CCGaugeEntry {
    /// Имя проекта последней отрисовавшейся сессии.
    var projectName: String? { snapshot?.project?.name }
}

// MARK: - Компактная строка (средний размер)

struct GaugeRow: View {
    let caption: LocalizedStringKey
    /// `nil` — данных нет: прочерк вместо цифр, пустая полоска.
    let metric: GaugeMetric?
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 6) {
            LevelGlyph(level: metric?.level, dimmed: dimmed)

            Text(caption)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Bar(fraction: metric?.fraction ?? 0, tint: tint)

            Text(metric?.value ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .layoutPriority(2)

            if let auxiliary = metric?.auxiliary {
                Text(auxiliary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityValue(metric?.value ?? "no data")
    }

    private var tint: Color { metricTint(metric, dimmed: dimmed) }
}

// MARK: - Подробная строка (большой размер)

struct DetailGaugeRow: View {
    let caption: LocalizedStringKey
    let metric: GaugeMetric?
    let detail: String?
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                LevelGlyph(level: metric?.level, dimmed: dimmed)

                Text(caption)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(metric?.value ?? "—")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .layoutPriority(2)
            }

            Bar(fraction: metric?.fraction ?? 0, tint: metricTint(metric, dimmed: dimmed), height: 8)

            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption)
        .accessibilityValue(metric?.value ?? "no data")
    }
}

// MARK: - Мелочи

/// Цвет не единственный носитель смысла: форма глифа меняется вместе с уровнем.
struct LevelGlyph: View {
    let level: Level?
    let dimmed: Bool
    var font: Font = .caption2

    var body: some View {
        Image(systemName: level?.symbolName ?? "minus.circle")
            .font(font)
            .foregroundStyle(dimmed || level == nil ? Color.secondary : level!.color)
            .layoutPriority(1)
    }
}

func metricTint(_ metric: GaugeMetric?, dimmed: Bool) -> Color {
    guard let metric else { return .secondary }
    return dimmed ? .secondary : metric.level.color
}

/// Возраст снимка. Раздел 2.4: устаревшие данные обязаны выглядеть устаревшими,
/// поэтому после часа к возрасту добавляется явное слово.
struct AgeCaption: View {
    let entry: CCGaugeEntry

    var body: some View {
        if let captured = entry.snapshot?.capturedAt {
            let age = CCGaugeFormat.relativeAge(of: captured, at: entry.date)
            Text(entry.freshness?.isDimmed == true ? "outdated · \(age)" : "\(age)")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Одно окно для всех случаев, когда цифр показывать нельзя.
struct MessageView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    /// Возраст снимка, если он есть: в состоянии «заброшено» это
    /// единственное честное число на виджете.
    var age: String?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if !compact {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let age {
                Text(age)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MessageView {
    /// Снимка нет вообще — экспортёр ещё ни разу не отработал.
    static func noData(compact: Bool = false) -> MessageView {
        MessageView(
            title: "No data yet",
            message: "Launch Claude Code in the terminal and send a message.",
            compact: compact
        )
    }

    /// Снимок старше суток. Раздел 2.4: вместо цифр — приглашение.
    static func abandoned(entry: CCGaugeEntry, compact: Bool = false) -> MessageView {
        MessageView(
            title: "Data is stale",
            message: "Launch Claude Code in the terminal to refresh.",
            age: entry.snapshot.map { CCGaugeFormat.relativeAge(of: $0.capturedAt, at: entry.date) },
            compact: compact
        )
    }
}
