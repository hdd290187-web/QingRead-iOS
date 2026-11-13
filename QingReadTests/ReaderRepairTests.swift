import XCTest
import UIKit
import CoreText
@testable import QingRead

@MainActor final class ReaderRepairTests: XCTestCase {
    func testBuild43SnapshotDefaultsProgressAndBacksUpBeforeNewWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let book = Book(title: "旧书", format: .txt, chapters: [Chapter(title: "第一章", length: 1000)])
        let first = Bookmark(bookID: book.id, position: ReadingPosition(characterOffset: 123), title: "保留")
        let duplicate = Bookmark(bookID: book.id, position: ReadingPosition(characterOffset: 123), title: "重复")
        let other = Bookmark(bookID: book.id, position: ReadingPosition(characterOffset: 456), title: "不同位置")
        let snapshot = LibraryStore.Snapshot(books: [book], positions: [book.id: first.position], bookmarks: [first, duplicate, other], settings: ReaderSettings(), sources: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any]); settings.removeValue(forKey: "showBottomProgress"); settings["font"] = "rounded"; json["settings"] = settings
        let bytes = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        try bytes.write(to: root.appendingPathComponent("library.json"))
        let library = LibraryStore(rootURL: root)
        XCTAssertTrue(library.settings.showBottomProgress); XCTAssertEqual(library.settings.font, .rounded)
        XCTAssertEqual(library.bookmarks(for: book).map(\.position.characterOffset).sorted(), [123, 456])
        XCTAssertEqual(Set(library.bookmarks.map(\.id)), Set([first.id, other.id]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), bytes)
        library.settings.showBottomProgress = false; library.flushSettingsIfNeeded()
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library-before-build44.json")), bytes)
        let restarted = LibraryStore(rootURL: root)
        XCTAssertEqual(restarted.books.first?.id, book.id); XCTAssertEqual(restarted.position(for: book).characterOffset, 123)
        XCTAssertFalse(restarted.settings.showBottomProgress); XCTAssertEqual(restarted.bookmarks(for: book).count, 2)
    }
    func testBookmarkToggleAndSameAnchorDedupPersistAcrossRestart() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(rootURL: root)
        let book = library.add(Book(title: "书签回归", format: .txt, chapters: [Chapter(title: "一", length: 900), Chapter(title: "二", length: 900)]))
        let session = ReaderSession(book: book, library: library)
        session.bookmark(); XCTAssertTrue(session.hasBookmark); XCTAssertEqual(library.bookmarks.count, 1)
        session.bookmark(); XCTAssertFalse(session.hasBookmark); XCTAssertTrue(library.bookmarks.isEmpty)
        session.bookmark()
        library.addBookmark(Bookmark(bookID: book.id, position: ReadingPosition(progression: 0.1), title: "重复锚点但时间不同"))
        XCTAssertEqual(library.bookmarks.count, 1)
        session.report(ReadingPosition(characterOffset: 123)); session.bookmark()
        session.report(ReadingPosition(chapter: 1)); session.bookmark()
        XCTAssertEqual(library.bookmarks.count, 3)
        let restarted = LibraryStore(rootURL: root); XCTAssertEqual(restarted.bookmarks.count, 3)
        let restored = ReaderSession(book: book, library: restarted); XCTAssertTrue(restored.hasBookmark)
        if let mark = restarted.bookmarks(for: book).first(where: { $0.position.chapter == 1 }) { restarted.deleteBookmark(mark) }
        XCTAssertFalse(restored.hasBookmark); XCTAssertEqual(restarted.bookmarks.count, 2)
    }
    func testSettingsAreLiveButPersistOnlyAfterDebounceOrFlush() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(rootURL: root); library.flush()
        let file = root.appendingPathComponent("library.json"); let old = try Data(contentsOf: file)
        for i in 14...36 { library.settings.fontSize = Double(i) }
        XCTAssertEqual(library.settings.fontSize, 36)
        XCTAssertEqual(try Data(contentsOf: file), old)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(LibraryStore(rootURL: root).settings.fontSize, 36)
        library.settings.lineSpacing = 15; library.flushSettingsIfNeeded()
        XCTAssertEqual(LibraryStore(rootURL: root).settings.lineSpacing, 15)
    }
    func testInstalledFontInventoryUsesRealUIFontFaces() {
        for font in ReaderFont.allCases {
            print("ReaderFontInventory \(font.rawValue)=\(font.installedName ?? (ReaderFont.available.contains(font) ? "built-in" : "unavailable"))")
        }
        print("ReaderFontFamilies " + UIFont.familyNames.filter { $0.localizedCaseInsensitiveContains("Song") || $0.localizedCaseInsensitiveContains("Kai") || $0.localizedCaseInsensitiveContains("Hei") || $0.localizedCaseInsensitiveContains("Yuan") }.joined(separator: ","))
        XCTAssertEqual(Array(ReaderFont.available.prefix(3)), [.system, .rounded, .serif])
        XCTAssertGreaterThanOrEqual(ReaderFont.available.count, 5)
        XCTAssertEqual(ReaderFont.kaiti.installedName, "LXGWWenKaiLite-Regular")
        for font in ReaderFont.available.dropFirst(3) { XCTAssertNotNil(font.installedName.flatMap { UIFont(name: $0, size: 20) }) }
    }
    func testAvailableChineseFontsAndMissingGlyphFallback() {
        for font in ReaderFont.available {
            var settings=ReaderSettings();settings.font=font
            let line=CTLineCreateWithAttributedString(NSAttributedString(string:"予盈中文，𠮷😊。",attributes:[.font:settings.uiFont]))
            let runs=CTLineGetGlyphRuns(line) as! [CTRun]
            XCTAssertFalse(runs.isEmpty)
            for run in runs {
                let count=CTRunGetGlyphCount(run)
                var glyphs=[CGGlyph](repeating:0,count:count)
                CTRunGetGlyphs(run,CFRange(location:0,length:count),&glyphs)
                XCTAssertTrue(glyphs.allSatisfy { $0 != 0 },font.rawValue)
                let attributes=CTRunGetAttributes(run) as NSDictionary
                if let face=attributes[kCTFontAttributeName] {
                    XCTAssertFalse((CTFontCopyPostScriptName(face as! CTFont) as String).contains("LastResort"))
                }
            }
        }
    }
    func testRapidSuccessfulImportsReplaceOneToastAndAutoDismiss() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let library=LibraryStore(rootURL:root.appendingPathComponent("library"))
        let controller=DocumentImportController()
        func waitForToast(_ title:String) async throws {
            for _ in 0..<100 {
                if controller.toast?.result.imported == [title] { return }
                try await Task.sleep(nanoseconds:30_000_000)
            }
            XCTFail("成功导入应出现对应的单个轻提示")
        }
        for title in ["先导入","后导入"] {
            let url=root.appendingPathComponent(title+".txt")
            try Data(("第一章\n"+title+"的独立原创内容。\n").utf8).write(to:url)
            controller.consume(.success([url]),library:library)
            try await waitForToast(title)
            XCTAssertNil(controller.feedback,"全部成功不能自动弹出结果 sheet")
        }
        try await Task.sleep(nanoseconds:1_400_000_000)
        XCTAssertEqual(controller.toast?.result.imported,["后导入"],"旧提示的计时器不能清除新结果")
        try await Task.sleep(nanoseconds:600_000_000)
        XCTAssertNil(controller.toast)
        XCTAssertEqual(controller.lastFeedback?.result.imported,["后导入"])
        XCTAssertEqual(library.books.count,2)
    }
}
