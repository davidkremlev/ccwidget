import Foundation

/// Локализованное форматирование. Ручной склейки строк быть не должно —
/// см. раздел 10 ТЗ.
public enum CCWidgetFormat {
    /// «2 минуты назад». Локализовано из коробки.
    public static func relativeAge(of date: Date, at now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Обратный отсчёт до сброса окна. Две старшие единицы, сокращённо.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let style = Duration.UnitsFormatStyle(
            allowedUnits: [.days, .hours, .minutes],
            width: .abbreviated,
            maximumUnitCount: 2
        )
        return Duration.seconds(max(0, seconds)).formatted(style)
    }

    /// Момент сброса: «Wed 3:00». День недели без даты — сброс всегда близко.
    public static func resetMoment(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    public static func percent(_ value: Int) -> String {
        value.formatted(.percent)
    }

    /// Доля кеша: 0.9943 → «99%».
    public static func ratio(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    public static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// Компактные токены: 62777 → «62.8K», 1000000 → «1M».
    public static func tokens(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// Точные токены с разделителями разрядов — для большого размера,
    /// где место есть и округление только теряет информацию.
    public static func tokensExact(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}
