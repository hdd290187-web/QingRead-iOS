import XCTest
import ReadiumShared
@testable import QingRead

@MainActor
final class EPUBTests: XCTestCase {
    func testEPUBImportMetadataTOCImagesAndLocator() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OriginalFixture", withExtension: "epub"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(rootURL: root)
        let imported = await library.importFile(from: url)
        let book = try XCTUnwrap(imported, library.lastError ?? "no book")
        XCTAssertEqual(book.title, "原创测试书")
        XCTAssertEqual(book.author, "测试作者")
        XCTAssertEqual(book.chapters.map(\.title), ["第一章 出发", "第二章 归来"])
        let service = EPUBService()
        let publication = try await service.open(path: XCTUnwrap(book.originalFile))
        XCTAssertEqual(publication.readingOrder.count, 2)
        XCTAssertTrue(publication.resources.contains { $0.href.hasSuffix("image.svg") })
        let locator = await publication.locate(publication.readingOrder[1])
        let json = try XCTUnwrap(locator).jsonString()
        let restored = try Locator(jsonString: json)
        XCTAssertEqual(restored.href, locator?.href)
        library.update(position: ReadingPosition(chapter: 1, locatorJSON: json, progression: 0.5), for: book)
        let restart = LibraryStore(rootURL: root)
        XCTAssertEqual(restart.position(for: book).locatorJSON, json)
    }
    func testInvalidEPUBIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalid = root.appendingPathComponent("broken.epub"); try Data("not a zip".utf8).write(to: invalid)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let imported = await library.importFile(from: invalid)
        XCTAssertNil(imported); XCTAssertTrue(library.books.isEmpty); XCTAssertNotNil(library.lastError)
    }
}
