import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var selectedTab = 0
    @State private var pendingURL: URL?

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem { Label("书架", systemImage: "books.vertical.fill") }
                .tag(0)
            DiscoverView()
                .tabItem { Label("找书", systemImage: "magnifyingglass") }
                .tag(1)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(.primary)
        .onOpenURL { url in
            pendingURL = url
            Task { await library.importFile(from: url) }
            selectedTab = 0
        }
        .alert("导入失败", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("知道了", role: .cancel) { library.lastError = nil }
        } message: { Text(library.lastError ?? "") }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var showImporter = false
    @State private var selectedBook: Book?
    @State private var showGrid = false

    private var filteredBooks: [Book] {
        guard !query.isEmpty else { return library.books }
        return library.books.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredBooks.isEmpty { emptyState } else { bookList }
            }
            .overlay { if library.isImporting { ProgressView("正在导入…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .navigationTitle("书架")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书名或作者")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }.accessibilityLabel("导入书籍")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { showGrid.toggle() } } label: { Image(systemName: showGrid ? "list.bullet" : "square.grid.2x2") }.accessibilityLabel(showGrid ? "列表视图" : "网格视图")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .epub], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { for url in urls { await library.importFile(from: url) } } }
            }
            .fullScreenCover(item: $selectedBook) { book in ReaderView(book: book) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView { Label("书架是空的", systemImage: "books.vertical") } description: { Text("导入 TXT 或 EPUB，打开后会自动保存阅读位置") } actions: { Button("导入书籍") { showImporter = true }.buttonStyle(.borderedProminent) }
    }

    private var bookList: some View {
        ScrollView {
            if showGrid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 16) {
                    ForEach(filteredBooks) { book in BookTile(book: book) { selectedBook = book } .contextMenu { removeButton(for: book) } }
                }.padding(16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredBooks) { book in BookRow(book: book, progress: progress(for: book)) { selectedBook = book } .contextMenu { removeButton(for: book) }; Divider().padding(.leading, 78) }
                }.padding(.horizontal, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func progress(for book: Book) -> Double {
        library.position(for: book).progression
    }

    @ViewBuilder private func removeButton(for book: Book) -> some View { Button("删除", role: .destructive) { library.remove(book) } }
}

struct BookRow: View {
    let book: Book
    let progress: Double
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CoverView(book: book, size: CGSize(width: 54, height: 76))
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 8) { ProgressView(value: progress).tint(.primary); Text("\(Int(progress * 100))%").font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical, 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct BookTile: View {
    let book: Book
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) { CoverView(book: book, size: CGSize(width: 155, height: 210)); Text(book.title).font(.headline).foregroundStyle(.primary).lineLimit(2); Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
    }
}

struct CoverView: View {
    let book: Book
    let size: CGSize
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.18, green: 0.22, blue: 0.23))
            
            VStack(alignment: .leading, spacing: 4) { Text(book.format.title).font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.7)); Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(3) }.padding(10)
        }.frame(width: size.width, height: size.height).clipShape(RoundedRectangle(cornerRadius: 6)).shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
