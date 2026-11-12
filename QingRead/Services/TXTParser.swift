import Foundation
import CoreFoundation

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
enum TXTEncoding: String { case utf8 = "UTF-8", utf16 = "UTF-16", gb18030 = "GB18030/GBK" }
struct TXTSection { var title: String; var text: String }
struct TXTParser {
    static let maxFileSize = 200 * 1024 * 1024
    static let chunkLimit = 24000
    static func decode(_ data: Data) throws -> (text: String, encoding: TXTEncoding) {
        guard data.count <= maxFileSize else { throw ReaderError.message("文件超过 200 MB，请先拆分后导入。") }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16) { return (s, .utf16) }
        // BOM-less UTF-16 is detected from zero-byte distribution, before UTF-8.
        let sample = Array(data.prefix(1024))
        if sample.count > 4 {
            let evenZeros = stride(from: 0, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
            let oddZeros = stride(from: 1, to: sample.count, by: 2).filter { sample[$0] == 0 }.count
            if max(evenZeros, oddZeros) > sample.count / 6,
               let s = String(data: data, encoding: oddZeros > evenZeros ? .utf16LittleEndian : .utf16BigEndian) { return (s, .utf16) }
        }
        if let s = String(data: data, encoding: .utf8) { return (s.replacingOccurrences(of: "\u{FEFF}", with: ""), .utf8) }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return (s, .gb18030) }
        throw ReaderError.message("无法识别文字编码。支持 UTF-8、UTF-16、GB18030/GBK。")
    }
    static func sections(from text: String, title: String) throws -> [TXTSection] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReaderError.message("文件没有可阅读的正文。") }
        let regex = try NSRegularExpression(pattern: #"(?m)^[\t 　]*(?:第[0-9零〇一二三四五六七八九十百千万两]+[章回节卷部集][^\n]{0,60}|序章[^\n]{0,40}|楔子[^\n]{0,40}|番外[^\n]{0,40})[\t 　]*$"#)
        let ns = normalized as NSString
        let matches = regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length))
        var ranges: [(String, NSRange)] = []
        if matches.isEmpty { ranges.append((title, NSRange(location: 0, length: ns.length))) }
        else {
            if let first = matches.first, first.range.location > 0 { ranges.append(("前言", NSRange(location: 0, length: first.range.location))) }
            for (i, match) in matches.enumerated() {
                let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
                ranges.append((ns.substring(with: match.range).trimmingCharacters(in: .whitespaces), NSRange(location: match.range.location, length: end - match.range.location)))
            }
        }
        var result: [TXTSection] = []
        for (heading, range) in ranges {
            var offset = range.location; var part = 0
            while offset < NSMaxRange(range) {
                let count = min(chunkLimit, NSMaxRange(range) - offset)
                var safe = NSRange(location: offset, length: count)
                safe = ns.rangeOfComposedCharacterSequences(for: safe)
                safe.length = min(safe.length, NSMaxRange(range) - offset)
                result.append(TXTSection(title: part == 0 ? heading : "\(heading) · 续\(part)", text: ns.substring(with: safe)))
                offset = NSMaxRange(safe); part += 1
            }
        }
        return result
    }
}
