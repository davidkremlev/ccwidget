import SwiftUI

extension Level {
    /// System colours adapt to light and dark and to the accessibility
    /// settings on their own. No custom palette — see section 8.
    public var color: Color {
        switch self {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .depleted: return .gray
        }
    }

    /// Colour must not be the only carrier of meaning: the glyph's shape
    /// differs at every level, not just its tint.
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
    /// Anything older than an hour is dimmed. A widget that quietly shows
    /// yesterday's percentages is worse than no widget at all.
    public var isDimmed: Bool {
        switch self {
        case .fresh: return false
        case .stale, .abandoned: return true
        }
    }

    public var hidesNumbers: Bool {
        if case .abandoned = self { return true }
        return false
    }
}
