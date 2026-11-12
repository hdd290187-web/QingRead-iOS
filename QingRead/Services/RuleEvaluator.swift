import Foundation
import SwiftSoup

// Deliberately small, testable Legado-compatible subset. No JavaScript runtime.
enum RuleNode {
    case html(Element)
    case json(Any)
}
struct RuleDocument {
    let root: RuleNode
    init(data: Data, baseURL: String) throws {
        if let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) { root = .json(json) }
        else { root = .html(try SwiftSoup.parse(TXTParser.decode(data).text, baseURL)) }
    }
    func nodes(_ rule: String, from node: RuleNode? = nil) throws -> [RuleNode] {
        let node = node ?? root
        switch node {
        case .json(let value): return try Self.jsonPath(rule, in: value).map { .json($0) }
        case .html(let element):
            guard !rule.isEmpty else { return [node] }
            var current = [element]
            let stages = rule.replacingOccurrences(of: "@css:", with: "").split(separator: "@", omittingEmptySubsequences: true)
            for stage in stages {
                let selector = Self.css(String(stage))
                current = try current.flatMap { try $0.select(selector).array() }
            }
            return current.map { .html($0) }
        }
    }
    func value(_ raw: String, from node: RuleNode? = nil, preserveLines: Bool = false) throws -> String {
        if raw.isEmpty { return "" }
        for fallback in raw.components(separatedBy: "||") {
            let pieces = fallback.components(separatedBy: "##")
            let rule = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let current = node ?? root
            var output = ""
            switch current {
            case .json(let object):
                let values = try Self.jsonPath(rule, in: object)
                output = values.compactMap { value in
                    if let text = value as? String { return text }
                    if let number = value as? NSNumber { return number.stringValue }
                    return nil
                }.joined(separator: "\n")
            case .html(let element):
                var parts = rule.replacingOccurrences(of: "@css:", with: "").components(separatedBy: "@")
                let action = parts.last ?? "text"
                let known = ["text", "textNodes", "html", "ownText", "href", "src", "content", "value", "title", "alt"]
                let attribute: String
                if known.contains(action) { attribute = parts.removeLast() } else { attribute = "text" }
                let selector = parts.filter { !$0.isEmpty }.joined(separator: "@")
                let elements: [Element] = selector.isEmpty ? [element] : try nodes(selector, from: current).compactMap { if case .html(let e) = $0 { return e }; return nil }
                output = try elements.map { item in
                    if attribute == "html" || (preserveLines && attribute == "text") { return try Self.cleanHTML(item.html()) }
                    if attribute == "text" || attribute == "textNodes" { return try item.text() }
                    if attribute == "ownText" { return item.ownText() }
                    return try item.attr(attribute)
                }.joined(separator: preserveLines ? "\n" : " ")
            }
            if pieces.count >= 2, !pieces[1].isEmpty {
                let regex = try NSRegularExpression(pattern: pieces[1])
                output = regex.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: pieces.count >= 3 ? pieces[2] : "")
            }
            if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return output.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return ""
    }
    static func css(_ rule: String) -> String {
        var value = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("class.") { value = "." + value.dropFirst(6) }
        else if value.hasPrefix("id.") { value = "#" + value.dropFirst(3) }
        else if value.hasPrefix("tag.") { value = String(value.dropFirst(4)) }
        if let match = value.range(of: #"\.(-?\d+)$"#, options: .regularExpression) {
            let index = value[match].dropFirst(); value.replaceSubrange(match, with: ":eq(\(index))")
        }
        return value
    }
    static func jsonPath(_ raw: String, in root: Any) throws -> [Any] {
        var path = raw.replacingOccurrences(of: "@json:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "$" || path.isEmpty { return (root as? [Any]) ?? [root] }
        if path.hasPrefix("$.") { path = String(path.dropFirst(2)) }
        else if path.hasPrefix("$") { path = String(path.dropFirst()) }
        guard !path.contains(".."), !path.contains("?"), !path.contains("(") else { throw ReaderError.message("不支持 JSONPath 递归或过滤表达式。") }
        path = path.replacingOccurrences(of: "['", with: ".").replacingOccurrences(of: "']", with: "").replacingOccurrences(of: "[\"", with: ".").replacingOccurrences(of: "\"]", with: "")
        let pattern = try NSRegularExpression(pattern: #"([^\.\[\]]+)|\[(\d+|\*)\]"#)
        var values: [Any] = [root]
        for match in pattern.matches(in: path, range: NSRange(path.startIndex..., in: path)) {
            if let keyRange = Range(match.range(at: 1), in: path) {
                let key = String(path[keyRange])
                values = values.flatMap { value -> [Any] in
                    if key == "*", let array = value as? [Any] { return array }
                    if let dictionary = value as? [String: Any], let next = dictionary[key] { return [next] }
                    return []
                }
            } else if let indexRange = Range(match.range(at: 2), in: path) {
                let index = String(path[indexRange])
                values = values.flatMap { value -> [Any] in
                    guard let array = value as? [Any] else { return [] }
                    if index == "*" { return array }
                    guard let number = Int(index), array.indices.contains(number) else { return [] }; return [array[number]]
                }
            }
        }
        return values.flatMap { ($0 as? [Any]) ?? [$0] }
    }
    static func cleanHTML(_ html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        try document.select("script,style,iframe,noscript").remove()
        let stripped = try document.body()?.html() ?? ""
        let paragraphs = stripped.replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div|h[1-6]|li)\s*>"#, with: "\u{2028}", options: .regularExpression)
        return try SwiftSoup.parse(paragraphs).text().replacingOccurrences(of: "\u{2028}", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
