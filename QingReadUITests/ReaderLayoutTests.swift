import XCTest

final class ReaderLayoutTests: XCTestCase {
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func reveal(_ app: XCUIApplication) {
        if !app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
    }
    @MainActor func testAllModesImmersionOverlayAndLandscape() {
        defer { XCUIDevice.shared.orientation = .portrait }
        for mode in ["slide", "cover", "curl", "scroll"] {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            app.launchArguments = ["--uitest-reset", "--uitest-seed", "--uitest-mode=" + mode]
            app.launch()
            let book = app.staticTexts["原创阅读测试"].firstMatch
            XCTAssertTrue(book.waitForExistence(timeout: 20)); book.tap()
            let viewport = mode == "scroll" ? app.tables.firstMatch : app.descendants(matching: .any).matching(identifier: "reader.content").firstMatch
            XCTAssertTrue(viewport.waitForExistence(timeout: 30))
            XCTAssertFalse(app.buttons["返回书架"].exists, "新阅读会话默认沉浸式")
            let beforeFrame = viewport.frame
            let beforeText = mode == "scroll" ? app.textViews.firstMatch.value as? String : viewport.value as? String
            attach(app, mode + "-竖屏沉浸")
            reveal(app)
            XCTAssertTrue(app.buttons["返回书架"].isHittable)
            XCTAssertEqual(viewport.frame, beforeFrame)
            XCTAssertEqual(mode == "scroll" ? app.textViews.firstMatch.value as? String : viewport.value as? String, beforeText)
            attach(app, mode + "-浮层工具栏")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(viewport.waitForExistence(timeout: 15))
            expectation(for: NSPredicate { _, _ in viewport.frame.width > viewport.frame.height }, evaluatedWith: nil)
            waitForExpectations(timeout: 10)
            XCTAssertGreaterThanOrEqual(viewport.frame.minX, 0)
            XCTAssertLessThanOrEqual(viewport.frame.maxY, app.frame.maxY)
            attach(app, mode + "-横屏沉浸")
            XCUIDevice.shared.orientation = .portrait
            reveal(app); app.buttons["返回书架"].tap()
            app.terminate()
        }
    }
    @MainActor func testChapterBoundaryFontChangeAndBackgroundRestore() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-seed", "--uitest-mode=slide"]
        app.launch()
        let book = app.staticTexts["原创阅读测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.tap()
        let content = app.descendants(matching: .any).matching(identifier: "reader.content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 20))
        reveal(app); app.buttons["下一章"].tap()
        expectation(for: NSPredicate(format: "label == %@", "第2章 测试"), evaluatedWith: app.staticTexts["reader.chapterTitle"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue((content.value as? String)?.contains("第2章") ?? false)
        // Backward at the first page crosses to the previous chapter's last page.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.45)).tap()
        expectation(for: NSPredicate(format: "label == %@", "第1章 测试"), evaluatedWith: app.staticTexts["reader.chapterTitle"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse((content.value as? String ?? "").isEmpty)
        let numbers = content.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let anchor = numbers.count >= 3 ? numbers[numbers.count - 2] : 0
        reveal(app); app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.sliders["settings.fontSize"].waitForExistence(timeout: 5))
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition: 0.65)
        app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        let reflowRange = content.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertGreaterThanOrEqual(reflowRange.count, 3)
        if reflowRange.count >= 3 {
            XCTAssertLessThanOrEqual(reflowRange[reflowRange.count - 2], anchor)
            XCTAssertGreaterThan(reflowRange[reflowRange.count - 1], anchor)
        }
        let reflowed = content.value as? String
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(content.waitForExistence(timeout: 10)); XCTAssertEqual(content.value as? String, reflowed)
        attach(app, "跨章-字号-后台恢复")
        reveal(app); app.buttons["返回书架"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15)); XCTAssertEqual(content.value as? String, reflowed)
    }
}
