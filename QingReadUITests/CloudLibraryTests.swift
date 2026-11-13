import XCTest

final class CloudLibraryTests: XCTestCase {
    private let id = "B67F5B15-2DA2-4099-A9B8-579A9342531A"
    @MainActor private func discover(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["发现"].waitForExistence(timeout: 20)); app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.segmentedControls["discover.section"].waitForExistence(timeout: 10))
        app.segmentedControls["discover.section"].buttons["云书库"].tap()
    }
    @MainActor private func closeReader(_ app: XCUIApplication) {
        if !app.buttons["返回书架"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        XCTAssertTrue(app.buttons["返回书架"].waitForExistence(timeout: 10)); app.buttons["返回书架"].tap()
    }
    @MainActor func testCloudDownloadAutomaticallyOpensExistingReaderAndReadsOffline() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-reset", "--uitest-cloud"]; app.launch(); discover(app)
        let row = app.buttons["cloud.open." + id]; XCTAssertTrue(row.waitForExistence(timeout: 20)); row.tap()
        let content = app.descendants(matching: .any).matching(identifier: "reader.content").firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30)); closeReader(app)
        XCTAssertTrue(app.staticTexts["已下载，可离线阅读"].firstMatch.waitForExistence(timeout: 10))
        row.tap(); XCTAssertTrue(content.waitForExistence(timeout: 15)); closeReader(app)
        app.tabBars.buttons["书架"].tap()
        XCTAssertTrue(app.staticTexts["云端来信测试"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "云端来信测试")).count, 1)
        app.terminate(); app.launchArguments = ["--uitest-cloud", "--uitest-cloud-offline"]; app.launch()
        let local = app.staticTexts["云端来信测试"].firstMatch
        XCTAssertTrue(local.waitForExistence(timeout: 20)); local.tap()
        XCTAssertTrue(content.waitForExistence(timeout: 20)); closeReader(app)
        discover(app)
        XCTAssertTrue(app.staticTexts["cloud.error"].waitForExistence(timeout: 20))
        app.tabBars.buttons["书架"].tap(); XCTAssertTrue(app.staticTexts["云端来信测试"].firstMatch.exists)
    }
    @MainActor func testDirectDownloadAndDeletingCredentialKeepShelfAndOnlineSources() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-reset", "--uitest-cloud"]; app.launch(); discover(app)
        let download = app.buttons["cloud.download." + id]; XCTAssertTrue(download.waitForExistence(timeout: 20)); download.tap()
        XCTAssertTrue(app.staticTexts["已下载，可离线阅读"].firstMatch.waitForExistence(timeout: 30))
        app.segmentedControls["discover.section"].buttons["在线书源"].tap()
        XCTAssertTrue(app.textFields["搜索小说"].waitForExistence(timeout: 10))
        app.tabBars.buttons["我的"].tap()
        let connection = app.buttons["profile.cloud"].firstMatch
        if connection.waitForExistence(timeout: 5) { connection.tap() }
        else { app.staticTexts["云书库连接"].firstMatch.tap() }
        let remove = app.buttons["cloud.removeToken"]; XCTAssertTrue(remove.waitForExistence(timeout: 10)); remove.tap()
        app.buttons["删除凭据"].tap()
        XCTAssertTrue(app.secureTextFields["cloud.token"].waitForExistence(timeout: 10))
        app.tabBars.buttons["发现"].tap(); app.segmentedControls["discover.section"].buttons["云书库"].tap()
        XCTAssertTrue(app.buttons["cloud.connect"].waitForExistence(timeout: 10))
        app.tabBars.buttons["书架"].tap(); XCTAssertTrue(app.staticTexts["云端来信测试"].firstMatch.waitForExistence(timeout: 10))
    }
    @MainActor func testRevokedTokenShowsReconnectWithoutAccountOrExtraTab() {
        let app = XCUIApplication(); app.launchArguments = ["--uitest-reset", "--uitest-cloud", "--uitest-cloud-unauthorized"]; app.launch(); discover(app)
        XCTAssertTrue(app.buttons["cloud.connect"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "重新连接")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        app.buttons["cloud.connect"].tap()
        XCTAssertTrue(app.secureTextFields["cloud.token"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["cloud.saveToken"].exists)
    }
}
