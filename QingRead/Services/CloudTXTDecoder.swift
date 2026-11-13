import Foundation
import CoreFoundation

/// Honor the v1 encoding metadata, including a manual correction made in the web library.
/// The existing chapter parser, validation, staging and local import engine remain in use.
enum CloudTXTDecoder {
    static func decode(_ data: Data, encoding: String) throws -> (text: String, encoding: TXTEncoding) {
        guard data.count <= TXTParser.maxFileSize else { throw CloudError.tooLarge }
        let selected: String.Encoding
        let kind: TXTEncoding
        switch encoding.lowercased() {
        case "utf-8", "utf-8-sig": selected = .utf8; kind = .utf8
        case "utf-16": selected = .utf16; kind = .utf16
        case "utf-16-le": selected = .utf16LittleEndian; kind = .utf16
        case "utf-16-be": selected = .utf16BigEndian; kind = .utf16
        case "gb18030", "gbk":
            selected = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            kind = .gb18030
        default: throw ReaderError.message("云端指定的文字编码不受支持，请在后台更正后重试。")
        }
        guard let text = String(data: data, encoding: selected) else { throw ReaderError.message("无法按云端指定的编码读取正文，请在后台更正编码后重试。") }
        return (text.replacingOccurrences(of: "\u{FEFF}", with: ""), kind)
    }
}
