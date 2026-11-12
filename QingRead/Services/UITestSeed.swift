#if DEBUG
import Foundation
extension LibraryStore {
    func seedImportPickerDocumentsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--uitest-import-files") else { return }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("导入测试", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("第一章 文件导入\n这是通过系统文件选择器读取的原创正文。\n第二章 归来\n重启后仍可阅读。".utf8).write(to: directory.appendingPathComponent("系统文件测试.txt"))
            try Data().write(to: directory.appendingPathComponent("空白文件.txt"))
            if let epub = Data(base64Encoded: "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") { try epub.write(to: directory.appendingPathComponent("原创测试书.epub")) }
        } catch { lastError = error.localizedDescription }
    }
    func seedUITestBookIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitest-seed") else { return }
        if let modeArgument = args.first(where: { $0.hasPrefix("--uitest-mode=") }), let mode = ReaderMode(rawValue: String(modeArgument.dropFirst("--uitest-mode=".count))) { settings.mode = mode }
        guard !books.contains(where: { $0.title == "原创阅读测试" }) else { return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("原创阅读测试.txt")
        var text = ""
        for chapter in 1...3 {
            text += "第\(chapter)章 测试\n"
            for line in 1...70 { text += "这是第\(chapter)章第\(line)段原创文字，用于测试中文分页、字符定位与章节衔接。小舟经过湖面，晚风吹过树梢。\n\n" }
        }
        do { try Data(text.utf8).write(to: file); await importFile(from: file) } catch { lastError = error.localizedDescription }
    }
}
#endif
