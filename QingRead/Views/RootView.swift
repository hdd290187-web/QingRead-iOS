import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selectedTab = 0
    @StateObject private var imports = DocumentImportController()

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView(imports: imports)
                .tabItem { Label("书架", systemImage: "books.vertical.fill") }
                .tag(0)
            DiscoverView()
                .tabItem { Label("发现", systemImage: "safari") }
                .tag(1)
            SettingsView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(2)
        }
        .tint(YYTheme.accent)
        .toolbarBackground(YYTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onOpenURL { url in
            imports.openURL(url, library: library)
            selectedTab = 0
        }
        .task {
            #if DEBUG
            await library.seedUITestBookIfRequested()
            await library.seedBrandBooksIfRequested()
            await library.seedReaderPerformanceIfRequested()
            library.seedImportPickerDocumentsIfRequested()
            if let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--uitest-import-result=") }) {
                let directory = library.importTestFixtureDirectory
                switch String(mode.dropFirst("--uitest-import-result=".count)) {
                case "selected": imports.consume(.success([directory.appendingPathComponent("系统文件测试.txt")]), library: library)
                case "partial": imports.consume(.success([directory.appendingPathComponent("系统文件测试.txt"), directory.appendingPathComponent("空白文件.txt")]), library: library)
                case "failure": imports.consume(.failure(CocoaError(.fileReadNoPermission)), library: library)
                case "empty": imports.consume(.success([]), library: library)
                case "cancel": imports.consume(.failure(CocoaError(.userCancelled)), library: library)
                default: break
                }
            }
            #endif
        }
        .sheet(item: $imports.feedback) { ImportFeedbackView(feedback: $0) }
        .alert("操作提示", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("知道了", role: .cancel) { library.lastError = nil }
        } message: { Text(library.lastError ?? "") }
    }
}

private enum ShelfSort: String, CaseIterable, Identifiable {
    case imported, recent, title, progress
    var id: String { rawValue }
    var title: String { switch self { case .imported: "最近导入"; case .recent: "最近阅读"; case .title: "书名"; case .progress: "阅读进度" } }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @ObservedObject var imports: DocumentImportController
    @State private var selectedBook: Book?
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @AppStorage("yuying.library.grid") private var showGrid = true
    @AppStorage("yuying.library.sort") private var sortValue = ShelfSort.imported.rawValue

