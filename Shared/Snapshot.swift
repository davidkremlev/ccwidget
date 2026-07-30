import Foundation

/// The schema version this code understands. A snapshot with a higher
/// version is unusable — drawing from it would be guesswork.
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

    /// Fields the parser dropped. Empty in the normal case. Collected while
    /// decoding; never stored in the JSON itself.
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

    /// Only the schema version and the capture moment are required — without
    /// them a snapshot means nothing. Everything else is parsed softly, and
    /// loudly.
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

        // Read last, once the nested decoders have reported in.
        diagnostics = decoder.ccwidgetDiagnostics?.issues ?? []
    }

    /// How old the snapshot is at `now`.
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
    // The full path is deliberately absent — see section 4. The exporter
    // does not write it, and there is no field for it here either: a field
    // that is always nil suggests something somewhere does fill it in.
}

public struct Limits: Codable, Sendable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// Each window is parsed softly: a broken or partial one yields `nil`
    /// instead of taking the whole snapshot down. A missing `rate_limits` is
    /// expected in the first seconds of a session and stays silent; a
    /// corrupted window, on the other hand, must reach the log and the
    /// diagnostics.
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

    /// Percentages arrive whole or fractional — a live snapshot carried
    /// `28.000000000000004`. Strict decoding lost the entire window over it.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usedPercentage = try c.decodeRoundedInt(forKey: .usedPercentage)
        resetsAt = try c.decode(Date.self, forKey: .resetsAt)
    }

    public var remainingPercentage: Int { 100 - usedPercentage }

    /// Time left until the window resets.
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
    /// A number the source may send either whole or fractional.
    public func decodeRoundedInt(forKey key: Key) throws -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        return Int(try decode(Double.self, forKey: key).rounded())
    }
}

public struct CostInfo: Codable, Sendable {
    public let sessionUsd: Double?
}

// MARK: - Levels

public enum Level: String, Sendable {
    case healthy, warning, critical, depleted
}

extension LimitWindow {
    /// The level follows **consumption**, exactly as the context's does: one
    /// column must never hold two opposite quantities.
    ///
    /// The thresholds are the same boundaries as before, rewritten in terms of
    /// consumption: the old "remaining > 50 / 20-50 / 1-20 / 0" maps precisely
    /// onto "used < 50 / 50-80 / 81-99 / 100". No colour changed places.
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
    /// Context is dangerous as it fills, so its level follows how full it is.
    public var level: Level? {
        guard let used = usedPercentage else { return nil }
        switch used {
        case ..<50: return .healthy
        case 50...70: return .warning
        default: return .critical
        }
    }
}
