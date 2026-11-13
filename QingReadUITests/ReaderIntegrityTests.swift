import XCTest

final class ReaderIntegrityTests: XCTestCase {
    @MainActor private func snapshot(_ table: XCUIElement) -> [String: Any] {
        var result: [String: Any] = [:]
        let ready = NSPredicate { _, _ in
            guard let data = table.label.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chapter = value["chapter"] as? Int, let offset = value["offset"] as? Int else { return false }
            result = value
            return table.value as? String == "\(chapter):\(offset)"
        }
        expectation(for: ready, evaluatedWith: nil); waitForExpectations(timeout: 15)
        return result
    }
    @MainActor private func verify(_ state: [String: Any], table: XCUIElement) {
        let chapter = state["chapter"] as? Int ?? -99
        XCTAssertEqual(state["anchorFailures"] as? Int, 0, "窗口更新不能改变可见字形锚点")
        XCTAssertEqual(state["drawnFixtureChapter"] as? Int, chapter, "真实 TextKit cell 内容必须属于报告的章节")
        XCTAssertLessThanOrEqual(abs((state["drawnOffset"] as? Int ?? -100) - (state["offset"] as? Int ?? 0)), 3)
        let mounted = state["mountedChapters"] as? [Int] ?? []
        if let first = mounted.first, let last = mounted.last { XCTAssertEqual(mounted, Array(first...last)) }
        // Inspect the actually visible canvas text and frame, independently of
        // the controller's persisted progression and structured diagnostics.
        let origin = CGPoint(x: table.frame.midX, y: table.frame.minY + 8.5)
        let canvases = table.descendants(matching: .any).matching(identifier: "reader.scrollContent").allElementsBoundByIndex
        let visible = canvases.first { $0.frame.contains(origin) }
        XCTAssertNotNil(visible, "正文起点必须有真实可见的绘制 cell")
        XCTAssertTrue((visible?.value as? String ?? "").contains("样本章节\(chapter + 1)）"))
    }
    @MainActor private func exercise(_ fixture: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-integrity=" + fixture, "--reader-integrity"]
        app.launch()
        let book = app.staticTexts["滚动顺序回归样本"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 45)); book.tap()
        let table = app.tables.matching(identifier: "reader.scrollViewport").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 45))
        var previous = snapshot(table); verify(previous, table: table)
        for direction in [true, false, true, false] {
            for _ in 0..<(direction ? 24 : 16) {
                if direction { table.swipeUp(velocity: .fast) } else { table.swipeDown(velocity: .fast) }
                let next = snapshot(table); verify(next, table: table)
                let pixels = (next["worldY"] as? Double ?? 0) - (previous["worldY"] as? Double ?? 0)
                let characters = (next["globalOffset"] as? Int ?? 0) - (previous["globalOffset"] as? Int ?? 0)
                if direction { XCTAssertGreaterThanOrEqual(characters, -96) }
                else { XCTAssertLessThanOrEqual(characters, 96) }
                XCTAssertLessThanOrEqual(Double(abs(characters)), abs(pixels) * 3 + 160, "字符跨度必须与实际纸面位移相符，不能瞬移章节")
                previous = next
            }
        }
        XCUIDevice.shared.press(.home); app.activate()
        let resumed = snapshot(table)
        XCTAssertEqual(resumed["globalOffset"] as? Int, previous["globalOffset"] as? Int)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout: 5)); app.buttons["reader.settings"].tap()
        let originalAnchor = resumed["globalOffset"] as? Int ?? 0
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition: 0.55)
        app.buttons["settings.font"].tap()
        app.buttons["settings.font.system"].tap(); app.navigationBars.buttons.firstMatch.tap()
        let relaxed = app.buttons["settings.line.12"]
        for _ in 0..<5 { if relaxed.isHittable { break }; app.swipeUp() }
        relaxed.tap(); app.buttons["reader.settings.done"].tap()
        let reflowed = snapshot(table); verify(reflowed, table: table)
        XCTAssertLessThanOrEqual(abs((reflowed["globalOffset"] as? Int ?? 0) - originalAnchor), 64)
        table.swipeUp(velocity: .fast)
        let saved = snapshot(table); verify(saved, table: table)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap() }
        app.buttons["返回书架"].tap(); app.terminate()
        app.launchArguments = ["--reader-integrity"]; app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap()
        XCTAssertTrue(table.waitForExistence(timeout: 30))
        let reopened = snapshot(table); verify(reopened, table: table)
        XCTAssertEqual(reopened["globalOffset"] as? Int, saved["globalOffset"] as? Int)
    }
    @MainActor func testShortBookEightyFastFlingReversalsAndReopen() { exercise("short") }
    @MainActor func testNinetySixChaptersEightyFastFlingReversalsAndReopen() { exercise("long") }
    @MainActor func testMonolithEightyFastFlingReversalsAndReopen() { exercise("monolith") }
}
