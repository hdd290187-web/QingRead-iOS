import XCTest

final class ReaderLayoutTests: XCTestCase {
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func reveal(_ app: XCUIApplication) {
        if !app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
    }
    @MainActor private func scrollAnchor(_ table: XCUIElement) -> (chapter: Int, offset: Int) {
        let parts = (table.value as? String ?? "").split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2, "滚动视口必须提供实际提交的字符锚点")
        return (parts.first ?? -1, parts.last ?? -1)
    }
    @MainActor private func scrollTo(_ element: XCUIElement, app: XCUIApplication) {
        let container=app.descendants(matching:.any).matching(identifier:"settings.form.scroll").firstMatch
        for _ in 0..<8 {
            let top=(app.navigationBars.allElementsBoundByIndex.filter { $0.isHittable }.map { $0.frame.maxY }.max() ?? 0)+12
            if element.isHittable && element.frame.midY>top { break }
            if element.exists && element.frame.midY<=top { container.swipeDown(velocity:.slow) }
            else { container.swipeUp(velocity:.slow) }
        }
        XCTAssertTrue(element.isHittable)
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
            let beforeText = mode == "scroll" ? app.descendants(matching: .any).matching(identifier: "reader.scrollContent").firstMatch.value as? String : viewport.value as? String
            attach(app, mode + "-竖屏沉浸")
            reveal(app)
            XCTAssertTrue(app.buttons["返回书架"].isHittable)
            XCTAssertEqual(viewport.frame, beforeFrame)
            XCTAssertEqual(mode == "scroll" ? app.descendants(matching: .any).matching(identifier: "reader.scrollContent").firstMatch.value as? String : viewport.value as? String, beforeText)
            attach(app, mode + "-浮层工具栏")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(viewport.waitForExistence(timeout: 15))
            var stableFrame = CGRect.null
            var stableText: String?
            var stableSince = ProcessInfo.processInfo.systemUptime
            expectation(for: NSPredicate { _, _ in
                let frame = viewport.frame, text = viewport.value as? String
                guard frame.width > frame.height else { return false }
                if frame != stableFrame || text != stableText {
                    stableFrame = frame; stableText = text; stableSince = ProcessInfo.processInfo.systemUptime
                    return false
                }
                return ProcessInfo.processInfo.systemUptime - stableSince >= 0.7
            }, evaluatedWith: nil)
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

        reveal(app); app.buttons["reader.settings"].tap()
        let scrollMode = app.buttons["settings.mode.scroll"]
        scrollTo(scrollMode, app: app); scrollMode.tap()
        app.buttons["reader.settings.done"].tap()
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        if app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        let initial = table.value as? String
        table.swipeUp()
        expectation(for: NSPredicate { _, _ in (table.value as? String) != initial }, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        let scrollBefore = scrollAnchor(table)

        reveal(app); app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.sliders["settings.fontSize"].waitForExistence(timeout: 5))
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition: 0.35)
        let relaxed = app.buttons["settings.line.12"]
        scrollTo(relaxed, app: app); relaxed.tap()
        let cream = app.buttons["settings.theme.cream"]
        scrollTo(cream, app: app); cream.tap()
        app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let scrollAfter = scrollAnchor(table)
        XCTAssertEqual(scrollAfter.chapter, scrollBefore.chapter)
        XCTAssertLessThanOrEqual(scrollAfter.offset, scrollBefore.offset)
        XCTAssertLessThanOrEqual(scrollBefore.offset - scrollAfter.offset, 40, "字号和行距重排应恢复到原锚点所在行")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(scrollAnchor(table).offset, scrollAfter.offset)
        attach(app, "滚动-字号行距主题-字符锚点恢复")
        reveal(app); app.buttons["返回书架"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap()
        XCTAssertTrue(table.waitForExistence(timeout: 15))
        let reopened = scrollAnchor(table)
        XCTAssertEqual(reopened.chapter, scrollAfter.chapter)
        XCTAssertEqual(reopened.offset, scrollAfter.offset)
    }
}
