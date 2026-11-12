import XCTest
@testable import QingRead

private final class FixtureURLProtocol: URLProtocol {
    static var requests: [String] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.requests.append(url.path)
        let text: String
        switch url.path {
        case "/robots.txt": text = "User-agent: *\nAllow: /"
        case "/search": text = #"{"books":[{"title":"原创在线书","author":"测试作者","url":"/book"}]}"#
        case "/book": text = #"{"chapters":[{"title":"第一章","url":"/chapter/1"},{"title":"第二章","url":"/chapter/2"}]}"#
        case "/chapter/1": text = #"{"content":"第一章的原创中文正文。"}"#
        case "/chapter/2": text = #"{"content":"第二章的原创中文正文。"}"#
        default: text = "{}"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor
final class OnlineFlowTests: XCTestCase {
    func testSearchTOCBodyAndOfflineCache() async throws {
        FixtureURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = BookSourceService(session: session)
        let source = BookSource(name: "原创接口", baseURL: "https://fixture.qingread.invalid", searchURL: "https://fixture.qingread.invalid/search?q={{key}}")
        let results = try await service.search("原创", source: source)
        XCTAssertEqual(results.first?.title, "原创在线书")
        let item = try XCTUnwrap(results.first)
        let chapters = try await service.chapters(for: item)
        XCTAssertEqual(chapters.count, 2)
        let content = try await service.chapterText(url: XCTUnwrap(chapters.first?.remoteURL), source: source)
        XCTAssertEqual(content, "第一章的原创中文正文。")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(rootURL: root)
        let book = library.add(Book(title: item.title, format: .online, chapters: chapters, source: source))
        try library.cacheChapter(book: book, index: 0, text: content)
        let requests = FixtureURLProtocol.requests.count
        let restarted = LibraryStore(rootURL: root)
        let restored = try XCTUnwrap(restarted.books.first)
        let reader = ReaderSession(book: restored, library: restarted)
        let offline = try await reader.loadText(at: 0)
        XCTAssertEqual(offline, content)
        XCTAssertEqual(FixtureURLProtocol.requests.count, requests)
        XCTAssertTrue(FixtureURLProtocol.requests.contains("/robots.txt"))
    }
}