    private var filteredBooks: [Book] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let books = library.books.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) || $0.author.localizedCaseInsensitiveContains(term) }
        return books.sorted { left, right in
            switch ShelfSort(rawValue: sortValue) ?? .imported {
            case .imported: return left.importedAt > right.importedAt
            case .recent: return (library.positions[left.id]?.updatedAt ?? left.importedAt) > (library.positions[right.id]?.updatedAt ?? right.importedAt)
            case .title: return left.title.localizedStandardCompare(right.title) == .orderedAscending
            case .progress: return library.position(for: left).progression > library.position(for: right).progression
            }
        }
    }
    private var importDisabled: Bool { library.isImporting || imports.awaitingImport }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                shelfHeader
                if showSearch { searchField }
                if let status = imports.status, !library.isImporting {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.caption)
                        Text(status).font(.caption).accessibilityIdentifier("import.status")
                        Spacer(minLength: 0)
                        if let feedback = imports.lastFeedback { Button("查看结果") { imports.feedback = feedback }.font(.caption).accessibilityIdentifier("import.showResult") }
                    }.foregroundStyle(YYTheme.secondary).padding(.horizontal, YYTheme.screenInset).padding(.vertical, 10)
                }
                Group {
                    if library.books.isEmpty { emptyState }
                    else if filteredBooks.isEmpty { ContentUnavailableView.search(text: query) }
                    else { bookList }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(YYTheme.background)
            .overlay {
                if importDisabled {
                    VStack(spacing: 8) {
                        ProgressView("正在导入…")
                        if let progress = library.importProgress {
                            Text("\(progress.current) / \(progress.total) · \(progress.stage.rawValue)").font(.caption)
                            Text(progress.fileName).font(.caption).lineLimit(1)
                        }
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("import.progress")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(YYTheme.background, for: .tabBar)
            .sheet(isPresented: $imports.pickerPresented, onDismiss: {
                if !imports.awaitingImport && imports.status == nil { imports.cancelled() }
            }) { bookPicker }
            .onChange(of: imports.lastFeedback?.id) { _, _ in query = ""; showSearch = false; searchFocused = false }
            .fullScreenCover(item: $selectedBook) { book in ReaderView(book: book) }
            .yyPage()
        }
    }
    private var shelfHeader: some View {
        HStack(spacing: 0) {
            Text("书架").font(YYTheme.title(26)).fixedSize().foregroundStyle(YYTheme.foreground)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("library.title")
            Menu {
                Picker("排序", selection: $sortValue) { ForEach(ShelfSort.allCases) { Text($0.title).tag($0.rawValue) } }
                Divider()
                Button { showGrid.toggle() } label: { Label(showGrid ? "列表视图" : "网格视图", systemImage: showGrid ? "list.bullet" : "square.grid.2x2") }
            } label: { Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(YYTheme.secondary).frame(width: 32, height: 44) }
                .accessibilityLabel("书架选项").accessibilityIdentifier("library.options")
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) { showSearch.toggle() }
                if showSearch { searchFocused = true } else { query = "" }
            } label: { Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44) }
                .accessibilityLabel("搜索书架").accessibilityIdentifier("library.search")
            Button { imports.openPicker() } label: { Image(systemName: "plus").font(.system(size: 25, weight: .light)).frame(width: 44, height: 44) }
                .accessibilityLabel("导入书籍").accessibilityIdentifier("library.import").disabled(importDisabled)
        }.foregroundStyle(YYTheme.foreground).buttonStyle(.plain).frame(height: 56).padding(.horizontal, YYTheme.screenInset)
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(YYTheme.secondary)
            TextField("搜索书名或作者", text: $query).focused($searchFocused).submitLabel(.search)
                .accessibilityIdentifier("library.searchField")
            Button { query = ""; showSearch = false; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(YYTheme.secondary) }.accessibilityLabel("关闭搜索")
        }.padding(12).background(YYTheme.separator.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, YYTheme.screenInset).padding(.top, 12).padding(.bottom, 4)
    }
    private var bookPicker: some View {
        BookDocumentPicker { result in
            query = ""
            imports.consume(result, library: library)
        }
    }
    private var emptyState: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                PaperWaves().fill(YYTheme.selection.opacity(0.35)).frame(height: proxy.size.height * 0.25).allowsHitTesting(false)
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    BrandMark(width: 102).padding(.bottom, 22)
                    Text(YYTheme.name).font(YYTheme.title(34)).tracking(5).foregroundStyle(YYTheme.foreground)
                    Text(YYTheme.subtitle).font(.system(size: 12)).tracking(2).foregroundStyle(YYTheme.secondary).padding(.top, 14)
                    Text("你的书架，从这里开始").font(.subheadline).foregroundStyle(YYTheme.secondary).padding(.top, 38)
                    Button { imports.openPicker() } label: {
                        Label("导入第一本书", systemImage: "plus").font(.system(size: 15, weight: .medium)).padding(.horizontal, 24).padding(.vertical, 14)
                    }.buttonStyle(.plain).foregroundStyle(YYTheme.foreground).background(YYTheme.selection, in: Capsule()).padding(.top, 18)
                        .accessibilityIdentifier("library.emptyImport").disabled(importDisabled)
                    Text("TXT · EPUB  /  阅读位置自动保存").font(.caption2).foregroundStyle(YYTheme.secondary).padding(.top, 16)
                    Spacer(minLength: 40)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 24)
            }
        }
    }
    private var bookList: some View {
        ScrollView {
            if showGrid {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], alignment: .leading, spacing: 26) {
                    ForEach(filteredBooks) { book in
                        BookTile(book: book, progress: library.position(for: book).progression) { selectedBook = book }.contextMenu { removeButton(for: book) }
                    }
                }.padding(.horizontal, YYTheme.screenInset).padding(.top, 24).padding(.bottom, 28)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredBooks) { book in
                        BookRow(book: book, progress: library.position(for: book).progression) { selectedBook = book }.contextMenu { removeButton(for: book) }
                        Rectangle().fill(YYTheme.separator).frame(height: 0.5).padding(.leading, 72)
                    }
                }.padding(.horizontal, YYTheme.screenInset).padding(.top, 12).padding(.bottom, 24)
            }
        }.accessibilityIdentifier("library.books")
    }
    @ViewBuilder private func removeButton(for book: Book) -> some View { Button("删除", role: .destructive) { library.remove(book) } }
}

struct BookRow: View {
    let book: Book
    let progress: Double
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                CoverView(book: book, size: CGSize(width: 56, height: 82))
                VStack(alignment: .leading, spacing: 7) {
                    Text(book.title).font(YYTheme.title(18)).foregroundStyle(YYTheme.foreground).lineLimit(2)
                    Text(book.author).font(.caption).foregroundStyle(YYTheme.secondary).lineLimit(1)
                    Text("已读 \(Int(min(1, max(0, progress)) * 100))%").font(.caption2).foregroundStyle(YYTheme.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(YYTheme.secondary.opacity(0.65))
            }.padding(.vertical, 16).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct BookTile: View {
    let book: Book
    let progress: Double
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                CoverView(book: book)
                Text(book.title).font(YYTheme.title(17, weight: .medium)).foregroundStyle(YYTheme.foreground).lineLimit(2).padding(.top, 10)
                Text("已读 \(Int(min(1, max(0, progress)) * 100))%").font(.system(size: 12)).foregroundStyle(YYTheme.secondary).monospacedDigit().padding(.top, 5)
            }.frame(maxWidth: .infinity, alignment: .topLeading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
