import XCTest
final class NavigationTests: XCTestCase {
    @MainActor func testChineseNavigation() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["书架"].waitForExistence(timeout: 15))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["字体、排版与主题"].waitForExistence(timeout: 5))
        app.tabBars.buttons["发现"].tap()
        XCTAssertTrue(app.segmentedControls["discover.section"].waitForExistence(timeout: 5))
        app.segmentedControls["discover.section"].buttons["在线书源"].tap()
        XCTAssertTrue(app.textFields["搜索小说"].waitForExistence(timeout: 5))
    }
}
