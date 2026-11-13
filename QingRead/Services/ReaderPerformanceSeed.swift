#if DEBUG
import Foundation

extension LibraryStore {
    func seedReaderPerformanceIfRequested() async {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--uitest-performance=") }) else { return }
        let fixture = String(argument.dropFirst("--uitest-performance=".count))
        settings.mode = .scroll
        settings.fontSize = 20; settings.font = .serif; settings.theme = .white
        settings.sidePadding = 28; settings.lineSpacing = 8; settings.paragraphSpacing = 12
        guard books.isEmpty else { return }
        let chapterCount = fixture == "short" ? 5 : fixture == "monolith" ? 1 : 80
        let paragraphs = fixture == "short" ? 12 : fixture == "monolith" ? 5000 : 100
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("滚动性能原创样本.txt")
        var text = ""
        for chapter in 1...chapterCount {
            text += "第\(chapter)章 原创性能样本\n"
            for line in 1...paragraphs {
                text += "第\(chapter)章第\(line)段。山间的风拂过纸页，湖面映着月光。这段原创测试文字用来核对连续滚动、章节顺序和字符位置，含有表情😊与扩展汉字𠮷。\n\n"
            }
        }
        do { try Data(text.utf8).write(to: file); _ = await importFile(from: file) }
        catch { lastError = error.localizedDescription }
    }
}
#endif
