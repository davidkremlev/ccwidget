import Foundation

/// Точечная правка `settings.json`.
///
/// `JSONSerialization` теряет отступы и порядок ключей: у пользователя
/// с аккуратным конфигом получается диф на весь файл вместо одной строки.
/// Поэтому значение ключа подменяется прямо в тексте, а остальные байты
/// не трогаются вовсе.
enum SettingsEditor {
    /// Как прошла правка. Онбординг обязан сказать это до нажатия кнопки.
    enum Outcome {
        /// Изменился только нужный ключ, форматирование сохранено.
        case surgical(String)
        /// Точечно не вышло — файл пересобран, порядок ключей и отступы уйдут.
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

    // MARK: Точечная правка

    private static func surgicalEdit(_ text: String, key: String, value: [String: Any]) -> String? {
        let chars = Array(text)
        guard let root = topLevelBraces(chars) else { return nil }
        let indent = detectIndent(chars, openBrace: root.open)
        guard let rendered = render(value, indent: indent, level: 1) else { return nil }

        if let span = valueSpan(chars, of: key, in: root) {
            // Ключ есть: подменяем только его значение.
            return String(chars[..<span.lowerBound]) + rendered + String(chars[span.upperBound...])
        }

        // Ключа нет: дописываем перед закрывающей скобкой, повторяя отступ.
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

    /// Границы корневого объекта.
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

    /// Диапазон значения верхнеуровневого ключа. Одноимённые ключи
    /// на большей глубине игнорируются — иначе правка уедет внутрь.
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

    /// Последний индекс значения, начинающегося с `start`.
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

    /// Отступ первого верхнеуровневого ключа — им же и дописываем.
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

    // MARK: Отрисовка значения

    private static func render(_ value: [String: Any], indent: String, level: Int) -> String? {
        guard JSONSerialization.isValidJSONObject(value) else { return nil }
        let inner = String(repeating: indent, count: level + 1)
        let outer = String(repeating: indent, count: level)
        // Порядок как в ТЗ, раздел 3: type, command, padding.
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

    // MARK: Страховка

    /// Правка принимается, только если результат разбирается и отличается
    /// от исходника ровно нужным ключом. Без этой проверки текстовая
    /// подмена однажды тихо испортит чужой конфиг.
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
