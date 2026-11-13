import XCTest
import UIKit
import ReadiumNavigator
@testable import QingRead

@MainActor
final class BrandTests: XCTestCase {
    func testBuild24SnapshotRetainsIDsProgressBookmarksAndSettings() throws {
        // A pre-brand schema payload, including every pre-existing settings key.
        let id = "11111111-2222-3333-4444-555555555555"
        let json = """
        {"books":[{"id":"\(id)","title":"旧书架","author":"旧作者","format":"txt","importedAt":1000,"chapters":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","title":"第一章","length":300}],"originalFile":"/private/existing-book","sourceIdentity":"txt:retained"}],"positions":["\(id)",{"chapter":0,"characterOffset":123,"progression":0.41,"updatedAt":2000}],"bookmarks":[{"id":"99999999-8888-7777-6666-555555555555","bookID":"\(id)","position":{"chapter":0,"characterOffset":123,"progression":0.41,"updatedAt":2000},"title":"保留书签","createdAt":2001}],"settings":{"fontSize":26,"font":"system","fontWeight":0.2,"lineSpacing":11,"paragraphSpacing":19,"sidePadding":32,"firstLineIndent":2,"theme":"cream","mode":"curl","tapZoneRatio":0.3,"rightHanded":true,"brightness":0.6,"customBrightness":true},"sources":[]}
        """
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let snapshot = root.appendingPathComponent("library.json")
        try Data(json.utf8).write(to: snapshot)
        let library = LibraryStore(rootURL: root)
        let book = try XCTUnwrap(library.books.first)
        XCTAssertEqual(book.id.uuidString, id)
        XCTAssertEqual(book.chapters.first?.id.uuidString, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(library.position(for: book).characterOffset, 123)
        XCTAssertEqual(library.bookmarks(for: book).first?.title, "保留书签")
        XCTAssertEqual(library.settings.font, .system); XCTAssertEqual(library.settings.theme, .cream)
        XCTAssertEqual(library.settings.mode, .curl); XCTAssertEqual(library.settings.sidePadding, 32)
        XCTAssertEqual(library.settings.fontSize, 26); XCTAssertTrue(library.settings.rightHanded)
        library.flush()
        let restart = LibraryStore(rootURL: root)
        XCTAssertEqual(restart.books, library.books)
        XCTAssertEqual(restart.settings, library.settings)
        XCTAssertEqual(restart.positions, library.positions)
        XCTAssertEqual(restart.bookmarks, library.bookmarks)
        XCTAssertNil(restart.lastError)
    }
    func testStyledHeadingPreservesEveryCharacterAndReflowAnchor() {
        let title = "第一章 纸上的时光"
        let text = title + "\n" + String(repeating: "窗外的雨下得很轻，像是不忍打扰屋内的安静。😊𠮷\n\n", count: 120)
        var settings = ReaderSettings()
        let original = TextPaginator.layout(text, size: CGSize(width: 264, height: 460), settings: settings, chapterTitle: title)
        XCTAssertEqual(original.attributed.string, text)
        XCTAssertEqual(original.ranges.last?.end, text.utf16.count)
        let heading = original.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(heading?.firstLineHeadIndent, 0)
        let body = original.attributed.attribute(.paragraphStyle, at: title.utf16.count + 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(body?.firstLineHeadIndent, settings.firstLineIndent * settings.fontSize)
        let blank = (text as NSString).range(of: "\n\n").location + 1
        let blankFont = original.attributed.attribute(.font, at: blank, effectiveRange: nil) as? UIFont
        XCTAssertLessThan(blankFont?.pointSize ?? 100, settings.fontSize / 2)
        let anchor = original.ranges[3].start
        settings.fontSize = 30; settings.sidePadding = 36; settings.theme = .gray
        let changed = TextPaginator.layout(text, size: CGSize(width: 248, height: 460), settings: settings, chapterTitle: title)
        let range = changed.ranges[changed.page(containing: anchor)]
        XCTAssertLessThanOrEqual(range.start, anchor); XCTAssertGreaterThan(range.end, anchor)
        for pair in zip(changed.ranges, changed.ranges.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start) }
        XCTAssertEqual(changed.ranges.last?.end, text.utf16.count)
    }
    func testGeneratedCoverIsStableVariedAndBounded() {
        let first = Book(title: "山间来信", format: .txt)
        let second = Book(title: "星夜", format: .txt)
        let seed = NatureCover.seed(for: first)
        let image = NatureCover.render(seed: seed)
        XCTAssertEqual(image.pngData(), NatureCover.render(seed: seed).pngData())
        XCTAssertNotEqual(image.pngData(), NatureCover.render(seed: NatureCover.seed(for: second)).pngData())
        XCTAssertEqual(image.size, BookCoverCache.thumbnailSize)
        XCTAssertEqual(image.scale, 1)
    }
    func testEPUBOriginalCoverAndDiskCacheSurviveCacheRecreation() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CoverFixture", withExtension: "epub"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = Book(title: "封面与排版测试", format: .epub, originalFile: url.path)
        let cover = await BookCoverCache(directory: directory).cover(for: book)
        XCTAssertEqual(cover.kind, .epub)
        XCTAssertLessThanOrEqual(cover.image.size.width, 400); XCTAssertLessThanOrEqual(cover.image.size.height, 588)
        XCTAssertEqual(cover.image.size.width / cover.image.size.height, 2.0 / 3.0, accuracy: 0.01)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1); XCTAssertTrue(files[0].lastPathComponent.hasSuffix(".epub.jpg"))
        let cached = await BookCoverCache(directory: directory).cover(for: book)
        XCTAssertEqual(cached.kind, .epub); XCTAssertEqual(cached.image.size, cover.image.size)
    }
    func testEPUBPreferencesUseActualFontPaperSpacingAndExclusiveMode() {
        var settings = ReaderSettings()
        settings.fontSize = 28; settings.lineSpacing = 12; settings.sidePadding = 36
        settings.font = .serif; settings.theme = .green; settings.mode = .scroll
        let prefs = EPUBReaderController.preferences(settings: settings, traits: UITraitCollection(userInterfaceStyle: .light))
        XCTAssertEqual(prefs.fontSize, 1.75)
        XCTAssertEqual(prefs.lineHeight, 40.0 / 28)
        XCTAssertEqual(prefs.pageMargins, 1.5)
        XCTAssertEqual(prefs.fontFamily?.rawValue, "Noto Serif SC")
        XCTAssertEqual(prefs.scroll, true)
        XCTAssertEqual(prefs.publisherStyles, false)
        settings.theme = .system; settings.mode = .curl; settings.font = .rounded
        let changed = EPUBReaderController.preferences(settings: settings, traits: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertEqual(changed.theme, .dark); XCTAssertEqual(changed.scroll, false)
        XCTAssertEqual(changed.fontFamily?.rawValue, "ui-rounded")
        XCTAssertNotEqual(prefs.backgroundColor, changed.backgroundColor)
    }
}
