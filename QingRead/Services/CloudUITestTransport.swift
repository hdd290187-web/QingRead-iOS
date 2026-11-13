#if DEBUG
import Foundation
import CryptoKit

/// Synthetic transport is installed only by an explicit DEBUG UI-test launch argument.
enum CloudUITestTransport {
    static let id = UUID(uuidString: "B67F5B15-2DA2-4099-A9B8-579A9342531A")!
    static let text = Data(("第一章 云端来信\n" + String(repeating: "这是一段测试生成的原创文字，下载后保存在本机书架。春天的风翻过书页，故事慢慢展开。\n", count: 60) + "第二章 归途\n故事的末尾仍有一盏灯。\n").utf8)
    static var book: CloudBook {
        CloudBook(id: id, title: "云端来信测试", author: "虚构作者", format: .txt, fileSize: Int64(text.count), originalName: "云端来信测试.txt",
                  sha256: SHA256.hash(data: text).map { String(format: "%02x", $0) }.joined(), updatedAt: "2026-11-13T00:00:00Z", revision: 1,
                  coverUrl: "/api/v1/books/\(id.uuidString)/cover", downloadUrl: "/api/v1/books/\(id.uuidString)/download")
    }
    static func client() -> CloudAPIClient {
        let token = "yy_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudUIFixtureProtocol.self]
        return CloudAPIClient(tokens: CloudMemoryTokenStore(token), configuration: config)
    }
}

private final class CloudUIFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == CloudAPIClient.origin.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if ProcessInfo.processInfo.arguments.contains("--uitest-cloud-offline") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        var code = 200
        var body = Data()
        var headers = ["Content-Type": "application/json"]
        let path = request.url!.path.lowercased()
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        if ProcessInfo.processInfo.arguments.contains("--uitest-cloud-unauthorized") { code = 401 }
        else if path.hasSuffix("/cover") { code = 404 }
        else if path.hasSuffix("/download") {
            body = CloudUITestTransport.text
            headers = ["Content-Type": "text/plain", "ETag": "\"\(CloudUITestTransport.book.sha256)\"", "Accept-Ranges": "bytes"]
            if let range = request.value(forHTTPHeaderField: "Range"), let start = Int(range.dropFirst(6).dropLast()), start < body.count {
                code = 206; headers["Content-Range"] = "bytes \(start)-\(body.count - 1)/\(body.count)"; body = body.subdata(in: start..<body.count)
            }
        } else if path == "/api/v1/books" {
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = parts.first(where: { $0.name == "query" })?.value ?? ""
            let format = parts.first(where: { $0.name == "format" })?.value ?? ""
            let items = (query.isEmpty || CloudUITestTransport.book.title.contains(query)) && (format.isEmpty || format == "txt") ? [CloudUITestTransport.book] : []
            body = (try? encoder.encode(CloudBookPage(items: items, total: items.count, page: 1, pageSize: 20))) ?? Data()
        } else { body = (try? encoder.encode(CloudUITestTransport.book)) ?? Data() }
        headers["Content-Length"] = String(body.count)
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for offset in stride(from: 0, to: body.count, by: 4096) { client?.urlProtocol(self, didLoad: body.subdata(in: offset..<min(body.count, offset + 4096))) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
