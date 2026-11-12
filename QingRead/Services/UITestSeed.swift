#if DEBUG
import Foundation
extension LibraryStore {
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
