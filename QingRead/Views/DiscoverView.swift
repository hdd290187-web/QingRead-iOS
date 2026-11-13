import SwiftUI

struct DiscoverView: View {
    @State private var section = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("发现", selection: $section) { Text("云书库").tag(0); Text("在线书源").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal, YYTheme.screenInset).padding(.vertical, 8)
                    .accessibilityIdentifier("discover.section")
                if section == 0 { CloudLibraryView() } else { OnlineSourcesView() }
            }.navigationTitle("发现").yyPage()
        }
    }
}

private struct OnlineSourcesView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var selectedSource: BookSource?
    @State private var results: [OnlineBook] = []
    @State private var busy = false
    @State private var message: String?
    @State private var selectedBook: Book?
    var body: some View {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索小说", text: $query).submitLabel(.search).onSubmit(search)
                        if busy { ProgressView() }
                        else { Button(action: search) { Image(systemName: "arrow.right.circle.fill") }.accessibilityLabel("开始搜索").disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || selectedSource == nil) }
                    }
                }
                Section("书源") {
                    if library.sources.isEmpty { NavigationLink("导入书源 JSON") { SourceManagerView() } }
                    ForEach(library.sources) { source in
                        Button { selectedSource = source } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name)
                                    if !source.issues.isEmpty { Text("不兼容，已禁用").font(.caption).foregroundStyle(.orange) }
                                }
                                Spacer()
                                if selectedSource?.id == source.id { Image(systemName: "checkmark") }
                            }
                        }.disabled(!source.enabled || busy)
                    }
                }
                if !results.isEmpty { Section("搜索结果") { ForEach(results) { result in OnlineBookRow(result: result) { open(result) }.disabled(busy) } } }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }
            .yyPage()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SourceGuideView() } label: { Image(systemName: "info.circle") }.accessibilityLabel("书源说明") } }
            .fullScreenCover(item: $selectedBook) { ReaderView(book: $0) }
            .onAppear { if selectedSource == nil { selectedSource = library.sources.first(where: { $0.enabled }) } }
    }
    private func search() {
        guard !busy, let source = selectedSource, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; message = nil; results = []
        Task { defer { busy = false }; do { results = try await BookSourceService().search(query.trimmingCharacters(in: .whitespacesAndNewlines), source: source); if results.isEmpty { message = "没有找到结果，请检查关键字或书源规则。" } } catch { message = error.localizedDescription } }
    }
    private func open(_ item: OnlineBook) {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                let chapters = try await BookSourceService().chapters(for: item)
                let book = Book(title: item.title, author: item.author, format: .online, chapters: chapters, source: item.source, originURL: item.detailURL ?? item.contentURL)
                selectedBook = library.add(book)
            } catch { message = "在线目录读取失败：\(error.localizedDescription)" }
        }
    }
}
struct OnlineBookRow: View {
    let result: OnlineBook
    let action: () -> Void
    var body: some View { Button(action: action) { HStack { VStack(alignment: .leading, spacing: 4) { Text(result.title).font(.headline); Text(result.author).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "book") } }.buttonStyle(.plain) }
}
struct SourceGuideView: View {
    var body: some View {
        List {
            Section("支持范围") { Text("Legado/阅读 3.0 的 CSS、class/id/tag 简写、@text/@href/@html、基础 JSONPath、## 正则清洗和 || 备选规则。支持 GET 搜索 {{key}} / {{page}}；目录和正文支持完整单页内容。") }
            Section("不兼容") { Text("JavaScript、XPath、变量存取、POST、动态签名、登录/验证码、复杂 JSONPath 和网页多页拼接。导入时逐条标注并禁用相关书源。") }
            Section("资源使用") { Text("只导入你有权访问的资源。阅读器尊重站点 robots.txt 禁止路径和 HTTP 限流；未内置盗版书源或完整小说。站点改版可能导致规则失效。") }
        }.navigationTitle("书源说明").yyPage()
    }
}
