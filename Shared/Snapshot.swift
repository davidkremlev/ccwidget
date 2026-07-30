import Foundation

/// Версия схемы, которую понимает этот код.
/// Снимок с большей версией считается непригодным — рисовать по нему нельзя.
public let ccwidgetSupportedSchemaVersion = 1

public struct Snapshot: Codable, Sendable {
    public let schemaVersion: Int
    public let capturedAt: Date
    public let sessionId: String?
    public let claudeCodeVersion: String?
    public let model: ModelInfo?
    public let project: ProjectInfo?
    public let limits: Limits
    public let context: ContextInfo?
    public let cost: CostInfo?

    /// Поля, которые разбор отбросил. В норме пусто.
    /// Собирается при декодировании, в JSON не хранится.
    public let diagnostics: [ParseIssue]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, capturedAt, sessionId, claudeCodeVersion
        case model, project, limits, context, cost
    }

    public init(
        schemaVersion: Int,
        capturedAt: Date,
        sessionId: String?,
        claudeCodeVersion: String?,
        model: ModelInfo?,
        project: ProjectInfo?,
        limits: Limits,
        context: ContextInfo?,
        cost: CostInfo?,
        diagnostics: [ParseIssue] = []
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.sessionId = sessionId
        self.claudeCodeVersion = claudeCodeVersion
        self.model = model
        self.project = project
        self.limits = limits
        self.context = context
        self.cost = cost
        self.diagnostics = diagnostics
    }

    /// Обязательны только версия схемы и момент снимка — без них снимок
    /// бессмыслен. Всё остальное разбирается мягко и громко.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)

        sessionId = c.decodeSoft(String.self, forKey: .sessionId, path: "sessionId", decoder: decoder)
        claudeCodeVersion = c.decodeSoft(String.self, forKey: .claudeCodeVersion, path: "claudeCodeVersion", decoder: decoder)
        model = c.decodeSoft(ModelInfo.self, forKey: .model, path: "model", decoder: decoder)
        project = c.decodeSoft(ProjectInfo.self, forKey: .project, path: "project", decoder: decoder)
        context = c.decodeSoft(ContextInfo.self, forKey: .context, path: "context", decoder: decoder)
        cost = c.decodeSoft(CostInfo.self, forKey: .cost, path: "cost", decoder: decoder)
        limits = c.decodeSoft(Limits.self, forKey: .limits, path: "limits", decoder: decoder)
            ?? Limits(fiveHour: nil, sevenDay: nil)

        // Читается последним, когда вложенные разборы уже отчитались.
        diagnostics = decoder.ccwidgetDiagnostics?.issues ?? []
    }

    /// Возраст снимка на момент `now`.
    public func age(at now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(capturedAt)
    }
}

public struct ModelInfo: Codable, Sendable {
    public let id: String?
    public let displayName: String?
    public let effort: String?
}

public struct ProjectInfo: Codable, Sendable {
    public let name: String?
    // Полного пути здесь нет намеренно — см. раздел 4. Экспортёр его
    // не пишет, и поля в модели тоже нет: поле, всегда равное nil,
    // заставляет думать, что где-то оно всё-таки заполняется.
}

public struct Limits: Codable, Sendable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// Окно разбирается мягко: битое или неполное окно даёт `nil`,
    /// а не роняет разбор всего снимка. Отсутствие `rate_limits` —
    /// штатная ситуация в первые секунды сессии, и она молчит;
    /// а вот испорченное окно обязано попасть в лог и в диагностику.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = c.decodeSoft(LimitWindow.self, forKey: .fiveHour, path: "limits.fiveHour", decoder: decoder)
        sevenDay = c.decodeSoft(LimitWindow.self, forKey: .sevenDay, path: "limits.sevenDay", decoder: decoder)
    }
}

public struct LimitWindow: Codable, Sendable {
    public let usedPercentage: Int
    public let resetsAt: Date

    public init(usedPercentage: Int, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }

    /// Проценты приходят то целыми, то дробными — живой снимок принёс
    /// `28.000000000000004`. Строгий разбор терял всё окно целиком.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = try c.decodeRoundedInt(forKey: .usedPercentage)
        resetsAt = try c.decode(Date.self, forKey: .resetsAt)
    }

    public var remainingPercentage: Int { 100 - usedPercentage }

    /// Время до сброса окна.
    public func timeUntilReset(at now: Date = Date()) -> TimeInterval {
        resetsAt.timeIntervalSince(now)
    }
}

public struct ContextInfo: Codable, Sendable {
    public let usedPercentage: Int?
    public let totalInputTokens: Int?
    public let windowSize: Int?
    public let cacheHitRatio: Double?

    public init(usedPercentage: Int?, totalInputTokens: Int?, windowSize: Int?, cacheHitRatio: Double?) {
        self.usedPercentage = usedPercentage
        self.totalInputTokens = totalInputTokens
        self.windowSize = windowSize
        self.cacheHitRatio = cacheHitRatio
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = c.decodeSoftRoundedInt(forKey: .usedPercentage, path: "context.usedPercentage", decoder: decoder)
        totalInputTokens = c.decodeSoftRoundedInt(forKey: .totalInputTokens, path: "context.totalInputTokens", decoder: decoder)
        windowSize = c.decodeSoftRoundedInt(forKey: .windowSize, path: "context.windowSize", decoder: decoder)
        cacheHitRatio = c.decodeSoft(Double.self, forKey: .cacheHitRatio, path: "context.cacheHitRatio", decoder: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Число, которое источник может прислать и целым, и дробным.
    public func decodeRoundedInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        return Int(try decode(Double.self, forKey: key).rounded())
    }
}

public struct CostInfo: Codable, Sendable {
    public let sessionUsd: Double?
}

// MARK: - Пороги

public enum Level: String, Sendable {
    case healthy, warning, critical, depleted
}

extension LimitWindow {
    /// Уровень считается от **израсходованного**, как и у контекста:
    /// в одном столбце не должно стоять двух противоположных величин.
    ///
    /// Пороги — та же граница, что и раньше, переписанная от расхода:
    /// прежние «остаток > 50 / 20–50 / 1–20 / 0» дают в точности
    /// «расход < 50 / 50–80 / 81–99 / 100». Цвета не поменялись местами.
    public var level: Level {
        switch usedPercentage {
        case ..<50: return .healthy
        case 50...80: return .warning
        case 81...99: return .critical
        default: return .depleted
        }
    }
}

extension ContextInfo {
    /// Контекст опасен, когда наполняется: уровень считается от заполнения.
    public var level: Level? {
        guard let used = usedPercentage else { return nil }
        switch used {
        case ..<50: return .healthy
        case 50...70: return .warning
        default: return .critical
        }
    }
}
