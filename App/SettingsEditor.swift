import Foundation

/// Surgical edits to `settings.json`.
///
/// `JSONSerialization` loses the indentation and the key order: someone who
/// keeps a tidy config ends up with a whole-file diff instead of one line.
/// So the key's value is patched directly in the text and every other byte
/// is left alone.
enum SettingsEditor {
    /// How the edit went. Onboarding has to say this before the button is
    /// pressed.
    enum Outcome {
        /// Only the intended key changed; the formatting survived.
        case surgical(String)
        /// The surgical route failed — the file was rebuilt, so key order
        /// and indentation are gone.
        case rewritten(String)
    }

    static func setting(
        _ key: String,
        to value: [String: Any],
        in original: String?
    ) -> Outcome {
        if let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let edited = surgicalEdit(original, key: key, value: value),
               isEquivalent(edited, to: original, key: key, value: value) {
                return .surgical(edited)
            }
        }
        return .rewritten(rewrite(original, key: key, value: value))
    }

    /// The outcome of removing a key.
    enum RemovalOutcome {
        case surgical(String)
        case rewritten(String)
        case absent
    }

    /// Removes a top-level key while preserving the formatting around it.
    ///
    /// Needed by the uninstaller: restoring `settings.json` from a backup is
    /// not an option, because other keys may have changed between install and
    /// removal and rolling the whole file back would take those edits away.
    static func removing(_ key: String, from original: String?) -> RemovalOutcome {
        guard let original,
              let data = original.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object[key] != nil
        else { return .absent }

        object.removeValue(forKey: key)

        if let edited = surgicalRemoval(original, key: key),
           let editedData = edited.data(using: .utf8),
           let parsed = (try? JSONSerialization.jsonObject(with: editedData)) as? [String: Any],
           NSDictionary(dictionary: parsed).isEqual(to: object) {
            return .surgical(edited)
        }

        let rebuilt = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return .rewritten(rebuilt + "\n")
    }

    private static func surgicalRemoval(_ text: String, key: String) -> String? {
        let chars = Array(text)
        guard let root = topLevelBraces(chars),
              let span = valueSpan(chars, of: key, in: root),
              let keyStart = keyStart(chars, of: key, in: root)
        else { return nil }

        // Swallow the comma on one side or the other, or a dangling one is
        // left behind.
        var from = keyStart
        var to = span.upperBound
        var cursor = to
        while cursor < root.close, chars[cursor].isWhitespace { cursor += 1 }
        if cursor < root.close, chars[cursor] == "," {
            to = cursor + 1
        } else {
            var back = from - 1
            while back > root.open, chars[back].isWhitespace { back -= 1 }
            if back > root.open, chars[back] == "," { from = back }
        }
        // Take the orphaned newline before the key with it.
        var lineStart = from
        while lineStart > root.open, chars[lineStart - 1] == " " || chars[lineStart - 1] == "\t" {
            lineStart -= 1
        }
        if lineStart > root.open, chars[lineStart - 1] == "\n" { lineStart -= 1 }

        return String(chars[..<lineStart]) + String(chars[to...])
    }

    private static func keyStart(
        _ chars: [Character], of key: String, in root: (open: Int, close: Int)
    ) -> Int? {
        var depth = 0
        var index = root.open
        while index < root.close {
            let ch = chars[index]
            if ch == "\"" {
                guard let end = stringEnd(chars, from: index) else { return nil }
                if depth == 1, String(chars[(index + 1)..<end]) == key { return index }
                index = end + 1
                continue
            }
            if ch == "{" || ch == "[" { depth += 1 }
            if ch == "}" || ch == "]" { depth -= 1 }
            index += 1
        }
        return nil
    }

    // MARK: Surgical edit

    private static func surgicalEdit(_ text: String, key: String, value: [String: Any]) -> String? {
        let chars = Array(text)
        guard let root = topLevelBraces(chars) else { return nil }
        let indent = detectIndent(chars, openBrace: root.open)
        guard let rendered = render(value, indent: indent, level: 1) else { return nil }

        if let span = valueSpan(chars, of: key, in: root) {
            // The key exists: replace only its value.
            return String(chars[..<span.lowerBound]) + rendered + String(chars[span.upperBound...])
        }

        // No such key: append before the closing brace, matching the indent.
        let isEmpty = chars[(root.open + 1)..<root.close]
            .allSatisfy { $0.isWhitespace }
        var insertion = ""
        if !isEmpty {
            guard let lastValueEnd = lastNonWhitespace(chars, before: root.close) else { return nil }
            insertion = ",\n\(indent)\"\(key)\": \(rendered)"
            let head = String(chars[...lastValueEnd])
            let tail = String(chars[(lastValueEnd + 1)...])
            return head + insertion + tail
        }
        insertion = "\n\(indent)\"\(key)\": \(rendered)\n"
        return String(chars[...root.open]) + insertion + String(chars[root.close...])
    }

    /// The bounds of the root object.
    private static func topLevelBraces(_ chars: [Character]) -> (open: Int, close: Int)? {
        var open: Int?
        var close: Int?
        var depth = 0
        var inString = false
        var escaped = false
        for (index, ch) in chars.enumerated() {
            if escaped { escaped = false; continue }
            if inString {
                if ch == "\\" { escaped = true } else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"": inString = true
            case "{", "[":
                if ch == "{" && depth == 0 && open == nil { open = index }
                depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 && ch == "}" { close = index }
            default: break
            }
        }
        guard let open, let close, open < close else { return nil }
        return (open, close)
    }

    /// The range of a top-level key's value. Keys of the same name at
    /// greater depth are ignored — otherwise the edit lands inside a nested
    /// object.
    private static func valueSpan(
        _ chars: [Character],
        of key: String,
        in root: (open: Int, close: Int)
    ) -> Range<Int>? {
        var depth = 0
        var index = root.open
        while index < root.close {
            let ch = chars[index]
            if ch == "\"" {
                guard let end = stringEnd(chars, from: index) else { return nil }
                if depth == 1, String(chars[(index + 1)..<end]) == key {
                    var cursor = end + 1
                    while cursor < root.close, chars[cursor].isWhitespace { cursor += 1 }
                    guard cursor < root.close, chars[cursor] == ":" else { index = end + 1; continue }
                    cursor += 1
                    while cursor < root.close, chars[cursor].isWhitespace { cursor += 1 }
                    guard let valueEnd = valueEnd(chars, from: cursor) else { return nil }
                    return cursor..<(valueEnd + 1)
                }
                index = end + 1
                continue
            }
            if ch == "{" || ch == "[" { depth += 1 }
            if ch == "}" || ch == "]" { depth -= 1 }
            index += 1
        }
        return nil
    }

    private static func stringEnd(_ chars: [Character], from start: Int) -> Int? {
        var index = start + 1
        while index < chars.count {
            if chars[index] == "\\" { index += 2; continue }
            if chars[index] == "\"" { return index }
            index += 1
        }
        return nil
    }

    /// The last index of the value that begins at `start`.
    private static func valueEnd(_ chars: [Character], from start: Int) -> Int? {
        switch chars[start] {
        case "\"": return stringEnd(chars, from: start)
        case "{", "[":
            var depth = 0
            var index = start
            while index < chars.count {
                let ch = chars[index]
                if ch == "\"" {
                    guard let end = stringEnd(chars, from: index) else { return nil }
                    index = end + 1
                    continue
                }
                if ch == "{" || ch == "[" { depth += 1 }
                if ch == "}" || ch == "]" {
                    depth -= 1
                    if depth == 0 { return index }
                }
                index += 1
            }
            return nil
        default:
            var index = start
            while index < chars.count, !",}]\n".contains(chars[index]) { index += 1 }
            var end = index - 1
            while end > start, chars[end].isWhitespace { end -= 1 }
            return end
        }
    }

    private static func lastNonWhitespace(_ chars: [Character], before limit: Int) -> Int? {
        var index = limit - 1
        while index >= 0, chars[index].isWhitespace { index -= 1 }
        return index >= 0 ? index : nil
    }

    /// The indent of the first top-level key; new entries reuse it.
    private static func detectIndent(_ chars: [Character], openBrace: Int) -> String {
        var index = openBrace + 1
        var run = ""
        while index < chars.count {
            let ch = chars[index]
            if ch == "\n" { run = "" } else if ch == " " || ch == "\t" { run.append(ch) } else { break }
            index += 1
        }
        return run.isEmpty ? "  " : run
    }

    // MARK: Rendering the value

    private static func render(_ value: [String: Any], indent: String, level: Int) -> String? {
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        let inner = String(repeating: indent, count: level + 1)
        let outer = String(repeating: indent, count: level)
        // Order as in section 3: type, command, padding.
        let order = ["type", "command", "padding"]
        let keys = order.filter { value[$0] != nil } + value.keys.filter { !order.contains($0) }.sorted()
        var lines: [String] = []
        for key in keys {
            guard let literal = jsonLiteral(value[key]!) else { return nil }
            lines.append("\(inner)\"\(key)\": \(literal)")
        }
        return "{\n" + lines.joined(separator: ",\n") + "\n\(outer)}"
    }

    private static func jsonLiteral(_ value: Any) -> String? {
        switch value {
        case let string as String:
            guard let data = try? JSONSerialization.data(withJSONObject: [string]),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return String(text.dropFirst().dropLast())
        case let number as Int: return String(number)
        case let flag as Bool: return flag ? "true" : "false"
        case let number as Double: return String(number)
        default: return nil
        }
    }

    // MARK: Safety net

    /// The edit is accepted only if the result parses and differs from the
    /// original by exactly the intended key. Without this check a textual
    /// substitution will one day quietly corrupt somebody's config.
    private static func isEquivalent(
        _ edited: String, to original: String, key: String, value: [String: Any]
    ) -> Bool {
        guard let editedData = edited.data(using: .utf8),
              let editedObject = try? JSONSerialization.jsonObject(with: editedData) as? [String: Any]
        else { return false }

        var expected = (original.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        expected[key] = value

        return NSDictionary(dictionary: editedObject).isEqual(to: expected)
    }

    private static func rewrite(_ original: String?, key: String, value: [String: Any]) -> String {
        var object = (original?.data(using: .utf8)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        object[key] = value
        let data = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )) ?? Data()
        return (String(data: data, encoding: .utf8) ?? "{}") + "\n"
    }
}
