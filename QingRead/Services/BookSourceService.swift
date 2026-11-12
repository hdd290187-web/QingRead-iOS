import Foundation

struct OnlineBook: Hashable, Identifiable {
    let id: String
    var title: String
    var author: String
    var detailURL: URL?
    var contentURL: URL?
    var source: BookSource
}
struct BookSourceService {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    static func importSources(_ data: Data) throws -> [BookSource] {
        guard data.count <= 5_000_000 else { throw ReaderError.message("书源文件超过 5 MB，请拆分后导入。") }
        let json = try JSONSerialization.jsonObject(with: data)
        let objects: [[String: Any]]
        if let array = json as? [[String: Any]] { objects = array }
        else if let object = json as? [String: Any] { objects = (object["sources"] as? [[String: Any]]) ?? [object] }
        else { throw ReaderError.message("书源 JSON 必须是对象或数组。") }
        guard !objects.isEmpty else { throw ReaderError.message("书源数组为空。") }
        return try objects.map { object in
            let name = object["bookSourceName"] as? String ?? object["name"] as? String ?? "未命名书源"
            guard let searchURL = object["searchUrl"] as? String ?? object["searchURL"] as? String, !searchURL.isEmpty else { throw ReaderError.message("\(name)：缺少 searchUrl。") }
            let base = object["bookSourceUrl"] as? String ?? object["baseUrl"] as? String ?? searchURL.components(separatedBy: "{{")[0]
            guard let baseURL = URL(string: base), ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") else { throw ReaderError.message("\(name)：书源地址必须为 HTTP/HTTPS。") }
            var issues: [String] = []
            func rules(_ key: String) -> [String: String] {
                guard let dictionary = object[key] as? [String: Any] else { return [:] }
                var result: [String: String] = [:]
                for (field, value) in dictionary { if let value = value as? String { result[field] = value } else if let value = value as? Bool { result[field] = value ? "true" : "false" } else { issues.append("\(key).\(field)：规则必须为字符串。") } }
                return result
            }
            let search = rules("ruleSearch"), info = rules("ruleBookInfo"), toc = rules("ruleToc"), content = rules("ruleContent")
            for (field, rule) in [search, info, toc, content].flatMap({ Array($0) }) where !rule.isEmpty {
                if rule.contains("@js:") || rule.contains("<js>") || rule.contains("{{") { issues.append("\(field)：不支持 JavaScript 或动态模板。") }
                if rule.hasPrefix("//") || rule.contains("@XPath:") || rule.contains("@xpath:") { issues.append("\(field)：不支持 XPath。") }
                if rule.contains("&&") || rule.contains("@put:") || rule.contains("@get:") || rule.contains("$..") || rule.contains("[?(") { issues.append("\(field)：不支持规则变量、并联或复杂 JSONPath。") }
                if field == "nextContentUrl" || field == "nextTocUrl" { issues.append("\(field)：不支持网页分页抓取，请使用单页完整章节的书源。") }
            }
            if let type = object["bookSourceType"] as? Int, type != 0 { issues.append("仅支持文字书源，不支持音频等其他类型。") }
            if object["loginUrl"] != nil || object["loginUi"] != nil { issues.append("不支持登录、验证码或 Cookie 书源。") }
            if searchURL.contains(",{\"") || searchURL.contains("<js>") || searchURL.contains("@js:") { issues.append("搜索仅支持 GET URL，不支持 POST 或签名脚本。") }
            let remainingTemplate = searchURL.replacingOccurrences(of: "{{key}}", with: "").replacingOccurrences(of: "{{page}}", with: "")
            if remainingTemplate.contains("{{") { issues.append("搜索模板仅支持 {{key}} 和 {{page}}。") }
            var headers = object["header"] as? [String: String] ?? [:]
            if let encoded = object["header"] as? String, let headerData = encoded.data(using: .utf8), let parsed = try? JSONDecoder().decode([String: String].self, from: headerData) { headers = parsed }
            if headers.keys.contains(where: { ["cookie", "authorization"].contains($0.lowercased()) }) { issues.append("不支持含登录凭据的请求头。"); headers = headers.filter { !["cookie", "authorization"].contains($0.key.lowercased()) } }
            return BookSource(name: name, baseURL: base, searchURL: searchURL, headers: headers, search: search, info: info, toc: toc, content: content, issues: Array(Set(issues)).sorted(), enabled: issues.isEmpty && (object["enabled"] as? Bool ?? true))
        }
    }
    func downloadSource(_ raw: String) async throws -> Data {
        var urlString = raw
        if raw.hasPrefix("https://github.com/"), raw.contains("/blob/") { urlString = raw.replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/").replacingOccurrences(of: "/blob/", with: "/") }
        guard let url = URL(string: urlString) else { throw ReaderError.message("书源 URL 无效。") }
        return try await fetch(url: url, headers: [:], respectRobots: false)
    }
    func search(_ query: String, source: BookSource) async throws -> [OnlineBook] {
        guard source.enabled, source.issues.isEmpty else { throw ReaderError.message(source.compatibilityNote) }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let search = source.searchURL.replacingOccurrences(of: "{{key}}", with: encoded).replacingOccurrences(of: "{{page}}", with: "1")
        guard var url = URL(string: search, relativeTo: URL(string: source.baseURL))?.absoluteURL else { throw ReaderError.message("搜索 URL 无效。") }
        if !source.searchURL.contains("{{key}}"), source.search.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: true) { components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: query)]; url = components.url ?? url }
        let data = try await fetch(url: url, headers: source.headers)
        return try Self.parseSearch(data: data, url: url, source: source)
    }
    static func parseSearch(data: Data, url: URL, source: BookSource) throws -> [OnlineBook] {
        let document = try RuleDocument(data: data, baseURL: url.absoluteString)
        let listRule = source.search["bookList"] ?? ""
        let nodes: [RuleNode]
        if listRule.isEmpty, case .json(let object) = document.root { nodes = ((object as? [Any]) ?? (object as? [String: Any])?["books"] as? [Any] ?? []).map { .json($0) } }
        else { nodes = try document.nodes(listRule) }
        return try nodes.prefix(200).enumerated().compactMap { index, node in
            let title = try document.value(source.search["name"] ?? "title", from: node)
            guard !title.isEmpty else { return nil }
            let author = try document.value(source.search["author"] ?? "author", from: node)
            let link = try document.value(source.search["bookUrl"] ?? "url", from: node)
            let content = try document.value(source.search["contentUrl"] ?? "contentUrl", from: node)
            return OnlineBook(id: "\(source.id)-\(index)-\(link)", title: title, author: author.isEmpty ? "未知作者" : author, detailURL: resolved(link, base: url), contentURL: resolved(content, base: url), source: source)
        }
    }
    func chapters(for item: OnlineBook) async throws -> [Chapter] {
        if let direct = item.contentURL { return [Chapter(title: item.title, remoteURL: direct)] }
        guard let detail = item.detailURL else { throw ReaderError.message("搜索结果缺少书籍 URL。") }
        let detailData = try await fetch(url: detail, headers: item.source.headers)
        var tocURL = detail
        if let rule = item.source.info["tocUrl"], !rule.isEmpty {
            let document = try RuleDocument(data: detailData, baseURL: detail.absoluteString)
            if let extracted = Self.resolved(try document.value(rule), base: detail) { tocURL = extracted }
        }
        let data = tocURL == detail ? detailData : try await fetch(url: tocURL, headers: item.source.headers)
        return try Self.parseChapters(data: data, url: tocURL, source: item.source)
    }
    static func parseChapters(data: Data, url: URL, source: BookSource) throws -> [Chapter] {
        let document = try RuleDocument(data: data, baseURL: url.absoluteString)
        let rule = source.toc["chapterList"] ?? "$.chapters[*]"
        let nodes = try document.nodes(rule)
        var visited = Set<URL>()
        var result = try nodes.prefix(20000).compactMap { node -> Chapter? in
            let title = try document.value(source.toc["chapterName"] ?? "title", from: node)
            let raw = try document.value(source.toc["chapterUrl"] ?? "url", from: node)
            guard !title.isEmpty, let link = resolved(raw, base: url), visited.insert(link).inserted else { return nil }
            return Chapter(title: title, remoteURL: link)
        }
        if source.toc["isReverse"] == "true" { result.reverse() }
        guard !result.isEmpty else { throw ReaderError.message("未解析到目录，请检查 chapterList/chapterName/chapterUrl。") }
        return result
    }
    func chapterText(url: URL, source: BookSource) async throws -> String {
        let data = try await fetch(url: url, headers: source.headers)
        let document = try RuleDocument(data: data, baseURL: url.absoluteString)
        var content: String
        if let rule = source.content["content"], !rule.isEmpty { content = try document.value(rule, preserveLines: true) }
        else if case .json(let object) = document.root { content = (object as? [String: Any])?["content"] as? String ?? (object as? [String: Any])?["text"] as? String ?? "" }
        else { content = try RuleDocument.cleanHTML(TXTParser.decode(data).text) }
        if let replace = source.content["replaceRegex"], !replace.isEmpty {
            let pieces = replace.components(separatedBy: "##")
            let regex = try NSRegularExpression(pattern: pieces[0])
            content = regex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: pieces.count > 1 ? pieces[1] : "")
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReaderError.message("正文为空，请检查书源正文规则。") }
        return content
    }
    static func resolved(_ link: String, base: URL) -> URL? {
        guard !link.isEmpty, let url = URL(string: link, relativeTo: base)?.absoluteURL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }; return url
    }
    private func fetch(url: URL, headers: [String: String], respectRobots: Bool = true) async throws -> Data {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw ReaderError.message("仅支持 HTTP/HTTPS 书源。") }
        if respectRobots { try await SiteAccessPolicy.shared.check(url: url, session: session) }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("QingRead/1.0 (personal reading)", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReaderError.message("站点返回无效响应。") }
        guard (200...299).contains(response.statusCode) else { throw ReaderError.message("站点返回 HTTP \(response.statusCode)。请遵守访问限制，稍后重试或更换有权访问的书源。") }
        guard data.count <= 12_000_000 else { throw ReaderError.message("站点响应超过 12 MB，已停止处理。") }
        return data
    }
}
