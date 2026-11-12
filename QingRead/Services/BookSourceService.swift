import Foundation

struct OnlineBook: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var author: String
    var detailURL: URL?
    var contentURL: URL?
}
enum BookSourceError: LocalizedError {
    case invalidJSON, invalidURL, incompatible(String)
    var errorDescription: String? { switch self { case .invalidJSON: "书源 JSON 格式无效"; case .invalidURL: "书源 URL 无效"; case .incompatible(let reason): reason } }
}
struct BookSourceService {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    static func importSources(_ data: Data) throws -> [BookSource] {
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any] ] {
            return try array.map { try importOne($0, data: data) }
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BookSourceError.invalidJSON }
        if let array = object["sources"] as? [[String: Any]] { return try array.map { try importOne($0, data: data) } }
        return [try importOne(object, data: data)]
    }
    static func importOne(_ object: [String: Any], data: Data) throws -> BookSource {
        let name = object["bookSourceName"] as? String ?? object["name"] as? String ?? "未命名书源"
        guard let searchURL = object["searchUrl"] as? String ?? object["searchURL"] as? String, !searchURL.isEmpty else { throw BookSourceError.invalidJSON }
        var issues: [String] = []; let raw = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8) ?? ""
        if raw.contains("<js>") || raw.contains("@js:") || raw.contains("{{") { issues.append("包含 JavaScript/模板规则，当前版本不会执行。") }
        if raw.contains("//") { issues.append("包含 XPath 规则，当前版本只保留 JSON 简单字段。") }
        if object["loginUrl"] != nil { issues.append("包含登录配置，当前版本不保存账号或 Cookie。") }
        // Preserve the source with a visible risk note rather than silently claiming full Legado compatibility.
        return BookSource(name: name, baseURL: object["bookSourceUrl"] as? String ?? searchURL, searchURL: searchURL, issues: issues)
    }
    func downloadSource(_ urlString: String) async throws -> Data { guard let url = URL(string: urlString) else { throw BookSourceError.invalidURL }; let (data, response) = try await session.data(from: url); guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { throw BookSourceError.invalidURL }; return data }
    func chapterText(url: URL, source: BookSource) async throws -> String {
        var request = URLRequest(url: url); source.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }; let (data, response) = try await session.data(for: request); guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { throw BookSourceError.invalidURL }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { for key in ["content", "text", "body"] { if let value = object[key] as? String { return value } } }
        guard let text = String(data: data, encoding: .utf8) else { throw BookSourceError.invalidJSON }; return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func importSource(data: Data) throws -> BookSource {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BookSourceError.invalidJSON }
        return try Self.importOne(object, data: data)
    }
    func search(_ query: String, source: BookSource) async throws -> [OnlineBook] {
        guard var url = URL(string: source.searchURL) else { throw BookSourceError.invalidURL }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if source.searchURL.contains("{{key}}") { url = URL(string: source.searchURL.replacingOccurrences(of: "{{key}}", with: encoded))! }
        else if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) { components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: query)]; url = components.url! }
        var request = URLRequest(url: url); source.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request); guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else { throw BookSourceError.invalidURL }
        let json = try JSONSerialization.jsonObject(with: data); let rows = (json as? [[String: Any]]) ?? (json as? [String: Any])?["books"] as? [[String: Any]]; guard let rows else { throw BookSourceError.invalidJSON }
        return rows.enumerated().compactMap { index, row in guard let title = row["title"] as? String ?? row["name"] as? String else { return nil }; return OnlineBook(id: row["id"] as? String ?? "\(index)-\(title)", title: title, author: row["author"] as? String ?? "未知作者", detailURL: URL(string: row["url"] as? String ?? ""), contentURL: URL(string: row["contentUrl"] as? String ?? "")) }
    }
}
