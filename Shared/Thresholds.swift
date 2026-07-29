import SwiftUI

extension Level {
    /// Системные цвета — сами подстраиваются под тему и настройки доступности.
    /// Своей палитры не заводим, см. раздел 8 ТЗ.
    public var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .depleted: return .gray
        }
    }

    /// Цвет не должен быть единственным носителем смысла: форма глифа
    /// отличается на каждом уровне, а не только оттенок.
    public var symbolName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        case .depleted: return "xmark.circle.fill"
        }
    }
}

extension Freshness {
    /// Данные старше часа приглушаются: виджет, молча показывающий
    /// вчерашние проценты, хуже отсутствующего.
    public var isDimmed: Bool {
        switch self {
        case .fresh, .recent: return false
        case .stale, .abandoned: return true
        }
    }

    public var hidesNumbers: Bool {
        if case .abandoned = self { return true }
        return false
    }
}
