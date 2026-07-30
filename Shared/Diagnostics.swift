import Foundation
import os

public let ccwidgetParseLog = Logger(subsystem: "dev.illvminat.ccwidget", category: "parsing")
public let ccwidgetWidgetLog = Logger(subsystem: "dev.illvminat.ccwidget", category: "widget")
public let ccwidgetStoreLog = Logger(subsystem: "dev.illvminat.ccwidget", category: "store")

/// Одно поле, которое разбор отбросил.
public struct ParseIssue: Sendable, Equatable, Codable {
    public let field: String
    /// Сырое значение из JSON. `nil`, если его не удалось даже прочитать.
    public let rawValue: String?
    public let reason: String

    public var summary: String {
        "\(field) = \(rawValue ?? "?") — \(reason)"
    }
}

/// Копилка отброшенных полей на время одного разбора.
///
/// Мягкий разбор без неё — это молчаливая потеря данных: поле исчезает,
/// виджет рисует прочерк, а причину приходится искать вслепую.
public final class DiagnosticsCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ParseIssue] = []

    public init() {}

    public func record(field: String, raw: JSONValue?, error: Error) {
        let issue = ParseIssue(
            field: field,
            rawValue: raw?.compactDescription,
            reason: Self.reason(for: error)
        )
        lock.lock()
        storage.append(issue)
        lock.unlock()

        ccwidgetParseLog.error(
            """
            soft parse dropped field \(field, privacy: .public); \
            raw=\(issue.rawValue ?? "<unreadable>", privacy: .private); \
            reason=\(issue.reason, privacy: .public)
            """
        )
    }

    public var issues: [ParseIssue] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    private static func reason(for error: Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        switch error {
        case .typeMismatch(let type, let context):
            return "expected \(type), \(context.debugDescription)"
        case .valueNotFound(let type, _):
            return "no value for \(type)"
        case .keyNotFound(let key, _):
            return "missing key \(key.stringValue)"
        case .dataCorrupted(let context):
            return context.debugDescription
        @unknown default:
            return "\(error)"
        }
    }
}

extension CodingUserInfoKey {
    public static let ccwidgetDiagnostics = CodingUserInfoKey(
        rawValue: "dev.illvminat.ccwidget.diagnostics"
    )!
}

extension Decoder {
    public var ccwidgetDiagnostics: DiagnosticsCollector? {
        userInfo[.ccwidgetDiagnostics] as? DiagnosticsCollector
    }
}

// MARK: - Мягкий разбор

extension KeyedDecodingContainer {
    /// Разбирает поле, а при неудаче записывает его в лог и в диагностику
    /// и возвращает `nil`. Тихого проглатывания здесь не бывает.
    public func decodeSoft<T: Decodable>(
        _ type: T.Type,
        forKey key: Key,
        path: String,
        decoder: Decoder
    ) -> T? {
        guard contains(key) else { return nil }
        do {
            if try decodeNil(forKey: key) { return nil }
            return try decode(T.self, forKey: key)
        } catch {
            decoder.ccwidgetDiagnostics?.record(
                field: path,
                raw: try? decode(JSONValue.self, forKey: key),
                error: error
            )
            return nil
        }
    }

    /// То же для чисел, которые источник шлёт то целыми, то дробными.
    public func decodeSoftRoundedInt(
        forKey key: Key,
        path: String,
        decoder: Decoder
    ) -> Int? {
        guard contains(key) else { return nil }
        do {
            if try decodeNil(forKey: key) { return nil }
            return try decodeRoundedInt(forKey: key)
        } catch {
            decoder.ccwidgetDiagnostics?.record(
                field: path,
                raw: try? decode(JSONValue.self, forKey: key),
                error: error
            )
            return nil
        }
    }
}

// MARK: - Сырое значение

/// Минимальное представление любого узла JSON — нужно только чтобы
/// показать в логе, что именно не разобралось.
public enum JSONValue: Decodable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    /// Короткая запись для лога: длинные узлы обрезаются.
    public var compactDescription: String {
        let full = description
        return full.count > 200 ? String(full.prefix(200)) + "…" : full
    }

    private var description: String {
        switch self {
        case .null: return "null"
        case .bool(let v): return "\(v)"
        case .number(let v):
            return v == v.rounded() && abs(v) < 1e15
                ? String(Int(v))
                : "\(v)"
        case .string(let v): return "\"\(v)\""
        case .array(let items):
            return "[" + items.map(\.description).joined(separator: ", ") + "]"
        case .object(let fields):
            let body = fields.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.description)" }
                .joined(separator: ", ")
            return "{" + body + "}"
        }
    }
}
