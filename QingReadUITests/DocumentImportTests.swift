import XCTest

final class DocumentImportTests: XCTestCase {
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-import-files"]
        app.launch()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor private func selectFile(_ name: String, app: XCUIApplication) {
        app.buttons["library.import"].tap()
        let folder = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "导入测试,")).firstMatch
        if folder.waitForExistence(timeout: 3) { folder.tap() }
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", name, (name as NSString).deletingPathExtension)).firstMatch
        guard file.waitForExistence(timeout: 15) else { XCTFail("系统 Files 选择器应展示 Documents 中的测试文件。\n" + app.debugDescription); return }
        file.tap()
        let open = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "打开"])).firstMatch
        if open.waitForExistence(timeout: 2), open.isEnabled { open.tap() }
    }
    @MainActor func testSystemFilesTXTImportRefreshDuplicateAndRestartRead() {
        let app = launch()
        selectFile("系统文件测试.txt", app: app)
        let done = app.buttons["import.result.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("系统文件测试"))
        done.tap()
        let book = app.staticTexts["系统文件测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.tap()
        let content = app.descendants(matching: .any).matching(identifier: "reader.content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        XCTAssertTrue((content.value as? String)?.contains("系统文件选择器") ?? false)
        app.buttons["返回书架"].tap()
        selectFile("系统文件测试.txt", app: app)
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("阅读进度已保留"))
        done.tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["系统文件测试"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["系统文件测试"].firstMatch.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        XCTAssertTrue((content.value as? String)?.contains("系统文件选择器") ?? false)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "系统Files导入TXT后重启可读"; image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testSystemFilesEPUBAndEmptyFileFeedback() {
        let app = launch()
        selectFile("空白文件.txt", app: app)
        let done = app.buttons["import.result.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        let message = app.staticTexts["import.result.message"].label
        XCTAssertTrue(message.contains("文件为空")); XCTAssertTrue(message.contains("错误码"))
        XCTAssertTrue(app.buttons["import.copyError"].exists)
        done.tap()
        selectFile("原创测试书.epub", app: app)
        XCTAssertTrue(done.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("已加入"))
        done.tap()
        XCTAssertTrue(app.staticTexts["原创测试书"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testSystemPickerCancelCanReopen() {
        let app = launch()
        app.buttons["library.import"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["import.copyError"].exists)
        selectFile("系统文件测试.txt", app: app)
        XCTAssertTrue(app.buttons["import.result.done"].waitForExistence(timeout: 20))
    }
}
