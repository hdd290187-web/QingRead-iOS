import SwiftUI
import UniformTypeIdentifiers

struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var selectedSource: BookSource?
    @State private var results: [OnlineBook] = []
    @State private var isSearching = false
    @State private var message: String?
    @State private var showSourceImporter = false
    @State private var selectedBook: Book?

    var body: some View {
        NavigationStack {
            List {
                Section { HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("搜索小说", text: $query).submitLabel(.search).onSubmit { search() }; if isSearching { ProgressView() } else { Button { search() } label: { Image(systemName: "arrow.right.circle.fill") }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || selectedSource == nil) } }.listRowBackground(Color.clear) }
                Section("书源") {
                    if library.sources.isEmpty { Text("请在设置中导入书源 JSON").foregroundStyle(.secondary) }
                    ForEach(library.sources) { source in Button { selectedSource = source } label: { HStack { Text(source.name); Spacer(); if selectedSource?.id == source.id { Image(systemName: "checkmark") } } } }
                }
                if !results.isEmpty { Section("搜索结果") { ForEach(results) { result in OnlineBookRow(result: result) { importOnline(result) } } } }
                if let message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle("找书")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { SourceGuideView() } label: { Image(systemName: "info.circle") }.accessibilityLabel("书源说明") } }
            .sheet(item: $selectedBook) { ReaderView(book: $0) }
        }
    }

    private func search() {
        guard let source = selectedSource else { return }
        isSearching = true; message = nil
        Task {
            do { results = try await BookSourceService().search(query.trimmingCharacters(in: .whitespacesAndNewlines), source: source) }
            catch { message = error.localizedDescription }
            isSearching = false
        }
    }

    private func importOnline(_ item: OnlineBook) {
        guard let contentURL = item.contentURL else { message = "该结果没有正文地址；请在书源中提供 contentUrl。"; return }
        Task {
            do { let (data, _) = try await URLSession.shared.data(from: contentURL); let book = Book(title: item.title, author: item.author, format: .txt, sourceURL: contentURL, chapters: TXTParser.chapters(from: data, fallbackTitle: item.title), isRemote: true); library.add(book); selectedBook = book }
            catch { message = "在线正文读取失败：\(error.localizedDescription)" }
        }
    }
}

struct OnlineBookRow: View {
    let result: OnlineBook
    let action: () -> Void
    var body: some View { Button(action: action) { HStack { VStack(alignment: .leading, spacing: 4) { Text(result.title).font(.headline); Text(result.author).font(.subheadline).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.down.circle") }.contentShape(Rectangle()) }.buttonStyle(.plain) }
}

struct SourceGuideView: View {
    var body: some View { List { Section("支持范围") { Text("支持简单 JSON 数组或 {books:[...]} 返回值，每项可包含 title、author、contentUrl。searchUrl 可使用 {{key}} 占位符。") }; Section("不兼容") { Text("复杂 XPath/CSS 规则、JavaScript 执行、登录态、动态签名、分页脚本和加密正文不会被执行，导入时会提示。") } }.navigationTitle("书源说明") }
}
