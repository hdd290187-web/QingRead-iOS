import XCTest

final class DocumentImportTests: XCTestCase {
    private func requireProviderDiagnosticMode() throws {
        #if !SYSTEM_FILES_DIAGNOSTICS
        throw XCTSkip("HUMAN_PENDING: macOS runner FileProvider returned -1005 and empty URLs before the App callback. Native Files diagnostics remain available via workflow import_only=true; callback, real copy/parse and library UI have separate required tests.")
        #endif
    }
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-import-files"]
        app.launch()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 15))
        return app
    }
    @MainActor @discardableResult private func selectFile(_ name: String, app: XCUIApplication) -> Bool {
        app.buttons["library.import"].tap()
        let fileView = app.collectionViews["File View"]
        let folder = fileView.cells.matching(NSPredicate(format: "label BEGINSWITH %@", "导入测试,")).firstMatch
        let file = fileView.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", name + ",", (name as NSString).deletingPathExtension + ",")).firstMatch
        if !file.waitForExistence(timeout: 2) && !folder.exists {
            let browse = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览"])).firstMatch
            if browse.waitForExistence(timeout: 15) { browse.tap() }
            let local = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["On My iPhone", "在我的 iPhone 上", "在我的iPhone上"])).firstMatch
            if !local.waitForExistence(timeout: 3) {
                let back = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "浏览", "Locations", "位置"])).firstMatch
                if back.exists { back.tap() }
            }
            if local.waitForExistence(timeout: 5) { local.tap() }
            if !folder.exists {
                let appFolder = fileView.cells.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "阅简,", "QingRead,")).firstMatch
                if appFolder.waitForExistence(timeout: 10) { appFolder.tap() }
            }
        }
        if folder.waitForExistence(timeout: 10) { folder.tap() }
        guard file.waitForExistence(timeout: 15) else { XCTFail("系统 Files 选择器应展示 Documents 中的测试文件。\n" + app.debugDescription); return false }
        file.tap()
        let open = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Open", "打开"])).firstMatch
        if open.waitForExistence(timeout: 3) {
            let ready = NSPredicate(format: "enabled == true AND hittable == true")
            expectation(for: ready, evaluatedWith: open)
            waitForExpectations(timeout: 5)
            // Use one ordinary finger-length press through XCTest. Remote Files
            // controls can ignore a synthetic 50 ms event while transitioning.
            open.press(forDuration: 0.15)
        }
        return true
    }
    @MainActor func testSystemFilesTXTImportRefreshDuplicateAndRestartRead() throws {
        try requireProviderDiagnosticMode()
        let app = launch()
        guard selectFile("系统文件测试.txt", app: app) else { return }
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
        guard selectFile("系统文件测试.txt", app: app) else { return }
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("阅读进度已保留"), app.staticTexts["import.result.message"].label)
        done.tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.staticTexts["系统文件测试"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["系统文件测试"].firstMatch.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        XCTAssertTrue((content.value as? String)?.contains("系统文件选择器") ?? false)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "系统Files导入TXT后重启可读"; image.lifetime = .keepAlways; add(image)
    }
    @MainActor func testSystemFilesEPUBAndEmptyFileFeedback() throws {
        try requireProviderDiagnosticMode()
        let app = launch()
        guard selectFile("空白文件.txt", app: app) else { return }
        let done = app.buttons["import.result.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 20))
        let message = app.staticTexts["import.result.message"].label
        XCTAssertTrue(message.contains("文件为空")); XCTAssertTrue(message.contains("错误码"))
        XCTAssertTrue(app.buttons["import.copyError"].exists)
        done.tap()
        guard selectFile("原创测试书.epub", app: app) else { return }
        XCTAssertTrue(done.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("已加入"))
        done.tap()
        XCTAssertTrue(app.staticTexts["原创测试书"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testSystemPickerCancelCanReopen() throws {
        try requireProviderDiagnosticMode()
        let app = launch()
        app.buttons["library.import"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["import.copyError"].exists)
        guard selectFile("系统文件测试.txt", app: app) else { return }
        XCTAssertTrue(app.buttons["import.result.done"].waitForExistence(timeout: 20))
    }
}
