import XCTest
@testable import QingRead

@MainActor
final class LibraryTests: XCTestCase {
    func testTXTImportPositionSettingsAndBookmarksSurviveRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("春天.txt")
        let text = "前言\n第一章 出发\n中文😊。\n第二章 归来\n结束。"
        try Data(text.utf8).write(to: file)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let imported = await library.importFile(from: file)
        let book = try XCTUnwrap(imported)
        XCTAssertEqual(book.chapters.count, 3)
        XCTAssertEqual(book.chapters.map { library.chapterText(for: $0, book: book) }.joined(), text)
        let position = ReadingPosition(chapter: 2, characterOffset: 3, progression: 0.8)
        library.update(position: position, for: book)
        library.settings.fontSize = 26
        library.addBookmark(Bookmark(bookID: book.id, position: position, title: "归来"))
        let restart = LibraryStore(rootURL: library.root)
        XCTAssertEqual(restart.books.first?.id, book.id)
        XCTAssertEqual(restart.position(for: book), position)
        XCTAssertEqual(restart.settings.fontSize, 26)
        XCTAssertEqual(restart.bookmarks(for: book).count, 1)
        let duplicate = await library.importFile(from: file)
        XCTAssertEqual(duplicate?.id, book.id)
        XCTAssertEqual(library.books.count, 1)
        library.remove(book)
        XCTAssertTrue(library.books.isEmpty)
    }
    func testOfflineChapterCacheSurvivesRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(rootURL: root)
        let book = library.add(Book(title: "缓存测试", format: .online, chapters: [Chapter(title: "第一章", remoteURL: URL(string: "https://example.invalid/1"))], source: BookSource(name: "测试", baseURL: "https://example.invalid", searchURL: "/s")))
        try library.cacheChapter(book: book, index: 0, text: "已经缓存的中文正文😊。")
        let restart = LibraryStore(rootURL: root)
        let restored = try XCTUnwrap(restart.books.first)
        XCTAssertEqual(restart.chapterText(for: restored.chapters[0], book: restored), "已经缓存的中文正文😊。")
        let session = ReaderSession(book: restored, library: restart)
        let cached = try await session.loadText(at: 0)
        XCTAssertEqual(cached, "已经缓存的中文正文😊。")
    }
    func testEmptyImportLeavesNoBook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("empty.txt"); try Data().write(to: file)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let imported = await library.importFile(from: file)
        XCTAssertNil(imported)
        XCTAssertTrue(library.books.isEmpty)
        XCTAssertNotNil(library.lastError)
    }
}
