import XCTest
import Combine
@testable import QingRead

@MainActor
final class ImportRepairTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("选择的中文书.txt")
        try Data("第一章 开始\n这是从文件选择器导入的原创正文。\n第二章 归来\n结束。".utf8).write(to: file)
        return (directory, file)
    }
    func testCoordinatedPrivateCopyAndNoScopeNeededForAppFiles() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let stage = directory.appendingPathComponent("staging")
        let copied = try await Task.detached { try DocumentStager.copyIntoPrivateDirectory(source: source, directory: stage) }.value
        XCTAssertFalse(copied.securityScopeGranted) // An ordinary app-owned file is still valid.
        XCTAssertEqual(try Data(contentsOf: source), try Data(contentsOf: copied.fileURL))
        XCTAssertTrue(copied.fileURL.path.hasPrefix(stage.path))
        XCTAssertEqual(copied.identity.count, 64)
        try FileManager.default.removeItem(at: source)
        XCTAssertFalse(try Data(contentsOf: copied.fileURL).isEmpty)
    }
    func testParsingUsesOnlyStagedFileAfterProviderURLDisappears() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let environment = ImportEnvironment(stage: { url, target, progress in
            let copy = try await ImportEnvironment.live.stage(url, target, progress)
            try FileManager.default.removeItem(at: url)
            return copy
        }, beforeCommit: { _ in })
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"), importEnvironment: environment)
        let result = await library.importFiles(from: [source])
        XCTAssertEqual(result.imported.count, 1); XCTAssertTrue(result.failures.isEmpty)
        let book = try XCTUnwrap(library.books.first)
        XCTAssertNil(book.originURL)
        XCTAssertNotNil(book.sourceIdentity)
        XCTAssertTrue(library.chapterText(for: book.chapters[0], book: book).contains("原创正文"))
        let restart = LibraryStore(rootURL: library.root)
        XCTAssertEqual(restart.books.first?.id, book.id)
        XCTAssertFalse(restart.chapterText(for: book.chapters[0], book: book).isEmpty)
    }
    func testDuplicateByContentsAcrossNamesAndURLsKeepsPosition() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"))
        let firstResult = await library.importFiles(from: [source]); XCTAssertTrue(firstResult.failures.isEmpty)
        let first = try XCTUnwrap(library.books.first)
        let position = ReadingPosition(chapter: 1, characterOffset: 2, progression: 0.8)
        library.update(position: position, for: first)
        library.addBookmark(Bookmark(bookID: first.id, position: position, title: "原书签"))
        let another = directory.appendingPathComponent("不同文件名.txt")
        try FileManager.default.copyItem(at: source, to: another)
        let duplicate = await library.importFiles(from: [another])
        XCTAssertEqual(duplicate.duplicates, [first.title]); XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.position(for: first), position); XCTAssertEqual(library.bookmarks(for: first).count, 1)
    }
    func testLegacySnapshotMigrationBacksUpAndPreservesBookID() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"))
        let imported = await library.importFile(from: source); let book = try XCTUnwrap(imported)
        let position = ReadingPosition(chapter: 1, characterOffset: 3, progression: 0.7)
        library.update(position: position, for: book)
        let index = library.root.appendingPathComponent("library.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        var books = try XCTUnwrap(json["books"] as? [[String: Any]])
        books[0].removeValue(forKey: "sourceIdentity"); books[0]["originURL"] = source.absoluteString
        json["books"] = books
        let previous = try JSONSerialization.data(withJSONObject: json)
        try previous.write(to: index, options: .atomic)
        let legacy = LibraryStore(rootURL: library.root)
        let duplicate = await legacy.importFiles(from: [source])
        XCTAssertEqual(duplicate.duplicates, [book.title]); XCTAssertEqual(legacy.books.first?.id, book.id)
        XCTAssertEqual(legacy.position(for: book), position)
        XCTAssertNil(legacy.books.first?.originURL); XCTAssertNotNil(legacy.books.first?.sourceIdentity)
        XCTAssertEqual(try Data(contentsOf: library.root.appendingPathComponent("library-before-import-repair.json")), previous)
    }
    func testPartialBatchRetainsSuccessAndShowsExactFailure() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("已被提供器移除.txt")
        let empty = directory.appendingPathComponent("空文件.txt"); try Data().write(to: empty)
        let unsupported = directory.appendingPathComponent("不是小说.pdf"); try Data("pdf".utf8).write(to: unsupported)
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"))
        let result = await library.importFiles(from: [missing, source, empty, unsupported])
        XCTAssertEqual(result.imported.count, 1); XCTAssertEqual(result.failures.count, 3)
        XCTAssertEqual(library.books.count, 1); XCTAssertFalse(library.isImporting)
        XCTAssertTrue(result.failures.contains { $0.stage == .validate && $0.reason.contains("空") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: library.root.appendingPathComponent("import-staging").path)) ?? [], [])
    }
    func testCommitFailureRollsBackNewFilesAndKeepsExistingSnapshot() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("library")
        let good = LibraryStore(rootURL: root); let original = await good.importFile(from: source)
        XCTAssertNotNil(original)
        let snapshot = try Data(contentsOf: root.appendingPathComponent("library.json"))
        let failing = ImportEnvironment(stage: ImportEnvironment.live.stage, beforeCommit: { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError) })
        let library = LibraryStore(rootURL: root, importEnvironment: failing)
        let changed = directory.appendingPathComponent("另一本.txt"); try Data("第一章 新书\n不同的正文。".utf8).write(to: changed)
        let result = await library.importFiles(from: [changed])
        XCTAssertEqual(result.failures.first?.stage, .commit)
        XCTAssertEqual(result.failures.first?.errorCode, NSFileWriteOutOfSpaceError)
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), snapshot)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("books").path).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: changed.path))
    }
    func testProviderPermissionAndUnavailableFailuresKeepUnderlyingCodes() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let provider = NSError(domain: "NSFileProviderErrorDomain", code: -1005)
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: [NSUnderlyingErrorKey: provider])
        let environment = ImportEnvironment(stage: { _, _, _ in
            throw ImportPipelineError(stage: .coordinate, reason: "文件提供器拒绝读取。", suggestion: "请先下载到本机再试。", underlying: denied)
        }, beforeCommit: { _ in })
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"), importEnvironment: environment)
        let result = await library.importFiles(from: [source])
        let failure = try XCTUnwrap(result.failures.first)
        XCTAssertEqual(failure.stage, .coordinate); XCTAssertEqual(failure.errorCode, 257)
        XCTAssertTrue(failure.underlyingCodes.contains("NSFileProviderErrorDomain / -1005"))
        XCTAssertFalse(failure.message.contains(directory.path)); XCTAssertTrue(library.books.isEmpty)
    }
    func testConcurrentImportRequestsSerializeAndDeduplicate() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"))
        async let a = library.importFiles(from: [source])
        async let b = library.importFiles(from: [source])
        let results = await [a, b]
        XCTAssertEqual(results.reduce(0) { $0 + $1.imported.count }, 1)
        XCTAssertEqual(results.reduce(0) { $0 + $1.duplicates.count }, 1)
        XCTAssertEqual(library.books.count, 1); XCTAssertFalse(library.isImporting)
    }
    func testPickerFailureEmptyResultAndCancellationAreVisible() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = LibraryStore(rootURL: directory)
        let controller = DocumentImportController()
        controller.consume(.failure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)), library: library)
        XCTAssertEqual(controller.lastFeedback?.result.failures.first?.stage, .picker)
        controller.consume(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)), library: library)
        XCTAssertEqual(controller.status, "已取消导入"); XCTAssertFalse(library.isImporting)
        let empty = await library.importFiles(from: [])
        XCTAssertEqual(empty.failures.first?.stage, .picker)
        XCTAssertTrue(empty.failures.first?.reason.contains("没有返回") ?? false)
    }
    func testCorruptLegacyIndexIsNeverOverwritten() async throws {
        let (directory, source) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("library"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = Data("corrupt but must preserve".utf8)
        try original.write(to: root.appendingPathComponent("library.json"))
        let library = LibraryStore(rootURL: root)
        let result = await library.importFiles(from: [source])
        XCTAssertEqual(result.failures.count, 1); XCTAssertTrue(library.books.isEmpty)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library.json")), original)
    }
}

