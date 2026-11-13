#if DEBUG
import Foundation
import CryptoKit

extension LibraryStore {
    func seedReaderPerformanceIfRequested() async {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--uitest-performance=") || $0.hasPrefix("--uitest-integrity=") }) else { return }
        let integrity = argument.hasPrefix("--uitest-integrity=")
        let fixture = String(argument.split(separator: "=", maxSplits: 1).last ?? "")
        guard ["short", "long", "monolith"].contains(fixture) else { return }
        settings.mode = .scroll
        settings.fontSize = 20; settings.font = .serif; settings.theme = .white
        settings.sidePadding = 28; settings.lineSpacing = 8; settings.paragraphSpacing = 12
        guard books.isEmpty else { return }
        // Each fresh synthetic test attempt owns its report. Reopening the reader
        // within that attempt still keeps the active-gesture sample in the probe.
        let variant = ProcessInfo.processInfo.arguments.contains("--reader-baseline") ? "baseline" : "optimized"
        let reports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(integrity ? "ReaderIntegrity" : "ReaderPerformance", isDirectory: true)
        try? FileManager.default.removeItem(at: reports.appendingPathComponent("\(fixture)-\(variant).json"))
        let chapterCount = fixture == "short" ? 5 : fixture == "monolith" ? 1 : integrity ? 96 : 80
        let paragraphs = fixture == "short" ? 12 : fixture == "monolith" ? 5000 : integrity ? 8 : 100
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(integrity ? "滚动顺序回归样本.txt" : "滚动性能原创样本.txt")
        var text = ""
        for chapter in 1...chapterCount {
            text += "第\(chapter)章 原创性能样本\n"
            for line in 1...paragraphs {
                text += "原创段落\(line)（样本章节\(chapter)）。山间的风拂过纸页，湖面映着月光。这段原创测试文字用来核对连续滚动、章节顺序和字符位置，含有表情😊与扩展汉字𠮷。\n\n"
            }
        }
        do {
            let bytes = Data(text.utf8)
            try bytes.write(to: file)
            guard var book = await importFile(from: file) else { return }
            if fixture == "monolith" {
                // Normal imports keep their 24k storage partitions. This DEBUG
                // fixture explicitly exercises one unusually large engine chapter.
                guard let directory = book.originalFile else { throw ReaderError.message("性能样本目录不存在。") }
                let name = "reader-performance-monolith.txt"
                try bytes.write(to: URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name))
                book.chapters = [Chapter(title: "第1章 原创性能样本", length: text.utf16.count, file: name)]
                book = add(book)
            }
            guard book.chapters.count == chapterCount, book.characterCount == text.utf16.count else {
                throw ReaderError.message("性能样本章节或字符校验失败，不能用于对照。")
            }
            let metadata: [String: Any] = [
                "schema": 1, "fixture": fixture, "engineChapterCount": book.chapters.count,
                "chapterUTF16Lengths": book.chapters.map(\.length), "totalUTF16": book.characterCount,
                "paragraphsPerChapter": paragraphs, "normalImportPartitionUTF16": TXTParser.chunkLimit,
                "singleChapterStressFixture": fixture == "monolith",
                "contentSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            ]
            try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: reports.appendingPathComponent("\(fixture)-fixture.json"), options: .atomic)
        }
        catch { lastError = error.localizedDescription }
    }
}
#endif
