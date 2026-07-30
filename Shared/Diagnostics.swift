import Foundation
import os

public let ccwidgetParseLog = Logger(subsystem: "dev.illvminat.ccwidget", category: "parsing")
public let ccwidgetWidgetLog = Logger(subsystem: "dev.illvminat.ccwidget", category: "widget")
public let ccwidgetStoreLog = Logger(subsystem: "dev.illvminat.ccwidget", category: "store")

/// One field the parser dropped.
public struct ParseIssue: Sendable, Equatable, Codable {
    public let field: String
    /// The raw JSON value. `nil` when even that could not be read.
    public let rawValue: String?
    public let reason: String

    public var summary: String {
        "\(field) = \(rawValue ?? "?") — \(reason)"
    }
}

/// Collects dropped fields for the duration of one parse.
///
/// Soft parsing without this is silent data loss: the field disappears, the
/// widget draws a dash, and the cause has to be hunted for blind.
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

// MARK: - Soft parsing

extension KeyedDecodingContainer {
    /// Decodes a field; on failure records it in the log and in the
    /// diagnostics and returns `nil`. Nothing is swallowed quietly here.
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

    /// The same for numbers the source sends sometimes whole, sometimes
    /// fractional.
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

// MARK: - Raw value

/// A minimal representation of any JSON node. Its only job is to show in
/// the log what exactly failed to decode.
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

    /// Short form for the log: long nodes are truncated.
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
