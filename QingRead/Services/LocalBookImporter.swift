import Foundation
import CryptoKit

struct PreparedLocalBook {
    let book: Book
    let identity: String
}

struct LocalBookImporter {
    static func prepareTXT(url: URL, title: String, directory: URL, id: UUID) throws -> PreparedLocalBook {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= TXTParser.maxFileSize else { throw ReaderError.message("TXT 超过 64 MB，请拆分后导入。") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoded: (text: String, encoding: TXTEncoding)
        do { decoded = try TXTParser.decode(data) }
        catch { throw ImportPipelineError(stage: .decode, reason: error.localizedDescription, suggestion: "请将原文件另存为 UTF-8 纯文本后再试。", underlying: error) }
        let controls = decoded.text.unicodeScalars.filter { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t" }
        if decoded.text.contains("\0") || controls.count > max(2, decoded.text.unicodeScalars.count / 50) {
            throw ImportPipelineError(stage: .decode, reason: "文件包含过多二进制控制字符，无法作为小说正文读取。", suggestion: "请确认文件不是改后缀的 PDF/压缩包，并将纯文本另存为 UTF-8 后再试。", underlying: nil)
        }
        let sections: [TXTSection]
        do { sections = try TXTParser.sections(from: decoded.text, title: title) }
        catch { throw ImportPipelineError(stage: .parse, reason: error.localizedDescription, suggestion: "请确认 TXT 不是空白文件且包含小说正文。", underlying: error) }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw ImportPipelineError(stage: .stage, reason: ImportDiagnostics.userReason(error as NSError), suggestion: "请检查设备可用空间后重试，原始文件已保留。", underlying: error) }
        var chapters: [Chapter] = []
        for (index, section) in sections.enumerated() {
            let file = "chapter-\(index).txt"
            do { try Data(section.text.utf8).write(to: directory.appendingPathComponent(file), options: .atomic) }
            catch { throw ImportPipelineError(stage: .stage, reason: ImportDiagnostics.userReason(error as NSError), suggestion: "正文写入失败，请检查设备空间后重试。", underlying: error) }
            chapters.append(Chapter(title: section.title, length: section.text.utf16.count, file: file))
        }
        return PreparedLocalBook(book: Book(id: id, title: title, format: .txt, chapters: chapters, originalFile: directory.path), identity: textIdentity(sections.map(\.text)))
    }
    static func textIdentity(_ fragments: [String]) -> String {
        var hasher = SHA256()
        for text in fragments { hasher.update(data: Data(text.utf8)) }
        return "txt:utf8:sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func legacyIdentity(for book: Book) -> String? {
        guard let path = book.originalFile else { return nil }
        if book.format == .epub { return (try? DocumentStager.contentIdentity(at: URL(fileURLWithPath: path))).map { "epub:sha256:" + $0 } }
        guard book.format == .txt, !book.chapters.isEmpty else { return nil }
        var hasher = SHA256()
        for chapter in book.chapters {
            guard let file = chapter.file, let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: file.hasPrefix("/") ? file : path + "/" + file)) else { return nil }
            defer { try? handle.close() }
            do { while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) } }
            catch { return nil }
        }
        return "txt:utf8:sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
