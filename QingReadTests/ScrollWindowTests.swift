import XCTest
import UIKit
@testable import QingRead

@MainActor final class ScrollWindowTests: XCTestCase {
    func testOutOfOrderPreloadsNeverSkipMissingChapters() {
        var available: Set<Int> = [40]
        var mounted = [40]
        for chapter in [42, 38, 43, 39, 41, 44] {
            available.insert(chapter)
            mounted = ScrollWindow.chapters(available: available, mounted: mounted, anchor: 40, visible: [40], deferRebase: true)
            XCTAssertEqual(mounted, Array(40...(mounted.last ?? 40)))
            if chapter != 41 && !available.contains(41) { XCTAssertEqual(mounted, [40]) }
        }
        XCTAssertEqual(mounted, [40, 41, 42, 43, 44])
        // The Build 43 union/sort would expose 42 directly after 40 here.
        XCTAssertNotEqual([40, 42], ScrollWindow.chapters(available: [40, 42], mounted: [40], anchor: 40, visible: [40], deferRebase: true))
    }
    func testWindowRetainsEveryVisibleChapterAndDefersPrependPrune() {
        let available = Set(0...99)
        let moving = ScrollWindow.chapters(available: Set(20...29), mounted: Array(22...27), anchor: 26, visible: [26, 27], deferRebase: true)
        XCTAssertEqual(moving, Array(22...29))
        let idle = ScrollWindow.chapters(available: available, mounted: moving, anchor: 26, visible: Set(26...31), deferRebase: false)
        XCTAssertEqual(idle, Array(24...31))
        XCTAssertEqual(ScrollWindow.chapters(available: [0, 1], mounted: [40], anchor: 40, visible: [40], deferRebase: false), [40])
    }
    func testActualVisibleGlyphStaysFixedAcrossPrependPruneAndStaleCompletion() async throws {
        let library = LibraryStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: library.root) }
        library.settings.mode = .scroll
        var layouts: [Int: ScrollChapterLayout] = [:]
        var chapters: [Chapter] = []
        for index in 0..<12 {
            let text = "第\(index + 1)章\n" + (1...20).map { "原创段落\($0)（样本章节\(index + 1)）。用于验证真实字形与稳定行身份。\n\n" }.joined()
            chapters.append(Chapter(title: "第\(index + 1)章", length: text.utf16.count))
            layouts[index] = try await ReaderLayoutWorker.shared.prepare(text: text, size: CGSize(width: 337, height: 715), width: 393, settings: library.settings, title: nil, foreground: .black).scroll
        }
        let book = library.add(Book(title: "合成锚点回归", format: .txt, chapters: chapters))
        let controller = NativeReaderController(session: ReaderSession(book: book, library: library), settings: library.settings)
        try controller.installIntegrityFixture([5: try XCTUnwrap(layouts[5]), 6: try XCTUnwrap(layouts[6])], at: ReadingPosition(chapter: 5, characterOffset: 100))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 731)); window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.layoutIfNeeded()
        let before = try XCTUnwrap(controller.integritySnapshot())
        XCTAssertTrue(JSONSerialization.isValidJSONObject(before))
        XCTAssertEqual(before["drawnFixtureChapter"] as? Int, 5)
        let generation = controller.integrityGeneration
        for chapter in [3, 7, 4, 2, 8] {
            controller.completeIntegrityPreload(try XCTUnwrap(layouts[chapter]), chapter: chapter, generation: generation)
            let after = try XCTUnwrap(controller.integritySnapshot())
            XCTAssertEqual(after["rowID"] as? String, before["rowID"] as? String)
            XCTAssertEqual(after["drawnOffset"] as? Int, before["drawnOffset"] as? Int)
            XCTAssertEqual(after["anchorFailures"] as? Int, 0)
        }
        XCTAssertGreaterThanOrEqual(controller.integritySnapshot()?["mutations"] as? Int ?? 0, 2)
        controller.completeIntegrityPreload(try XCTUnwrap(layouts[0]), chapter: 0, generation: generation - 1)
        XCTAssertEqual(controller.integritySnapshot()?["staleResultsDiscarded"] as? Int, 1)
        controller.viewWillDisappear(false)
        controller.completeIntegrityPreload(try XCTUnwrap(layouts[0]), chapter: 0, generation: generation)
        XCTAssertEqual(controller.integritySnapshot()?["staleResultsDiscarded"] as? Int, 2)
        XCTAssertEqual(controller.integritySnapshot()?["rowID"] as? String, before["rowID"] as? String)
        controller.viewDidAppear(false)
        // Repeated real UITableView transactions, independently checking TextKit
        // hit testing against cached line anchors after direction reversals.
        for step in 0..<100 {
            let y = CGFloat(60 + (step % 9) * 45)
            controller.setIntegrityViewport(y: y, deferringRebase: step % 2 == 0)
            let value = try XCTUnwrap(controller.integritySnapshot())
            let logical = try XCTUnwrap(value["offset"] as? Int)
            let drawn = try XCTUnwrap(value["drawnOffset"] as? Int)
            XCTAssertLessThanOrEqual(abs(logical - drawn), 3)
            XCTAssertEqual(value["anchorFailures"] as? Int, 0)
        }
    }
    func testMissingPreparedAnchorNeverFallsBackToChapterZero() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library=LibraryStore(rootURL:root);library.settings.mode = .scroll
        let book=library.add(Book(title:"保留锚点",format:.txt,chapters:(0..<8).map { Chapter(title:"第\($0+1)章",length:1000) }))
        let position=ReadingPosition(chapter:5,characterOffset:123,progression:0.65)
        library.update(position:position,for:book)
        let session=ReaderSession(book:book,library:library)
        let controller=NativeReaderController(session:session,settings:library.settings)
        XCTAssertThrowsError(try controller.installIntegrityFixture([:],at:position))
        XCTAssertEqual(session.position.chapter,5)
        XCTAssertEqual(library.position(for:book).characterOffset,123)
        XCTAssertNil(controller.integritySnapshot())
    }
}
