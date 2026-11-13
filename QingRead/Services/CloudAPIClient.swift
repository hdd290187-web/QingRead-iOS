import Foundation

final class CloudRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class CloudAPIClient: @unchecked Sendable {
    static let origin = URL(string: "https://1.113188.xyz")!
    let tokens: any CloudTokenStore
    let configuration: URLSessionConfiguration
    private let session: URLSession
    init(tokens: any CloudTokenStore = CloudKeychain(), configuration: URLSessionConfiguration = .ephemeral) {
        self.tokens = tokens
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        self.configuration = configuration
        session = URLSession(configuration: configuration, delegate: CloudRedirectGuard(), delegateQueue: nil)
    }
    static func isValidToken(_ token: String) -> Bool {
        token.hasPrefix("yy_") && (50...200).contains(token.count) &&
        token.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
    func request(path: String, query: [URLQueryItem] = [], token: String? = nil) throws -> URLRequest {
        guard path.hasPrefix("/api/v1/"), !path.contains("?"), !path.contains("#"), !path.contains("..") else { throw CloudError.invalidResponse }
        var parts = URLComponents(url: Self.origin, resolvingAgainstBaseURL: false)!
        parts.path = path
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url, url.scheme == "https", url.host == Self.origin.host else { throw CloudError.invalidResponse }
        guard let credential = try token ?? tokens.read(), Self.isValidToken(credential) else { throw CloudError.disconnected }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    func books(query: String = "", page: Int = 1, format: String = "", sort: CloudSort = .updated, token: String? = nil) async throws -> CloudBookPage {
        let items = [URLQueryItem(name: "query", value: query), .init(name: "page", value: String(page)),
                     .init(name: "page_size", value: "20"), .init(name: "sort", value: sort.rawValue), .init(name: "format", value: format)]
        let result: CloudBookPage = try await json(try request(path: "/api/v1/books", query: items, token: token))
        guard result.page == page, result.pageSize > 0, result.pageSize <= 100, result.total >= 0,
              Set(result.items.map(\.id)).count == result.items.count else { throw CloudError.invalidResponse }
        return result
    }
    func book(_ id: UUID) async throws -> CloudBook {
        let book: CloudBook = try await json(try request(path: "/api/v1/books/\(id.uuidString)"))
        guard book.id == id else { throw CloudError.invalidResponse }
        return book
    }
    func changes(since: String, afterID: UUID? = nil) async throws -> CloudChanges {
        var query = [URLQueryItem(name: "since", value: since), .init(name: "limit", value: "100")]
        if let afterID { query.append(.init(name: "after_id", value: afterID.uuidString)) }
        return try await json(try request(path: "/api/v1/changes", query: query))
    }
    func cover(_ book: CloudBook) async throws -> Data? {
        do {
            let (data, response) = try await session.data(for: request(path: "/api/v1/books/\(book.id.uuidString)/cover"))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return nil }
            guard status == 200 else { throw CloudError.status(status) }
            guard data.count <= 5 * 1024 * 1024, response.mimeType == "image/jpeg" else { throw CloudError.invalidResponse }
            return data
        } catch { throw CloudError.safe(error) }
    }
    private func json<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw CloudError.status(status) }
            guard data.count <= 8 * 1024 * 1024 else { throw CloudError.invalidResponse }
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            do { return try decoder.decode(T.self, from: data) } catch { throw CloudError.invalidResponse }
        } catch { throw CloudError.safe(error) }
    }
}
