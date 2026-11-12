import Foundation

actor SiteAccessPolicy {
    static let shared = SiteAccessPolicy()
    private struct Policy { var rules: [(allow: Bool, pattern: String)]; var expires: Date }
    private var policies: [String: Policy] = [:]
    private var lastRequest: [String: Date] = [:]
    func check(url: URL, session: URLSession) async throws {
        guard let host = url.host, let scheme = url.scheme else { throw ReaderError.message("站点地址无效。") }
        let origin = "\(scheme)://\(host)\(url.port.map { ":\($0)" } ?? "")"
        if policies[origin]?.expires ?? .distantPast < Date() {
            var rules: [(Bool, String)] = []
            if let robots = URL(string: origin + "/robots.txt") {
                var request = URLRequest(url: robots, timeoutInterval: 10)
                request.setValue("QingRead/1.0", forHTTPHeaderField: "User-Agent")
                if let (data, response) = try? await session.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode {
                    if status == 401 || status == 403 { rules = [(false, "/")] }
                    else if status == 429 || status >= 500 { throw ReaderError.message("站点暂时限制访问，请稍后重试。") }
                    else if status == 200, data.count < 1_000_000 { rules = Self.parse(String(decoding: data, as: UTF8.self)) }
                }
            }
            policies[origin] = Policy(rules: rules, expires: Date().addingTimeInterval(3600))
        }
        let path = url.path + (url.query.map { "?" + $0 } ?? "")
        let matching = (policies[origin]?.rules ?? []).filter { rule in
            let expression = "^" + NSRegularExpression.escapedPattern(for: rule.pattern).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\$", with: "$")
            return path.range(of: expression, options: .regularExpression) != nil
        }.sorted { $0.pattern.count == $1.pattern.count ? $0.allow && !$1.allow : $0.pattern.count > $1.pattern.count }
        if matching.first?.allow == false { throw ReaderError.message("站点 robots.txt 禁止访问此路径，已停止读取。") }
        if let last = lastRequest[origin] { let delay = 0.5 - Date().timeIntervalSince(last); if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } }
        lastRequest[origin] = Date()
    }
    static func parse(_ text: String) -> [(allow: Bool, pattern: String)] {
        var matching = false; var sawRule = false; var result: [(Bool, String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.components(separatedBy: "#")[0]
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if key == "user-agent" { if sawRule { matching = false; sawRule = false }; matching = matching || value == "*" || value.lowercased().contains("qingread") }
            else if key == "allow" || key == "disallow" { sawRule = true; if matching && !value.isEmpty { result.append((key == "allow", value)) } }
        }
        return result
    }
}
