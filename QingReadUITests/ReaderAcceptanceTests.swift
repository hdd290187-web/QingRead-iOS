import XCTest

final class ReaderAcceptanceTests: XCTestCase {
    @MainActor private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func reveal(_ app: XCUIApplication) {
        if !app.buttons["返回书架"].isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
    }
    @MainActor private func scrollTo(_ target: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            let bars=app.navigationBars.allElementsBoundByIndex.filter { $0.isHittable }
            let top=(bars.map { $0.frame.maxY }.max() ?? 0)+12
            if target.exists && target.isHittable && target.frame.midY>top && target.frame.maxY<app.frame.maxY-16 { return }
            let picker=element(app,"settings.font.list")
            let form=element(app,"settings.form.scroll")
            let container=picker.exists && picker.isHittable ? picker : form
            XCTAssertTrue(container.exists)
            if target.exists && target.frame.midY<=top { container.swipeDown(velocity:.slow) }
            else { container.swipeUp(velocity:.slow) }
        }
        XCTAssertTrue(target.isHittable)
    }
    @MainActor private func open(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-reset", "--uitest-seed", "--uitest-mode=" + mode]
        app.launch()
        let book = app.staticTexts["原创阅读测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 20)); book.tap()
        XCTAssertTrue(element(app, mode == "scroll" ? "reader.scrollViewport" : "reader.content").waitForExistence(timeout: 30))
        return app
    }
    @MainActor private func setProgressVisible(_ expected: Bool, app: XCUIApplication) {
        let toggle = app.switches["settings.showBottomProgress"]
        scrollTo(toggle, app: app)
        XCTAssertEqual(toggle.value as? String, expected ? "0" : "1")
        // SwiftUI exposes the complete label row as the switch accessibility frame.
        // Tap the actual trailing control, then verify the binding before dismissing.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", expected ? "1" : "0"), evaluatedWith: toggle)
        waitForExpectations(timeout: 10)
    }
    @MainActor func testBookmarkCancelReflowRestartAndListDeletion() {
        let app = open("slide"); reveal(app)
        let bookmark = app.buttons["reader.bookmark"]
        XCTAssertEqual(bookmark.value as? String, "未收藏")
        bookmark.tap(); XCTAssertEqual(bookmark.value as? String, "已收藏")
        bookmark.tap(); XCTAssertEqual(bookmark.value as? String, "未收藏")
        bookmark.tap()
        app.buttons["reader.settings"].tap()
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition: 0.6)
        app.buttons["reader.settings.done"].tap()
        reveal(app); XCTAssertEqual(bookmark.value as? String, "已收藏")
        app.buttons["返回书架"].tap(); app.terminate(); app.launchArguments = []; app.launch()
        app.staticTexts["原创阅读测试"].firstMatch.tap()
        XCTAssertTrue(element(app,"reader.content").waitForExistence(timeout: 20)); reveal(app)
        XCTAssertEqual(bookmark.value as? String, "已收藏")
        app.buttons["书签"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "reader.bookmark.item."))
        XCTAssertEqual(rows.count, 1)
        rows.firstMatch.swipeLeft(); app.buttons["删除"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(bookmark.value as? String, "未收藏")
        app.buttons["下一章"].tap(); reveal(app)
        XCTAssertEqual(bookmark.value as? String, "未收藏")
        bookmark.tap(); app.buttons["上一章"].tap(); reveal(app)
        XCTAssertEqual(bookmark.value as? String, "未收藏")
    }
    @MainActor private func progressAndViewport(mode: String, landscape: Bool) {
        let app = open(mode)
        if landscape { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let viewport = element(app, mode == "scroll" ? "reader.scrollViewport" : "reader.content")
        let progress = element(app,"reader.compactProgress")
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap(); XCTAssertTrue(app.buttons["返回书架"].isHittable)
        progress.tap(); XCTAssertFalse(app.buttons["返回书架"].exists)
        let height = viewport.frame.height
        let oldContent = mode == "scroll" ? viewport.value as? String : viewport.label
        progress.tap(); app.buttons["reader.settings"].tap()
        setProgressVisible(false, app: app)
        app.buttons["reader.settings.done"].tap()
        expectation(for: NSPredicate { _, _ in viewport.exists && viewport.frame.height > height + 20 }, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        XCTAssertFalse(progress.exists)
        XCTAssertEqual(viewport.frame.height - height, 28, accuracy: 2)
        if mode == "scroll" { XCTAssertEqual(viewport.value as? String, oldContent) }
        else { XCTAssertTrue((viewport.value as? String ?? "").contains("第1章")) }
        reveal(app); app.buttons["reader.settings"].tap(); setProgressVisible(true, app: app); app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(viewport.frame.height,height,accuracy:2)
    }
    @MainActor func testAllTXTModeProgressToggleActuallyExpandsViewport() {
        for mode in ["slide","cover","curl","scroll"] { progressAndViewport(mode:mode,landscape:false) }
    }
    @MainActor func testLandscapeProgressTogglePreservesViewportAnchor() {
        for mode in ["slide","cover","curl","scroll"] { progressAndViewport(mode:mode,landscape:true) }
    }
    @MainActor func testOpenPanelLiveTextLayoutThemeAndRealFontPicker() {
        let app=XCUIApplication()
        app.launchArguments=["--uitest-reset","--uitest-integrity=short","--reader-integrity"]
        app.launch(); let book=app.staticTexts["滚动顺序回归样本"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:30));book.tap()
        let table=app.tables.matching(identifier:"reader.scrollViewport").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout:30))
        var lastProbe=""
        func state() -> [String:Any] {
            let probe=app.staticTexts["settings.readerProbe"].label
            if probe != lastProbe { print("ReaderSettingsEvidence "+probe);lastProbe=probe }
            guard let bytes=probe.data(using:.utf8),let v=try? JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { return [:] };return v
        }
        reveal(app); let readerTable=element(app,"reader.scrollViewport")
        let original = readerTable.value.flatMap { String(describing:$0).split(separator:":").last.flatMap { Int($0) } } ?? 0
        reveal(app);app.buttons["reader.settings"].tap()
        XCTAssertFalse(app.staticTexts["即时预览"].exists)
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition:0.6)
        let chosenSize=Double(app.staticTexts["settings.fontSize.value"].label.split(separator:" ").first ?? "") ?? -1
        XCTAssertNotEqual(chosenSize,20);XCTAssertTrue((14...36).contains(chosenSize))
        expectation(for:NSPredicate { _,_ in state()["fontSize"] as? Double == chosenSize },evaluatedWith:nil);waitForExpectations(timeout:20)
        XCTAssertTrue(app.buttons["reader.settings.done"].exists,"验证必须发生在面板仍然打开时")
        app.buttons["settings.font"].tap()
        let wenKai=app.buttons["settings.font.kaiti"];scrollTo(wenKai,app:app);XCTAssertTrue(wenKai.waitForExistence(timeout:5));wenKai.tap();app.navigationBars.buttons.firstMatch.tap()
        expectation(for:NSPredicate { _,_ in (state()["fontName"] as? String ?? "").contains("LXGW") },evaluatedWith:nil);waitForExpectations(timeout:20)
        app.buttons["settings.font"].tap()
        let heiti=app.buttons["settings.font.heiti"];scrollTo(heiti,app:app);XCTAssertTrue(heiti.waitForExistence(timeout:5))
        heiti.tap();app.navigationBars.buttons.firstMatch.tap()
        expectation(for:NSPredicate { _,_ in state()["fontName"] as? String == "PingFangSC-Light" && state()["fontFamily"] as? String == "PingFang SC" },evaluatedWith:nil);waitForExpectations(timeout:20)
        app.buttons["settings.font"].tap();let serif=app.buttons["settings.font.serif"];scrollTo(serif,app:app);serif.tap();app.navigationBars.buttons.firstMatch.tap()
        expectation(for:NSPredicate { _,_ in let name=state()["fontName"] as? String ?? "";return name.contains("Noto") },evaluatedWith:nil);waitForExpectations(timeout:20)
        let green=app.buttons["settings.theme.green"];scrollTo(green,app:app);green.tap()
        expectation(for:NSPredicate { _,_ in state()["theme"] as? String == "green" },evaluatedWith:nil);waitForExpectations(timeout:10)
        XCTAssertLessThanOrEqual(abs((state()["globalOffset"] as? Int ?? -1000)-original),40)
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name="Build44-半透明护眼面板与真实正文";image.lifetime = .keepAlways;add(image)
        let dark=app.buttons["settings.theme.dark"];dark.tap()
        expectation(for:NSPredicate { _,_ in state()["theme"] as? String == "dark" },evaluatedWith:nil);waitForExpectations(timeout:10)
        let darkImage=XCTAttachment(screenshot:XCUIScreen.main.screenshot());darkImage.name="Build44-打开中的深色面板";darkImage.lifetime = .keepAlways;add(darkImage)
        app.buttons["reader.settings.done"].tap()
    }
    @MainActor func testEPUBProgressAndOpenPanelLivePreferences() {
        let app=XCUIApplication(); app.launchArguments=["--uitest-reset","--uitest-epub"]; app.launch()
        let book=app.staticTexts["封面与排版测试"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout:30));book.tap()
        let web=app.webViews.firstMatch
        let text=web.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","这是专为自动测试原创的短文")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout:45))
        let oldHeight=web.frame.height, oldTextHeight=text.frame.height
        let progress=element(app,"reader.compactProgress");progress.tap()
        app.buttons["reader.bookmark"].tap()
        XCTAssertEqual(app.buttons["reader.bookmark"].value as? String,"已收藏")
        app.buttons["reader.bookmark"].tap()
        XCTAssertEqual(app.buttons["reader.bookmark"].value as? String,"未收藏")
        app.buttons["reader.bookmark"].tap()
        app.buttons["reader.settings"].tap()
        app.sliders["settings.fontSize"].adjust(toNormalizedSliderPosition:0.65)
        expectation(for:NSPredicate { _,_ in text.exists && text.frame.height > oldTextHeight },evaluatedWith:nil);waitForExpectations(timeout:20)
        XCTAssertTrue(app.buttons["reader.settings.done"].exists)
        let toggle=app.switches["settings.showBottomProgress"];scrollTo(toggle,app:app);toggle.tap()
        app.buttons["reader.settings.done"].tap()
        expectation(for:NSPredicate { _,_ in web.frame.height > oldHeight + 20 },evaluatedWith:nil);waitForExpectations(timeout:20)
        XCTAssertFalse(progress.exists)
        XCTAssertEqual(web.frame.height-oldHeight,28,accuracy:2)
        reveal(app);XCTAssertEqual(app.buttons["reader.bookmark"].value as? String,"已收藏","EPUB 重排后原书签仍位于当前可见页")
        app.buttons["reader.bookmark"].tap();XCTAssertEqual(app.buttons["reader.bookmark"].value as? String,"未收藏")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(text.waitForExistence(timeout:15))
        XCUIDevice.shared.orientation = .portrait
        reveal(app);app.buttons["reader.settings"].tap();scrollTo(toggle,app:app);toggle.tap();app.buttons["reader.settings.done"].tap()
        XCTAssertTrue(progress.waitForExistence(timeout:10))
        XCTAssertTrue(text.exists)
    }
    @MainActor func testProfileKeepsTechnicalDetailsInsideAbout() {
        let app=XCUIApplication();app.launchArguments=["--uitest-reset"];app.launch()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["profile.about"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["版本"].exists)
        XCTAssertFalse(app.staticTexts["开源许可与素材来源"].exists)
        app.buttons["profile.about"].tap()
        XCTAssertTrue(app.staticTexts["版本"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["开源许可与素材来源"].exists)
        XCTAssertTrue(app.staticTexts["书源兼容范围"].exists)
    }
}
