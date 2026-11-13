import XCTest
import CryptoKit
@testable import QingRead

private struct CloudStubReply {
    var code = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var data = Data()
    var slow = false
}

private final class CloudStubProtocol: URLProtocol {
    static var reply: ((URLRequest) -> CloudStubReply)?
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let reply = Self.reply?(request) else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return }
        var headers = reply.headers; headers["Content-Length"] = String(reply.data.count)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().async {
            for offset in stride(from: 0, to: reply.data.count, by: reply.slow ? 128 : 4096) {
                if reply.slow { Thread.sleep(forTimeInterval: 0.02) }
                self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
                if stopped { return }
                self.client?.urlProtocol(self, didLoad: reply.data.subdata(in: offset..<min(reply.data.count, offset + (reply.slow ? 128 : 4096))))
            }
            self.lock.lock(); let stopped = self.stopped; self.lock.unlock()
            if !stopped { self.client?.urlProtocolDidFinishLoading(self) }
        }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}

@MainActor
final class CloudTests: XCTestCase {
    private var root: URL!
    private var data: Data { CloudUITestTransport.text }
    private var book: CloudBook { CloudUITestTransport.book }
    private var credential: String { "yy_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { CloudStubProtocol.reply = nil; try? FileManager.default.removeItem(at: root) }
    private func client(_ tokens: CloudMemoryTokenStore? = nil) -> CloudAPIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudStubProtocol.self]
        return CloudAPIClient(tokens: tokens ?? CloudMemoryTokenStore(credential), configuration: config)
    }
    private func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; return try encoder.encode(value)
    }
    private func file(_ bytes: Data? = nil) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".txt"); try (bytes ?? data).write(to: url); return url
    }
    private func context(_ book: CloudBook, update: Bool = false, cancellation: CloudCancellation = .init()) -> CloudImportContext {
        .init(book: book, allowsUpdate: update, cancellation: cancellation)
    }
    private func transfer(_ book: CloudBook? = nil, client: CloudAPIClient) -> CloudFileTransfer {
        CloudFileTransfer(book: book ?? self.book, directory: root.appendingPathComponent("downloads"), configuration: client.configuration)
    }
    private func partial(_ book: CloudBook) -> URL {
        root.appendingPathComponent("downloads/\(book.id.uuidString)-\(book.sha256).part")
    }
    private func preparePartial(_ count: Int) throws {
        try FileManager.default.createDirectory(at: partial(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.prefix(count).write(to: partial(book))
    }
    private func downloadReply(_ body: Data, book: CloudBook, code: Int = 200, range: String? = nil, slow: Bool = false) -> CloudStubReply {
        var headers = ["Content-Type": "text/plain", "ETag": "\"\(book.sha256)\"", "Accept-Ranges": "bytes"]
        if let range { headers["Content-Range"] = range }
        return .init(code: code, headers: headers, data: body, slow: slow)
    }

    func testAPIUsesFixedHTTPSBearerAndDocumentedQuery() async throws {
        let token = credential; let client = client(CloudMemoryTokenStore(token))
        let payload = try json(CloudBookPage(items: [book], total: 21, page: 2, pageSize: 20))
        CloudStubProtocol.reply = { request in
            XCTAssertEqual(request.url?.scheme, "https"); XCTAssertEqual(request.url?.host, "1.113188.xyz")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
            XCTAssertFalse(request.url!.absoluteString.contains(token))
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first(where: { $0.name == "page" })?.value, "2")
            XCTAssertEqual(query.first(where: { $0.name == "query" })?.value, "中文 & 作者")
            XCTAssertEqual(query.first(where: { $0.name == "sort" })?.value, "title_asc")
            XCTAssertEqual(query.first(where: { $0.name == "format" })?.value, "epub")
            return .init(data: payload)
        }
        let result = try await client.books(query: "中文 & 作者", page: 2, format: "epub", sort: .title)
        XCTAssertEqual(result.items.first?.id, book.id); XCTAssertEqual(result.total, 21)
    }

    func testCoverIsAuthenticatedAndMissingCoverIsOptional() async throws {
        let token = credential; let client = client(CloudMemoryTokenStore(token))
        CloudStubProtocol.reply = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
            XCTAssertTrue(request.url!.path.hasSuffix("/cover")); return .init(code: 404)
        }
        let cover = try await client.cover(book); XCTAssertNil(cover)
    }

    func testAPIStatusMessagesAndMalformedPayload() async throws {
        let client = client()
        for status in [401, 403, 404, 410, 416, 429, 503] {
            CloudStubProtocol.reply = { _ in .init(code: status) }
            do { _ = try await client.books(); XCTFail("Expected HTTP failure") }
            catch { XCTAssertEqual(error as? CloudError, .status(status)); XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
        CloudStubProtocol.reply = { _ in .init(data: Data("{}".utf8)) }
        do { _ = try await client.books(); XCTFail("Expected invalid response") } catch { XCTAssertEqual(error as? CloudError, .invalidResponse) }
    }

    func testRedirectAndForeignRequestCannotForwardCredential() throws {
        let client = client()
        XCTAssertThrowsError(try client.request(path: "https://invalid.example/api/v1/books"))
        XCTAssertThrowsError(try client.request(path: "/api/v1/../admin"))
        let delegate = CloudRedirectGuard()
        let request = URLRequest(url: URL(string: "https://invalid.example")!)
        let response = HTTPURLResponse(url: CloudAPIClient.origin, statusCode: 302, httpVersion: nil, headerFields: nil)!
        delegate.urlSession(.shared, task: URLSession.shared.dataTask(with: request), willPerformHTTPRedirection: response, newRequest: request) { XCTAssertNil($0) }
    }

    func testKeychainLifecycleAndIsolation() throws {
        let keychain = CloudKeychain(service: "com.hdd290187.qingread.tests." + UUID().uuidString)
        defer { try? keychain.remove() }
        XCTAssertNil(try keychain.read())
        let first = credential; try keychain.save(first); XCTAssertEqual(try keychain.read(), first)
        let second = credential; try keychain.save(second); XCTAssertEqual(try keychain.read(), second)
        try keychain.remove(); XCTAssertNil(try keychain.read())
    }

    func testConnectionStoresOnlyVerifiedCredentialAndRemovalKeepsLocalBook() async throws {
        let tokens = CloudMemoryTokenStore(); let cloud = CloudLibraryStore(client: client(tokens), downloadDirectory: root)
        let token = credential
        CloudStubProtocol.reply = { _ in .init(code: 401) }
        let rejected = await cloud.connect(token); XCTAssertFalse(rejected); XCTAssertNil(try tokens.read())
        let payload = try json(CloudBookPage(items: [book], total: 1, page: 1, pageSize: 20))
        CloudStubProtocol.reply = { _ in .init(data: payload) }
        let connected = await cloud.connect(token); XCTAssertTrue(connected); XCTAssertEqual(try tokens.read(), token)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let local = try await library.importCloudFile(from: file(), context: context(book))
        cloud.disconnect(); XCTAssertNil(try tokens.read()); XCTAssertFalse(cloud.connected)
        XCTAssertEqual(library.books.first?.id, local.id)
        XCTAssertFalse(try String(contentsOf: library.root.appendingPathComponent("library.json"), encoding: .utf8).contains(token))
    }

    func testUnauthorizedRefreshClearsCredentialAndPreservesOfflineBook() async throws {
        let tokens = CloudMemoryTokenStore(credential); let cloud = CloudLibraryStore(client: client(tokens))
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let local = try await library.importCloudFile(from: file(), context: context(book))
        CloudStubProtocol.reply = { _ in .init(code: 401) }; await cloud.refresh()
        XCTAssertFalse(cloud.connected); XCTAssertNil(try tokens.read()); XCTAssertTrue(cloud.message?.contains("重新连接") == true)
        let restart = LibraryStore(rootURL: library.root); XCTAssertEqual(restart.books.first?.id, local.id)
        XCTAssertFalse(restart.chapterText(for: local.chapters[0], book: local).isEmpty)
    }

    func testOfflineRefreshRetainsLastCloudList() async throws {
        let cloud = CloudLibraryStore(client: client())
        let payload = try json(CloudBookPage(items: [book], total: 1, page: 1, pageSize: 20))
        CloudStubProtocol.reply = { _ in .init(data: payload) }; await cloud.refresh()
        CloudStubProtocol.reply = nil; await cloud.refresh()
        XCTAssertEqual(cloud.books.count, 1); XCTAssertNotNil(cloud.message); XCTAssertTrue(cloud.connected)
    }

    func testPaginationDeduplicatesRowsAndRemoteDeletionKeepsLocalLibrary() async throws {
        let cloud = CloudLibraryStore(client: client())
        let first = book; var second = book; second.id = UUID(); second.title = "另一部虚构小说"
        let page1 = try json(CloudBookPage(items: [first], total: 21, page: 1, pageSize: 20))
        let page2 = try json(CloudBookPage(items: [first, second], total: 21, page: 2, pageSize: 20))
        CloudStubProtocol.reply = { request in
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value
            return .init(data: page == "2" ? page2 : page1)
        }
        await cloud.refresh(); XCTAssertTrue(cloud.hasMore)
        await cloud.nextPage(); XCTAssertEqual(cloud.books.map(\.id), [first.id, second.id]); XCTAssertFalse(cloud.hasMore)
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let local = try await library.importCloudFile(from: file(), context: context(first))
        let empty = try json(CloudBookPage(items: [], total: 0, page: 1, pageSize: 20))
        CloudStubProtocol.reply = { _ in .init(data: empty) }; await cloud.refresh()
        XCTAssertTrue(cloud.books.isEmpty); XCTAssertEqual(library.localBook(cloudID: first.id)?.id, local.id)
    }

    func testChangesUsesBothCursorFields() async throws {
        let client = client(); let id = UUID(); let since = "2026-11-13T12:00:00.123456+00:00"
        let payload = try json(CloudChanges(items: [.init(id: id, updatedAt: since, deletedAt: since, revision: 3)], hasMore: false, next: .init(since: since, afterId: id)))
        CloudStubProtocol.reply = { request in
            XCTAssertEqual(request.url!.path, "/api/v1/changes")
            XCTAssertTrue(request.url!.absoluteString.contains("%2B"))
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first(where: { $0.name == "since" })?.value, since)
            XCTAssertEqual(query.first(where: { $0.name == "after_id" })?.value, id.uuidString)
            return .init(data: payload)
        }
        let changes = try await client.changes(since: since, afterID: id)
        XCTAssertEqual(changes.next?.afterId, id); XCTAssertNotNil(changes.items.first?.deletedAt)
    }

    func testStreamingDownloadVerifiedAndAtomicallyCompleted() async throws {
        let client = client(); let reply = downloadReply(data, book: book)
        CloudStubProtocol.reply = { _ in reply }
        let result = try await transfer(client: client).download(request: client.request(path: book.downloadUrl)) { _, _ in }
        XCTAssertEqual(try Data(contentsOf: result), data); XCTAssertFalse(FileManager.default.fileExists(atPath: partial(book).path))
    }

    func testRange206ResumesExactBytes() async throws {
        try preparePartial(37)
        let client = client(); let original = data; let b = book
        let reply = downloadReply(original.subdata(in: 37..<original.count), book: b, code: 206, range: "bytes 37-\(original.count - 1)/\(original.count)")
        CloudStubProtocol.reply = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=37-")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Range"), "\"\(b.sha256)\""); return reply
        }
        let result = try await transfer(client: client).download(request: client.request(path: book.downloadUrl)) { _, _ in }
        XCTAssertEqual(try Data(contentsOf: result), original)
    }

    func testRangeIgnored200ReplacesPartialInsteadOfAppending() async throws {
        try preparePartial(41)
        let client = client(); let reply = downloadReply(data, book: book)
        CloudStubProtocol.reply = { request in XCTAssertNotNil(request.value(forHTTPHeaderField: "Range")); return reply }
        let result = try await transfer(client: client).download(request: client.request(path: book.downloadUrl)) { _, _ in }
        XCTAssertEqual(try Data(contentsOf: result), data)
    }

    func testInvalidRangeAnd416DiscardUnsafePartial() async throws {
        let client = client()
        for status in [206, 416] {
            try preparePartial(37)
            let reply = downloadReply(data.suffix(from: 37), book: book, code: status, range: "bytes 0-\(data.count - 1)/\(data.count)")
            CloudStubProtocol.reply = { _ in reply }
            do { _ = try await transfer(client: client).download(request: client.request(path: book.downloadUrl)) { _, _ in }; XCTFail("Expected invalid range") }
            catch { XCTAssertEqual(error as? CloudError, status == 416 ? .status(416) : .invalidResponse) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: partial(book).path))
        }
    }

    func testChecksumMismatchNeverCompletesFile() async throws {
        let client = client(); var corrupt = data; corrupt[0] ^= 1
        let reply = downloadReply(corrupt, book: book); CloudStubProtocol.reply = { _ in reply }
        do { _ = try await transfer(client: client).download(request: client.request(path: book.downloadUrl)) { _, _ in }; XCTFail("Expected bad checksum") }
        catch { XCTAssertEqual(error as? CloudError, .integrity) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial(book).path))
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: partial(book).deletingLastPathComponent().path).isEmpty) == true)
    }

    func testCancelPreservesBytesAndRetryResumesSafely() async throws {
        let client = client(); let started = expectation(description: "Some bytes reached the private file")
        started.assertForOverFulfill = false
        let reply = downloadReply(data, book: book, slow: true); CloudStubProtocol.reply = { _ in reply }
        let transfer = transfer(client: client)
        let task = Task { try await transfer.download(request: client.request(path: book.downloadUrl)) { done, _ in if done >= 128 { started.fulfill() } } }
        await fulfillment(of: [started], timeout: 10); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertEqual(error as? CloudError, .cancelled) }
        let count = try partial(book).resourceValues(forKeys: [.fileSizeKey]).fileSize!
        XCTAssertGreaterThan(count, 0); XCTAssertLessThan(count, data.count)
        let remaining = downloadReply(data.suffix(from: count), book: book, code: 206, range: "bytes \(count)-\(data.count - 1)/\(data.count)")
        CloudStubProtocol.reply = { request in XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=\(count)-"); return remaining }
        let retry = CloudFileTransfer(book: book, directory: root.appendingPathComponent("downloads"), configuration: client.configuration)
        let result = try await retry.download(request: client.request(path: book.downloadUrl)) { _, _ in }
        XCTAssertEqual(try Data(contentsOf: result), data)
    }

    func testCloudUUIDDeduplicationAndRemoteRenamePreserveProgress() async throws {
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let source = try file(); let first = try await library.importCloudFile(from: source, context: context(book))
        let position = ReadingPosition(chapter: 0, characterOffset: 32, progression: 0.3)
        library.update(position: position, for: first); library.addBookmark(.init(bookID: first.id, position: position, title: "原书签"))
        var renamed = book; renamed.title = "云端改名"; renamed.revision = 2
        let again = try await library.importCloudFile(from: source, context: context(renamed))
        XCTAssertEqual(first.id, again.id); XCTAssertEqual(library.books.count, 1); XCTAssertEqual(library.position(for: again), position)
        XCTAssertEqual(library.bookmarks(for: again).count, 1)
        let restart = LibraryStore(rootURL: library.root); XCTAssertEqual(restart.localBook(cloudID: book.id)?.id, first.id)
    }

    func testExplicitUpdateKeepsBookChapterBookmarkIDsAndTextAnchor() async throws {
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let first = try await library.importCloudFile(from: file(), context: context(book))
        let position = ReadingPosition(chapter: 0, characterOffset: 1500, progression: 0.3)
        library.update(position: position, for: first)
        let mark = Bookmark(bookID: first.id, position: position, title: "仍在这里"); library.addBookmark(mark)
        let revised = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "第一章 云端来信\n", with: "第一章 云端来信\n新增的一段。\n").utf8)
        var remote = book; remote.sha256 = SHA256.hash(data: revised).map { String(format: "%02x", $0) }.joined(); remote.fileSize = Int64(revised.count); remote.revision = 2
        let updated = try await library.importCloudFile(from: file(revised), context: context(remote, update: true))
        XCTAssertEqual(updated.id, first.id); XCTAssertEqual(updated.chapters[0].id, first.chapters[0].id); XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.bookmarks(for: updated).first?.id, mark.id)
        XCTAssertEqual(library.position(for: updated).characterOffset, position.characterOffset + "新增的一段。\n".utf16.count)
        XCTAssertEqual(library.localBook(cloudID: remote.id)?.cloudLinks?.first?.sha256, remote.sha256)
    }

    func testCancelledImportAndReadingUpdateLeaveOriginalUntouched() async throws {
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let cancellation = CloudCancellation(); cancellation.cancel()
        do { _ = try await library.importCloudFile(from: file(), context: context(book, cancellation: cancellation)); XCTFail("Cancelled import") } catch {}
        XCTAssertTrue(library.books.isEmpty)
        let first = try await library.importCloudFile(from: file(), context: context(book)); library.readerOpened(first.id)
        var remote = book; remote.revision = 2
        do { _ = try await library.importCloudFile(from: file(), context: context(remote, update: true)); XCTFail("Reading update must wait") } catch {}
        XCTAssertEqual(library.books.first, first); XCTAssertEqual(library.books.first?.originalFile, first.originalFile)
        library.readerClosed(first.id)
    }

    func testFailedUpdateCommitPreservesOriginalFileAndSnapshot() async throws {
        let folder = root.appendingPathComponent("library")
        let library = LibraryStore(rootURL: folder)
        let first = try await library.importCloudFile(from: file(), context: context(book))
        let snapshot = try Data(contentsOf: folder.appendingPathComponent("library.json"))
        var environment = ImportEnvironment.live; environment.beforeCommit = { _ in throw CocoaError(.fileWriteOutOfSpace) }
        let failing = LibraryStore(rootURL: folder, importEnvironment: environment)
        let revised = Data("第一章\n更新内容。".utf8)
        var remote = book; remote.revision = 2; remote.fileSize = Int64(revised.count)
        remote.sha256 = SHA256.hash(data: revised).map { String(format: "%02x", $0) }.joined()
        do { _ = try await failing.importCloudFile(from: file(revised), context: context(remote, update: true)); XCTFail("Expected commit failure") } catch {}
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("library.json")), snapshot)
        XCTAssertEqual(failing.books.first?.id, first.id); XCTAssertFalse(failing.chapterText(for: first.chapters[0], book: first).isEmpty)
    }

    func testDownloadThroughExistingImporterDeduplicatesRapidTaps() async throws {
        let library = LibraryStore(rootURL: root.appendingPathComponent("library")); let b = book
        let client = client(); let cloud = CloudLibraryStore(client: client, downloadDirectory: root.appendingPathComponent("downloads"))
        let payload = try json(b); let reply = downloadReply(data, book: b)
        CloudStubProtocol.reply = { request in request.url!.path.hasSuffix("/download") ? reply : .init(data: payload) }
        for _ in 0..<8 { cloud.download(b, library: library, openAfter: true) }
        for _ in 0..<300 {
            if cloud.bookToOpen != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(library.books.count, 1); XCTAssertEqual(cloud.bookToOpen?.id, library.books.first?.id)
        XCTAssertEqual(library.localBook(cloudID: b.id)?.id, library.books.first?.id)
        let restart = LibraryStore(rootURL: library.root); XCTAssertEqual(restart.books.count, 1)
    }

    func testPreCloudSnapshotRetainsIDsPathsBookmarksAndReaderSettings() async throws {
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let source = try file(); let imported = await library.importFile(from: source); let local = try XCTUnwrap(imported)
        let position = ReadingPosition(chapter: 0, characterOffset: 17, progression: 0.2)
        library.update(position: position, for: local); library.addBookmark(.init(bookID: local.id, position: position, title: "本地书签"))
        library.settings.mode = .scroll; library.settings.font = .heiti; library.flush()
        let index = library.root.appendingPathComponent("library.json")
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [String: Any])
        var records = try XCTUnwrap(snapshot["books"] as? [[String: Any]])
        for i in records.indices { records[i].removeValue(forKey: "cloudLinks") }
        snapshot["books"] = records; try JSONSerialization.data(withJSONObject: snapshot).write(to: index, options: .atomic)
        let restart = LibraryStore(rootURL: library.root)
        XCTAssertEqual(restart.books.first?.id, local.id); XCTAssertEqual(restart.books.first?.originalFile, local.originalFile)
        XCTAssertEqual(restart.books.first?.chapters.map(\.id), local.chapters.map(\.id)); XCTAssertNil(restart.books.first?.cloudLinks)
        XCTAssertEqual(restart.position(for: local), position); XCTAssertEqual(restart.bookmarks(for: local).count, 1)
        XCTAssertEqual(restart.settings.mode, .scroll); XCTAssertEqual(restart.settings.font, .heiti)
    }

    func testCloudEPUBUsesExistingImporterAndOriginalBytes() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "OriginalFixture", withExtension: "epub"))
        let bytes = try Data(contentsOf: source)
        var remote = book; remote.id = UUID(); remote.format = .epub; remote.fileSize = Int64(bytes.count); remote.originalName = "原创测试书.epub"
        remote.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let client = client(); let reply = downloadReply(bytes, book: remote); CloudStubProtocol.reply = { _ in reply }
        let file = try await transfer(remote, client: client).download(request: client.request(path: "/api/v1/books/\(remote.id.uuidString)/download")) { _, _ in }
        let library = LibraryStore(rootURL: root.appendingPathComponent("library"))
        let local = try await library.importCloudFile(from: file, context: context(remote))
        XCTAssertEqual(local.format, .epub); XCTAssertEqual(local.chapters.map(\.title), ["第一章 出发", "第二章 归来"])
        XCTAssertEqual(try DocumentStager.contentIdentity(at: URL(fileURLWithPath: XCTUnwrap(local.originalFile))), remote.sha256)
        let restart = LibraryStore(rootURL: library.root); XCTAssertEqual(restart.localBook(cloudID: remote.id)?.id, local.id)
    }
}
