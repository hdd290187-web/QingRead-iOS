import XCTest
import UIKit
import CoreFoundation
@testable import QingRead

final class CoreTests: XCTestCase {
    func testUTF8AndUTF16AndGB18030() throws {
        let text = "第一章 春天\n你好，世界。𠮷😊\n第二章 夜色\n中文阅读。"
        XCTAssertEqual(try TXTParser.decode(Data(text.utf8)).text, text)
        XCTAssertEqual(try TXTParser.decode(XCTUnwrap(text.data(using: .utf16))).text, text)
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let legacy = "第一章 春天\n中文测试"
        XCTAssertEqual(try TXTParser.decode(XCTUnwrap(legacy.data(using: String.Encoding(rawValue: gb)))).text, legacy)
    }
    func testChapterSplitPreservesEveryCharacter() throws {
        let text = "前言\n第一章 起点\n正文😊。\n第二章 归来\n结束。"
        let sections = try TXTParser.sections(from: text, title: "书")
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.map(\.text).joined(), text)
    }
    func testEmptyAndUnchapteredAndLargeText() throws {
        XCTAssertThrowsError(try TXTParser.sections(from: " \n", title: "空"))
        let text = String(repeating: "中文𠮷😊。\n", count: 18000)
        let sections = try TXTParser.sections(from: text, title: "大书")
        XCTAssertGreaterThan(sections.count, 2)
        XCTAssertEqual(sections.map(\.text).joined(), text)
        XCTAssertTrue(sections.allSatisfy { $0.text.utf16.count < TXTParser.chunkLimit + 8 })
    }
    @MainActor func testCoreTextPageCoverageAndReflow() {
        let text = String(repeating: "这是中文排版测试，包含 emoji 😊 和扩展汉字𠮷。\n\n", count: 180)
        var settings = ReaderSettings()
        let original = TextPaginator.layout(text, size: CGSize(width: 310, height: 600), settings: settings)
        XCTAssertGreaterThan(original.ranges.count, 1)
        XCTAssertEqual(original.ranges.first?.start, 0)
        XCTAssertEqual(original.ranges.last?.end, text.utf16.count)
        for pair in zip(original.ranges, original.ranges.dropFirst()) { XCTAssertEqual(pair.0.end, pair.1.start) }
        settings.fontSize = 30
        let reflow = TextPaginator.layout(text, size: CGSize(width: 310, height: 600), settings: settings)
        let anchor = original.ranges[2].start
        let range = reflow.ranges[reflow.page(containing: anchor)]
        XCTAssertLessThanOrEqual(range.start, anchor)
        XCTAssertGreaterThan(range.end, anchor)
    }
    func testPositionRoundTrip() throws {
        let position = ReadingPosition(chapter: 3, characterOffset: 512, locatorJSON: "{\"href\":\"chapter.xhtml\"}", progression: 0.42)
        XCTAssertEqual(try JSONDecoder().decode(ReadingPosition.self, from: JSONEncoder().encode(position)), position)
    }
}

extension CoreTests {
    @MainActor func testFontAndTextKitCharacterAnchor() {
        var settings = ReaderSettings(); settings.font = .serif
        XCTAssertTrue(settings.uiFont.familyName.contains("Noto"))
        let cell = ScrollTextCell(style: .default, reuseIdentifier: nil)
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 900)
        let text = String(repeating: "这是段落中的中文文字。\n", count: 12)
        cell.configure(text: TextPaginator.attributed(text, settings: settings), settings: settings)
        cell.layoutIfNeeded()
        let y = cell.y(for: 40)
        let offset = cell.character(at: CGPoint(x: settings.sidePadding, y: y + 3))
        XCTAssertLessThanOrEqual(abs(offset - 40), 18)
    }
}
