import XCTest

final class ReaderScrollPerformanceTests: XCTestCase {
    // The baseline preparation script changes only this constant in its worktree.
    private let baseline = false
    @MainActor private func exercise(_ fixture: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-performance=" + fixture, "--reader-performance"] + (baseline ? ["--reader-baseline"] : [])
        app.launch()
        let book = app.staticTexts["滚动性能原创样本"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 45)); book.tap()
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 45))
        if app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        attach(app, fixture + "-沉浸起始")
        // Identical real touch gestures for baseline and optimized app on one device.
        for _ in 0..<12 { table.swipeUp(velocity: .fast) }
        for _ in 0..<4 { table.swipeDown(velocity: .fast) }
        let start = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = table.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        attach(app, fixture + "-甩动与反向")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(app.buttons["返回书架"].waitForExistence(timeout: 5)); app.buttons["返回书架"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        book.tap(); XCTAssertTrue(table.waitForExistence(timeout: 30))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        XCTAssertTrue(app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "原创")).firstMatch.exists)
        attach(app, fixture + "-重启及后台恢复")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        if !app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        app.buttons["返回书架"].tap()
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testShortTXTRepeatedFlingAndRestore() { exercise("short") }
    @MainActor func testLongTXTRepeatedFlingAndRestore() { exercise("long") }
    @MainActor func testVeryLongChapterRepeatedFlingAndRestore() { exercise("monolith") }
}
