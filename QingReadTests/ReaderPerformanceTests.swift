import XCTest
import UIKit
@testable import QingRead

@MainActor
final class ReaderPerformanceTests: XCTestCase {
    func testChunksPreserveUTF16ComposedCharactersAndCRLF() {
        let text = "第一章\r\n" + String(repeating: "中文𠮷👨‍👩‍👧‍👦😊e\u{301}，一个很长的段落。", count: 1200) + "\r\n尾声。\n"
        let source = text as NSString
        let ranges = ScrollChapterLayout.chunkRanges(in: source, limit: 512)
        XCTAssertGreaterThan(ranges.count, 10)
        XCTAssertEqual(ranges.first?.start, 0); XCTAssertEqual(ranges.last?.end, source.length)
        XCTAssertEqual(ranges.map { source.substring(with: NSRange(location: $0.start, length: $0.length)) }.joined(), text)
        for pair in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(pair.0.end, pair.1.start)
            XCTAssertEqual(NSMaxRange(source.rangeOfComposedCharacterSequence(at: pair.0.end - 1)), pair.0.end)
        }
        XCTAssertTrue(ranges.allSatisfy { $0.length < 550 })
    }
    func testWorkerDoesNotPaginateScrollOrPerformLayoutOnMainThread() async throws {
        ReaderPerformanceRecorder.shared.enableForTesting(true)
        defer { ReaderPerformanceRecorder.shared.enableForTesting(false) }
        var settings = ReaderSettings(); settings.mode = .scroll
        let text = "第一章\n" + String(repeating: "这是用于后台排版验证的原创中文文字。😊\n\n", count: 1600)
        let prepared = try await ReaderLayoutWorker.shared.prepare(text: text, size: CGSize(width: 319, height: 640), width: 375, settings: settings, title: "第一章", foreground: .black)
        XCTAssertNil(prepared.pages)
        let layout = try XCTUnwrap(prepared.scroll)
        XCTAssertEqual(layout.length, text.utf16.count)
        XCTAssertLessThan(layout.chunks.count, 100)
        XCTAssertEqual(layout.chunks.map(\.attributed.string).joined(), text)
        ReaderPerformanceRecorder.shared.recordViewport(width: 375, height: 640, visibleLines: 18)
        let report = ReaderPerformanceRecorder.shared.snapshot()
        let validReport = JSONSerialization.isValidJSONObject(report)
        XCTAssertTrue(validReport, "性能报告必须仅包含可序列化的数值和容器")
        if validReport { _ = try JSONSerialization.data(withJSONObject: report) }
        let main = try XCTUnwrap(report["mainThreadOperations"] as? [String: Any])
        let all = try XCTUnwrap(report["operations"] as? [String: Any])
        XCTAssertNil(main["scrollLayout"]); XCTAssertNil(main["attributedText"])
        XCTAssertNil(all["pagination"]); XCTAssertNotNil(all["scrollLayout"])
    }
    func testMeasuredRowsMatchVisibleTextKitAndRetainLineAnchor() async throws {
        var settings = ReaderSettings(); settings.mode = .scroll
        let text = "第一章\n" + String(repeating: "窗外的雨下得很轻，像是不忍打扰屋内的安静。😊𠮷\n\n", count: 70)
        let prepared = try await ReaderLayoutWorker.shared.prepare(text: text, size: CGSize(width: 264, height: 600), width: 320, settings: settings, title: "第一章", foreground: .black)
        let layout = try XCTUnwrap(prepared.scroll)
        for chunk in layout.chunks.prefix(3) {
            let cell = ScrollTextCell(style: .default, reuseIdentifier: nil)
            cell.frame = CGRect(x: 0, y: 0, width: 320, height: chunk.height)
            cell.configure(text: chunk.attributed, settings: settings); cell.layoutIfNeeded()
            cell.textView.layoutManager.ensureLayout(for: cell.textView.textContainer)
            let manager = cell.textView.layoutManager
            let tail = chunk.range.end < layout.length ? manager.extraLineFragmentRect.minY : manager.extraLineFragmentRect.maxY
            let measured = ceil(max(manager.usedRect(for: cell.textView.textContainer).maxY, tail))
            print("ReaderTextKit: workerHeight=\(chunk.height) visibleHeight=\(measured) width=\(cell.textView.textContainer.size.width) leading=\(manager.usesFontLeading) lines=\(chunk.lines.count)")
            if abs(chunk.height - measured) > 1.1 {
                var visible: [(Int, CGFloat, CGFloat)] = []
                let glyphs = manager.glyphRange(for: cell.textView.textContainer)
                manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, range, _ in
                    visible.append((manager.characterRange(forGlyphRange: range, actualGlyphRange: nil).location, rect.minY, rect.height))
                }
                print("ReaderTextKit mismatch: containerHeight=\(cell.textView.textContainer.size.height) visibleUTF16=\(manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).length) expectedUTF16=\(chunk.attributed.length) visibleLines=\(visible.count)")
                for index in 0..<min(10, min(chunk.lines.count, visible.count)) {
                    print("ReaderTextKit line \(index): workerStart=\(chunk.lines[index].start) workerY=\(chunk.lines[index].y) visible=\(visible[index])")
                }
            }
            XCTAssertEqual(chunk.height, measured, accuracy: 1.1)
            if let line = chunk.lines.dropFirst(3).first {
                XCTAssertEqual(chunk.character(atY: line.y + 1), line.start)
                XCTAssertLessThanOrEqual(abs(cell.character(at: CGPoint(x: settings.sidePadding, y: line.y + 1)) - line.start), 3)
            }
        }
    }
    func testStagedProgressDoesNotWriteUntilFlushAndFlushIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("原创位置.txt")
        try Data(("第一章\n" + String(repeating: "原创正文。\n", count: 100)).utf8).write(to: file)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let imported = await library.importFile(from: file)
        let book = try XCTUnwrap(imported)
        let session = ReaderSession(book: book, library: library)
        let path = library.root.appendingPathComponent("library.json")
        let before = try Data(contentsOf: path)
        ReaderPerformanceRecorder.shared.enableForTesting(true)
        defer { ReaderPerformanceRecorder.shared.enableForTesting(false) }
        for offset in 1...200 { session.stage(ReadingPosition(characterOffset: offset, progression: Double(offset) / Double(book.characterCount))) }
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(library.position(for: book).characterOffset, 0)
        session.flush()
        XCTAssertEqual(LibraryStore(rootURL: library.root).position(for: book).characterOffset, 200)
        let after = try Data(contentsOf: path)
        session.flush(); XCTAssertEqual(try Data(contentsOf: path), after)
        let all = ReaderPerformanceRecorder.shared.snapshot()["operations"] as? [String: [String: Any]]
        XCTAssertEqual(all?["progressCommit"]?["count"] as? Int, 1)
    }
    func testChapterReadUsesWorkerAndCachedReadAvoidsRepeatedIO() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("原创文件.txt")
        try Data("第一章\n正文😊。\n第二章\n归来。".utf8).write(to: file)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let imported = await library.importFile(from: file)
        let session = ReaderSession(book: try XCTUnwrap(imported), library: library)
        ReaderPerformanceRecorder.shared.enableForTesting(true)
        defer { ReaderPerformanceRecorder.shared.enableForTesting(false) }
        let text = try await session.loadText(at: 0)
        let cached = try await session.loadText(at: 0)
        XCTAssertEqual(text, cached); XCTAssertTrue(text.contains("正文😊"))
        let report = ReaderPerformanceRecorder.shared.snapshot()
        let main = report["mainThreadOperations"] as? [String: Any]
        let all = report["operations"] as? [String: [String: Any]]
        XCTAssertNil(main?["fileRead"])
        XCTAssertEqual(all?["fileRead"]?["count"] as? Int, 1)
    }
}
