import XCTest

// These tests start at the picker callback boundary, then execute the real
// coordinated copy, parser, transaction, library publisher and result views.
// They do not claim to validate iCloud/File Provider delivery into that callback.
final class ImportFeedbackTests: XCTestCase {
    @MainActor private func launch(_ mode: String, reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (reset ? ["--uitest-reset"] : []) + ["--uitest-import-files", "--uitest-import-result=" + mode]
        app.launch()
        return app
    }
    @MainActor func testSelectedURLCopiesPublishesAndSurvivesRestart() {
        let app = launch("selected")
        XCTAssertTrue(app.buttons["import.result.done"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("已加入"))
        app.buttons["import.result.done"].tap()
        let book = app.staticTexts["系统文件测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5)); book.tap()
        let content = app.descendants(matching: .any).matching(identifier: "reader.content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        XCTAssertTrue((content.value as? String)?.contains("系统文件选择器") ?? false)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        app.buttons["返回书架"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(book.waitForExistence(timeout: 10)); book.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        XCTAssertTrue((content.value as? String)?.contains("原创正文") ?? false)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "回调后真实导入及重启读取"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testFailureCallbackShowsStageCodeAndCopyAction() {
        let app = launch("failure")
        XCTAssertTrue(app.buttons["import.result.done"].waitForExistence(timeout: 15))
        let message = app.staticTexts["import.result.message"].label
        XCTAssertTrue(message.contains("选择文件")); XCTAssertTrue(message.contains("257"))
        XCTAssertTrue(message.contains("重新选择")); XCTAssertTrue(app.buttons["import.copyError"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "导入权限失败阶段与错误码"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["import.result.done"].tap()
        XCTAssertTrue(app.buttons["import.showResult"].waitForExistence(timeout: 5))
        app.buttons["import.showResult"].tap()
        XCTAssertTrue(app.buttons["import.copyError"].waitForExistence(timeout: 5))
    }
    @MainActor func testEmptySelectionShowsAdvice() {
        let app = launch("empty")
        XCTAssertTrue(app.buttons["import.result.done"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("没有返回文件"))
        XCTAssertTrue(app.staticTexts["import.result.message"].label.contains("重新点击加号"))
    }
    @MainActor func testPartialBatchKeepsGoodBookAndShowsBadFile() {
        let app = launch("partial")
        XCTAssertTrue(app.buttons["import.result.done"].waitForExistence(timeout: 20))
        let message = app.staticTexts["import.result.message"].label
        XCTAssertTrue(message.contains("已加入 1 本")); XCTAssertTrue(message.contains("文件为空"))
        app.buttons["import.result.done"].tap()
        XCTAssertTrue(app.staticTexts["系统文件测试"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testCancellationIsNormalAndNativePickerCanCancel() {
        let app = launch("cancel")
        XCTAssertTrue(app.staticTexts["import.status"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["import.status"].label, "已取消导入")
        XCTAssertFalse(app.buttons["import.copyError"].exists)
        app.buttons["library.import"].tap()
        let cancel = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        // The hosted simulator cold-starts Files/FileProvider on its first use.
        // Build 39 exposed a real Cancel control only after the old 15s window.
        XCTAssertTrue(cancel.waitForExistence(timeout: 60)); cancel.tap()
        XCTAssertTrue(app.buttons["library.import"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["import.copyError"].exists)
    }
}
