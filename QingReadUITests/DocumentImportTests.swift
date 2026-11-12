import XCTest

final class DocumentImportTests: XCTestCase {
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
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in file.exists || (folder.exists && folder.isHittable) }, object: nil)
        guard XCTWaiter.wait(for: [ready], timeout: 20) == .completed else {
            XCTFail("等待系统 Files 完成首次加载失败。\n" + app.debugDescription); return false
        }
        if folder.exists && folder.isHittable { folder.tap() }
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
    @MainActor func testSystemFilesTXTImportRefreshDuplicateAndRestartRead() {
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
    @MainActor func testSystemFilesEPUBAndEmptyFileFeedback() {
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
    @MainActor func testSystemPickerCancelCanReopen() {
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
