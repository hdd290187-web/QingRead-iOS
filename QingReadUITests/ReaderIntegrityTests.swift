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
        let lineStart=state["lineStart"] as? Int ?? -1
        let lineEnd=state["lineEnd"] as? Int ?? -1
        let drawn=state["drawnOffset"] as? Int ?? -1
        XCTAssertEqual(lineStart,state["offset"] as? Int)
        XCTAssertGreaterThanOrEqual(drawn,lineStart,"字形命中必须落在 viewport 顶部的真实 TextKit 行中")
        XCTAssertLessThan(drawn,lineEnd)
        XCTAssertLessThanOrEqual(abs(drawn-lineStart),16,"实际字形命中必须仍位于阅读器所报告的同一行")
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
    @MainActor private func settled(_ table: XCUIElement) -> [String:Any] {
        var latest=snapshot(table); var stableSince=ProcessInfo.processInfo.systemUptime
        for _ in 0..<30 {
            Thread.sleep(forTimeInterval:0.1)
            let next=snapshot(table)
            let same=next["worldY"] as? Double == latest["worldY"] as? Double && next["globalOffset"] as? Int == latest["globalOffset"] as? Int
            if same && ProcessInfo.processInfo.systemUptime-stableSince>=0.3 { return next }
            if !same { stableSince=ProcessInfo.processInfo.systemUptime }
            latest=next
        }
        return latest
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
                XCTAssertEqual(next["generation"] as? Int, previous["generation"] as? Int, "正常甩动不得偷偷重建或恢复到其他章节")
                let pixels = (next["worldY"] as? Double ?? 0) - (previous["worldY"] as? Double ?? 0)
                let characters = (next["globalOffset"] as? Int ?? 0) - (previous["globalOffset"] as? Int ?? 0)
                if direction { XCTAssertGreaterThanOrEqual(characters, -96) }
                else { XCTAssertLessThanOrEqual(characters, 96) }
                XCTAssertLessThanOrEqual(Double(abs(characters)), abs(pixels) * 3 + 160, "字符跨度必须与实际纸面位移相符，不能瞬移章节")
                previous = next
            }
        }
        if fixture == "long" {
            // Exercise the actual progress slider too: its controls must not be
            // intercepted by the compact footer's new menu gesture.
            app.coordinate(withNormalizedOffset: CGVector(dx:0.5,dy:0.3)).tap()
            let slider=app.sliders["阅读进度"]
            XCTAssertTrue(slider.waitForExistence(timeout:5));slider.adjust(toNormalizedSliderPosition:1)
            expectation(for:NSPredicate { _,_ in
                guard let data=table.label.data(using:.utf8),let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return false }
                return value["chapter"] as? Int == 95 && (table.value as? String ?? "").hasPrefix("95:")
            },evaluatedWith:nil);waitForExpectations(timeout:30)
            previous=snapshot(table);verify(previous,table:table)
            XCTAssertEqual(previous["chapter"] as? Int,95)
            for direction in [true,false] {
                for _ in 0..<8 {
                    if direction { table.swipeUp(velocity:.fast) } else { table.swipeDown(velocity:.fast) }
                    let next=snapshot(table);verify(next,table:table)
                    XCTAssertEqual(next["generation"] as? Int,previous["generation"] as? Int)
                    let distance=(next["worldY"] as? Double ?? 0)-(previous["worldY"] as? Double ?? 0)
                    let characters=(next["globalOffset"] as? Int ?? 0)-(previous["globalOffset"] as? Int ?? 0)
                    XCTAssertLessThanOrEqual(Double(abs(characters)),abs(distance)*3+160)
                    if direction { XCTAssertGreaterThanOrEqual(characters,-96) } else { XCTAssertLessThanOrEqual(characters,96) }
                    previous=next
                }
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
        expectation(for:NSPredicate { _,_ in
            guard let data=table.label.data(using:.utf8),let state=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return false }
            return (state["fontSize"] as? Double ?? 0)>=25 && state["lineSpacing"] as? Double == 12 && !(state["fontName"] as? String ?? "Noto").contains("Noto")
        },evaluatedWith:nil);waitForExpectations(timeout:30)
        let reflowed = snapshot(table); verify(reflowed, table: table)
        XCTAssertLessThanOrEqual(abs((reflowed["globalOffset"] as? Int ?? 0) - originalAnchor), 64)
        table.swipeUp(velocity: .fast)
        let saved = settled(table); verify(saved, table: table)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap() }
        app.buttons["返回书架"].tap(); app.terminate()
        app.launchArguments = ["--reader-integrity"]; app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap()
        XCTAssertTrue(table.waitForExistence(timeout: 30))
        let reopened = settled(table); verify(reopened, table: table)
        XCTAssertEqual(reopened["globalOffset"] as? Int, saved["globalOffset"] as? Int)
    }
    @MainActor func testShortBookEightyFastFlingReversalsAndReopen() { exercise("short") }
    @MainActor func testNinetySixChaptersEightyFastFlingReversalsAndReopen() { exercise("long") }
    @MainActor func testMonolithEightyFastFlingReversalsAndReopen() { exercise("monolith") }
}
