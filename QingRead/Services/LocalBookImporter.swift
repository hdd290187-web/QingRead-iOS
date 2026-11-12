import Foundation

struct LocalBookImporter {
    static func importTXT(url: URL, directory: URL, id: UUID) throws -> Book {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= TXTParser.maxFileSize else { throw ReaderError.message("TXT 超过 64 MB，请拆分后导入。") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoded = try TXTParser.decode(data)
        let title = url.deletingPathExtension().lastPathComponent
        let sections = try TXTParser.sections(from: decoded.text, title: title)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var chapters: [Chapter] = []
        for (index, section) in sections.enumerated() {
            let file = "chapter-\(index).txt"
            try Data(section.text.utf8).write(to: directory.appendingPathComponent(file), options: .atomic)
            chapters.append(Chapter(title: section.title, length: section.text.utf16.count, file: file))
        }
        return Book(id: id, title: title, format: .txt, chapters: chapters, originalFile: directory.path, originURL: url)
    }
}