extension ImportRepairTests {
    func testUnavailableCloudPlaceholderReportsDownloadStage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = ImportEnvironment(stage: { _, _, _ in
            throw ImportPipelineError(stage: .download, reason: "iCloud 文件在等待期间未完成下载。", suggestion: "请先在‘文件’中下载到本机。", underlying: NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        }, beforeCommit: { _ in })
        let library = LibraryStore(rootURL: directory, importEnvironment: environment)
        let result = await library.importFiles(from: [directory.appendingPathComponent("未下载.txt")])
        XCTAssertEqual(result.failures.first?.stage, .download)
        XCTAssertEqual(result.failures.first?.errorCode, NSURLErrorTimedOut)
        XCTAssertTrue(result.failures.first?.message.contains("下载到本机") ?? false)
        XCTAssertTrue(library.books.isEmpty)
    }
    func testBinaryTextIsRejectedWithDecodeAdvice() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("binary.txt")
        try Data([0, 1, 2, 3, 4, 5, 6, 7]).write(to: file)
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"))
        let result = await library.importFiles(from: [file])
        XCTAssertEqual(result.failures.first?.stage, .decode)
        XCTAssertTrue(result.failures.first?.message.contains("UTF-8") ?? false)
        XCTAssertTrue(library.books.isEmpty)
    }
    func testEPUBDuplicateAcrossProviderCopiesKeepsLocator() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OriginalFixture", withExtension: "epub"))
        let renamed = directory.appendingPathComponent("另一个位置.epub")
        try FileManager.default.copyItem(at: fixture, to: renamed)
        let library = LibraryStore(rootURL: directory.appendingPathComponent("library"))
        let result = await library.importFile(from: fixture)
        let book = try XCTUnwrap(result)
        let position = ReadingPosition(chapter: 1, locatorJSON: "saved-locator", progression: 0.5)
        library.update(position: position, for: book)
        let second = await library.importFiles(from: [renamed])
        XCTAssertEqual(second.duplicates, [book.title]); XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.position(for: book), position)
        XCTAssertNil(book.originURL); XCTAssertNotNil(book.sourceIdentity)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(book.originalFile)))
    }
}
