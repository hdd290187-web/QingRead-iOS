import XCTest
@testable import QingRead

final class SourceTests: XCTestCase {
    func testImportFlagsUnsupportedRulesWithoutRejectingSimpleKeyTemplate() throws {
        let good = Data(#"{"bookSourceName":"测试","bookSourceUrl":"https://example.org","searchUrl":"/search?q={{key}}&page={{page}}","ruleSearch":{"bookList":".book","name":"a@text","bookUrl":"a@href"}}"#.utf8)
        let source = try XCTUnwrap(BookSourceService.importSources(good).first)
        XCTAssertTrue(source.enabled)
        XCTAssertTrue(source.issues.isEmpty)
        let bad = Data(#"[{"name":"脚本","bookSourceUrl":"https://example.org","searchUrl":"/s","ruleContent":{"content":"@js:java.getString()"}},{"name":"XPath","bookSourceUrl":"https://example.org","searchUrl":"/s","ruleSearch":{"bookList":"//div"}}]"#.utf8)
        let unsupported = try BookSourceService.importSources(bad)
        XCTAssertEqual(unsupported.count, 2)
        XCTAssertTrue(unsupported.allSatisfy { !$0.enabled && !$0.issues.isEmpty })
        XCTAssertThrowsError(try BookSourceService.importSources(Data("{}".utf8)))
        XCTAssertThrowsError(try BookSourceService.importSources(Data("not json".utf8)))
    }
    func testCSSSearchAndRelativeURL() throws {
        let source = BookSource(name: "站点", baseURL: "https://example.org", searchURL: "/search?q={{key}}", search: ["bookList": ".book", "name": "a@text", "author": ".author@text", "bookUrl": "a@href"])
        let html = Data("<main><div class='book'><a href='/book/1'>春天</a><span class='author'>测试作者</span></div></main>".utf8)
        let books = try BookSourceService.parseSearch(data: html, url: URL(string: "https://example.org/search?q=test")!, source: source)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(books[0].title, "春天")
        XCTAssertEqual(books[0].author, "测试作者")
        XCTAssertEqual(books[0].detailURL?.absoluteString, "https://example.org/book/1")
    }
    func testJSONPathAndFallbackAndRegex() throws {
        let doc = try RuleDocument(data: Data(#"{"data":{"books":[{"name":"第一章 广告","url":"/c/1"}]}}"#.utf8), baseURL: "https://example.org")
        let nodes = try doc.nodes("$.data.books[*]")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(try doc.value("missing||name## 广告##", from: nodes[0]), "第一章")
        XCTAssertEqual(try doc.value("url", from: nodes[0]), "/c/1")
    }
    func testTocDeduplicatesAndKeepsOrder() throws {
        let source = BookSource(name: "目录", baseURL: "https://example.org", searchURL: "/s", toc: ["chapterList": "a", "chapterName": "text", "chapterUrl": "href"])
        let data = Data("<a href='/1'>第一章</a><a href='/1'>重复</a><a href='/2'>第二章</a>".utf8)
        let chapters = try BookSourceService.parseChapters(data: data, url: URL(string: "https://example.org/toc")!, source: source)
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.last?.remoteURL?.path, "/2")
    }
    func testContentKeepsParagraphBreaksAndDropsScripts() throws {
        let text = try RuleDocument.cleanHTML("<script>alert(1)</script><p>第一段</p><p>第二段<br/>继续</p>")
        XCTAssertTrue(text.contains("第一段\n"))
        XCTAssertTrue(text.contains("第二段\n"))
        XCTAssertFalse(text.contains("alert"))
    }
    func testRobotsParsing() {
        let rules = SiteAccessPolicy.parse("User-agent: *\nDisallow: /private\nAllow: /private/open\nUser-agent: other\nDisallow: /all")
        XCTAssertEqual(rules.count, 2)
        XCTAssertFalse(rules[0].allow)
        XCTAssertEqual(rules[1].pattern, "/private/open")
    }
}
