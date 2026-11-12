import XCTest

final class ReaderTests: XCTestCase {
    @MainActor private func open(mode: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-reset", "--uitest-seed", "--uitest-mode=" + mode]; app.launch()
        let book = app.staticTexts["原创阅读测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.tap()
        XCTAssertTrue(app.buttons["返回书架"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func content(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "reader.content").firstMatch
    }
    @MainActor func testSlideTurnBookmarkAndRestart() {
        let app = open(mode: "slide")
        var page = content(app); XCTAssertTrue(page.waitForExistence(timeout: 15))
        let before = page.value as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)).tap()
        let changed = NSPredicate { _, _ in (self.content(app).value as? String) != before }
        expectation(for: changed, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        page = content(app)
        let after = page.value as? String
        XCTAssertNotEqual(before, after)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        app.buttons["添加书签"].tap()
        app.buttons["返回书架"].tap()
        app.terminate(); app.launchArguments = ["--uitest-seed"]; app.launch()
        app.staticTexts["原创阅读测试"].firstMatch.tap()
        XCTAssertTrue(content(app).waitForExistence(timeout: 15))
        XCTAssertEqual(content(app).value as? String, after)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "TXT 阅读与位置恢复"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testCoverCancelledDragPreservesPageAndTurnChangesIt() {
        let app = open(mode: "cover")
        XCTAssertTrue(content(app).waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let before = content(app).value as? String
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.45))
        let short = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.45))
        start.press(forDuration: 0.1, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(content(app).value as? String, before)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)).tap()
        let changed = NSPredicate { _, _ in (self.content(app).value as? String) != before }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 5)
    }
    @MainActor func testCurlCanTurn() {
        let app = open(mode: "curl")
        XCTAssertTrue(content(app).waitForExistence(timeout: 15))
        let before = content(app).value as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)).tap()
        let changed = NSPredicate { _, _ in (self.content(app).value as? String) != before }
        expectation(for: changed, evaluatedWith: nil); waitForExpectations(timeout: 5)
    }
    @MainActor func testScrollAndChapterSelection() {
        let app = open(mode: "scroll")
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        table.swipeUp()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        app.buttons["目录"].tap()
        let chapter = app.buttons["第2章 测试"].firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 5)); chapter.tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let correctChapter = NSPredicate(format: "label == %@", "第2章 测试")
        expectation(for: correctChapter, evaluatedWith: app.staticTexts["reader.chapterTitle"])
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.tables.firstMatch.cells.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这是第2章")).firstMatch.exists)
    }
}
