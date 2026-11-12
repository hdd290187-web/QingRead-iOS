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
                .tabItem { Label("找书", systemImage: "magnifyingglass") }
                .tag(1)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(.primary)
        .onOpenURL { url in
            imports.openURL(url, library: library)
            selectedTab = 0
        }
        .task {
            #if DEBUG
            await library.seedUITestBookIfRequested()
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

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @ObservedObject var imports: DocumentImportController
    @State private var selectedBook: Book?
    @State private var showGrid = false

    private var filteredBooks: [Book] {
        guard !query.isEmpty else { return library.books }
        return library.books.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.author.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let status = imports.status, !library.isImporting {
                    HStack {
                        Text(status).font(.subheadline).accessibilityIdentifier("import.status")
                        Spacer()
                        if let feedback = imports.lastFeedback { Button("查看结果") { imports.feedback = feedback }.accessibilityIdentifier("import.showResult") }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                Group { if filteredBooks.isEmpty { emptyState } else { bookList } }
            }
            .overlay {
                if library.isImporting || imports.awaitingImport {
                    VStack(spacing: 8) {
                        ProgressView("正在导入…")
                        if let progress = library.importProgress {
                            Text("\(progress.current) / \(progress.total) · \(progress.stage.rawValue)").font(.caption)
                            Text(progress.fileName).font(.caption).lineLimit(1)
                        }
                    }.padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("import.progress")
                }
            }
            .navigationTitle("书架")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书名或作者")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { imports.openPicker() } label: { Image(systemName: "plus") }.accessibilityLabel("导入书籍").accessibilityIdentifier("library.import").disabled(library.isImporting || imports.awaitingImport)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { showGrid.toggle() } } label: { Image(systemName: showGrid ? "list.bullet" : "square.grid.2x2") }.accessibilityLabel(showGrid ? "列表视图" : "网格视图")
                }
            }
            .sheet(isPresented: $imports.pickerPresented, onDismiss: {
                if !imports.awaitingImport && imports.status == nil { imports.cancelled() }
            }) {
                bookPicker
            }
            .onChange(of: imports.lastFeedback?.id) { _, _ in query = "" }
            .fullScreenCover(item: $selectedBook) { book in ReaderView(book: book) }
        }
    }

    private var bookPicker: some View {
        BookDocumentPicker { result in
            query = ""
            imports.consume(result, library: library)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView { Label("书架是空的", systemImage: "books.vertical") } description: { Text("导入 TXT 或 EPUB，打开后会自动保存阅读位置") } actions: { Button("导入书籍") { imports.openPicker() }.buttonStyle(.borderedProminent).disabled(library.isImporting || imports.awaitingImport) }
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
