import XCTest

final class BrandUITests: XCTestCase {
    @MainActor private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset"] + arguments
        app.launch()
        return app
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func scrollTo(_ target: XCUIElement, app: XCUIApplication) {
        for _ in 0..<4 { if target.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(target.isHittable)
    }
    @MainActor private func revealTools(_ app: XCUIApplication) {
        if !app.buttons["reader.settings"].isHittable {
            let progress=element(app,"reader.compactProgress")
            if progress.isHittable { progress.tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        }
        XCTAssertTrue(app.buttons["reader.settings"].waitForExistence(timeout:5))
    }
    @MainActor func testEmptyBrandAndThreeTabs() {
        let app = launch()
        XCTAssertTrue(app.buttons["library.emptyImport"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["library.emptyImport"].isHittable)
        XCTAssertGreaterThan(app.staticTexts["library.title"].frame.width, 40)
        XCTAssertTrue(app.staticTexts["予盈"].exists)
        XCTAssertTrue(app.staticTexts["赠予盈盈的阅读时光"].exists)
        XCTAssertFalse(app.staticTexts["阅简"].exists)
        capture(app, "予盈-空书架")
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.textFields["搜索小说"].waitForExistence(timeout: 5))
        capture(app, "予盈-发现")
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["字体、排版与主题"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["予盈"].exists)
        capture(app, "予盈-我的")
        app.staticTexts["字体、排版与主题"].tap()
        XCTAssertTrue(app.buttons["settings.font"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["字体"].isHittable)
        XCTAssertTrue(app.staticTexts["字号"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["settings.font"].frame.minX, 0)
        XCTAssertLessThanOrEqual(app.buttons["settings.font"].frame.maxX, app.frame.width)
        capture(app, "予盈-阅读设置")
        let dark = app.buttons["settings.theme.dark"]; scrollTo(dark, app: app); dark.tap()
        capture(app, "予盈-深色阅读设置")
        app.navigationBars.buttons.firstMatch.tap()
        capture(app, "予盈-深色我的")
    }
    @MainActor func testTwoColumnCoversSearchAndListSwitch() {
        let app = launch(["--uitest-brand-library"])
        let first = element(app, "book.cover.荒野植被")
        let second = element(app, "book.cover.交易沦陷")
        XCTAssertTrue(first.waitForExistence(timeout: 20)); XCTAssertTrue(second.waitForExistence(timeout: 10))
        let ready = NSPredicate(format: "value == %@", "自然图案")
        expectation(for: ready, evaluatedWith: first); waitForExpectations(timeout: 15)
        XCTAssertEqual(first.frame.minY, second.frame.minY, accuracy: 2)
        XCTAssertLessThan(first.frame.maxX, second.frame.minX)
        XCTAssertTrue(app.staticTexts["已读 72%"].exists)
        XCTAssertTrue(app.staticTexts["已读 38%"].exists)
        capture(app, "予盈-双列书架")
        app.buttons["library.search"].tap()
        let search = app.textFields["library.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("荒野")
        XCTAssertTrue(app.staticTexts["荒野植被"].exists); XCTAssertFalse(app.staticTexts["交易沦陷"].exists)
        app.buttons["关闭搜索"].tap()
        app.buttons["library.options"].tap(); app.buttons["列表视图"].tap()
        XCTAssertTrue(app.staticTexts["交易沦陷"].waitForExistence(timeout: 5))
        XCTAssertLessThan(first.frame.maxY, second.frame.minY)
        capture(app, "予盈-列表书架")
    }
    @MainActor func testReaderFontThemeLiveChangeAndRestart() {
        let app = launch(["--uitest-seed", "--uitest-mode=slide"])
        let book = app.staticTexts["原创阅读测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.tap()
        let content = element(app, "reader.content")
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        let originalPageCount = app.staticTexts["reader.pageInfo"].label.components(separatedBy: "/").last
        revealTools(app)
        capture(app, "予盈-TXT阅读工具栏")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let before = content.value as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.45)).tap()
        expectation(for: NSPredicate { _, _ in (content.value as? String) != before }, evaluatedWith: nil)
        waitForExpectations(timeout: 8)
        capture(app, "予盈-TXT沉浸阅读")
        revealTools(app); app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.sliders["settings.fontSize"].waitForExistence(timeout: 5))
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition: 0.85)
        app.buttons["settings.font"].tap()
        XCTAssertTrue(app.buttons["settings.font.system"].waitForExistence(timeout: 5)); app.buttons["settings.font.system"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        let gray = app.buttons["settings.theme.gray"]; scrollTo(gray, app: app); gray.tap()
        capture(app, "予盈-字体与纸张设置")
        app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        let after = content.value as? String
        XCTAssertFalse((after ?? "").isEmpty)
        XCTAssertNotEqual(originalPageCount, app.staticTexts["reader.pageInfo"].label.components(separatedBy: "/").last)
        capture(app, "予盈-TXT设置实时生效")
        revealTools(app); app.buttons["返回书架"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 15)); book.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15)); XCTAssertEqual(content.value as? String, after)
    }
    @MainActor func testEPUBOriginalCoverReadingAndPreferences() {
        let app = launch(["--uitest-epub"])
        let cover = element(app, "book.cover.封面与排版测试")
        XCTAssertTrue(cover.waitForExistence(timeout: 20))
        expectation(for: NSPredicate(format: "value == %@", "书籍原封面"), evaluatedWith: cover); waitForExpectations(timeout: 20)
        capture(app, "予盈-EPUB原封面")
        app.staticTexts["封面与排版测试"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这是专为自动测试原创的短文")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 45))
        let heading = app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", "第一章 出发")).firstMatch
        XCTAssertTrue(heading.exists)
        XCTAssertLessThan(heading.frame.minY, app.frame.height * 0.3)
        XCTAssertLessThan(heading.frame.height, 40, "XHTML 章标题应应用舒适的标题样式")
        let originalTextHeight = text.frame.height
        capture(app, "予盈-EPUB阅读")
        revealTools(app); app.buttons["reader.settings"].tap()
        XCTAssertTrue(app.sliders["settings.fontSize"].waitForExistence(timeout: 5)); app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition: 0.85)
        let cream = app.buttons["settings.theme.cream"]; scrollTo(cream, app: app); cream.tap()
        app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 30))
        expectation(for: NSPredicate { _, _ in text.frame.height > originalTextHeight }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        capture(app, "予盈-EPUB排版与纸张生效")
        revealTools(app); app.buttons["reader.settings"].tap()
        let scroll = app.buttons["settings.mode.scroll"]
        scrollTo(scroll, app: app); scroll.tap()
        XCTAssertTrue(scroll.isSelected)
        app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 45))
        if app.buttons["reader.settings"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        app.webViews.firstMatch.swipeUp(); app.webViews.firstMatch.swipeDown()
        XCTAssertTrue(text.exists, "EPUB 连续滚动保留正文并可反向拖动")
        capture(app, "予盈-EPUB连续滚动")
        revealTools(app); app.buttons["返回书架"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["封面与排版测试"].firstMatch.waitForExistence(timeout: 15)); app.staticTexts["封面与排版测试"].firstMatch.tap()
        XCTAssertTrue(text.waitForExistence(timeout: 20))
    }
    @MainActor func testLaunchCompositionAndInstalledHomeName() {
        // Preview of the static launch design, without a delay in the real launch path.
        let app = launch(["--uitest-launch-preview"])
        XCTAssertTrue(app.staticTexts["予盈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["赠予盈盈的阅读时光"].exists)
        capture(app, "予盈-启动屏布局预览")
        app.terminate(); XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["予盈"].firstMatch
        for _ in 0..<3 { if icon.exists && icon.isHittable { break }; springboard.swipeLeft() }
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        XCTAssertFalse(springboard.icons["阅简"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "予盈-实际安装的桌面名称与图标"; shot.lifetime = .keepAlways; add(shot)
    }
}
