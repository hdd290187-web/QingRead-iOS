import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var positions: [UUID: ReadingPosition] = [:]
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var isImporting = false
    @Published var settings = ReaderSettings() { didSet { persist() } }
    @Published var sources: [BookSource] = [] { didSet { persist() } }
    @Published var lastError: String?
    private let fm = FileManager.default
    let root: URL
    private var snapshotURL: URL { root.appendingPathComponent("library.json") }
    private var loading = true
    private struct Snapshot: Codable { var books: [Book]; var positions: [UUID: ReadingPosition]; var bookmarks: [Bookmark]; var settings: ReaderSettings; var sources: [BookSource] }
    init(rootURL: URL? = nil) {
        root = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingRead", isDirectory: true)
        load(); loading = false
    }
    @discardableResult
    func importFile(from url: URL) async -> Book? {
        isImporting = true; defer { isImporting = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let id = UUID(); let folder = root.appendingPathComponent("books/\(id.uuidString)", isDirectory: true)
        do {
            let ext = url.pathExtension.lowercased()
            guard ["txt", "epub"].contains(ext) else { throw ReaderError.message("仅支持 TXT 和 EPUB 文件。") }
            let book: Book
            if ext == "txt" {
                book = try await Task.detached(priority: .userInitiated) { try LocalBookImporter.importTXT(url: url, directory: folder, id: id) }.value
            } else {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let original = folder.appendingPathComponent("book.epub")
                try await Task.detached(priority: .userInitiated) { try FileManager.default.copyItem(at: url, to: original) }.value
                let service = EPUBService()
                let publication = try await service.open(path: original.path)
                let toc = (try? await publication.tableOfContents().get()) ?? []
                let chapters = EPUBService.flatten(toc.isEmpty ? publication.readingOrder : toc).map { Chapter(title: $0.title ?? "章节", href: $0.href) }
                book = Book(id: id, title: publication.metadata.title ?? url.deletingPathExtension().lastPathComponent, author: publication.metadata.authors.map(\.name).joined(separator: "、"), format: .epub, chapters: chapters, originalFile: original.path, originURL: url)
            }
            // A successful duplicate import opens the existing record, preserving its progress.
            if let existing = books.first(where: { $0.originURL == url && $0.format == book.format }) { try? fm.removeItem(at: folder); return existing }
            books.insert(book, at: 0); persist(); return book
        } catch { try? fm.removeItem(at: folder); lastError = error.localizedDescription; return nil }
    }
    @discardableResult
    func add(_ input: Book) -> Book {
        var book = input
        if book.format == .online {
            let folder = root.appendingPathComponent("books/\(book.id.uuidString)", isDirectory: true)
            do { try fm.createDirectory(at: folder, withIntermediateDirectories: true); book.originalFile = folder.path }
            catch { lastError = error.localizedDescription }
        }
        if let existing = books.first(where: { $0.originURL != nil && $0.originURL == book.originURL && $0.format == book.format }) { return existing }
        books.removeAll { $0.id == book.id }; books.insert(book, at: 0); persist(); return book
    }
    func remove(_ book: Book) {
        books.removeAll { $0.id == book.id }; positions[book.id] = nil; bookmarks.removeAll { $0.bookID == book.id }
        if let file = book.originalFile {
            let url = URL(fileURLWithPath: file); let folder = book.format == .epub ? url.deletingLastPathComponent() : url
            if folder.standardizedFileURL.path.hasPrefix(root.appendingPathComponent("books").path + "/") { try? fm.removeItem(at: folder) }
        }
        persist()
    }
    func position(for book: Book) -> ReadingPosition { positions[book.id] ?? .beginning }
    func update(position: ReadingPosition, for book: Book) { positions[book.id] = position; persist() }
    func addBookmark(_ bookmark: Bookmark) { bookmarks.append(bookmark); persist() }
    func bookmarks(for book: Book) -> [Bookmark] { bookmarks.filter { $0.bookID == book.id }.sorted { $0.createdAt > $1.createdAt } }
    func deleteBookmark(_ bookmark: Bookmark) { bookmarks.removeAll { $0.id == bookmark.id }; persist() }
    func saveSource(_ source: BookSource) { sources.removeAll { $0.id == source.id || $0.name == source.name && $0.baseURL == source.baseURL }; sources.append(source); persist() }
    func removeSource(at index: Int) { guard sources.indices.contains(index) else { return }; sources.remove(at: index); persist() }
    func cachedChapterFile(book: Book, index: Int) -> String { (book.originalFile ?? "") + "/cached-\(index).txt" }
    func cacheChapter(book: Book, index: Int, text: String) throws {
        guard !text.isEmpty, let record = books.firstIndex(where: { $0.id == book.id }), books[record].chapters.indices.contains(index), let folder = book.originalFile else { throw ReaderError.message("章节缓存目录无效。") }
        try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let file = "cached-\(index).txt"
        try Data(text.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent(file), options: .atomic)
        books[record].chapters[index].file = file; books[record].chapters[index].length = text.utf16.count; persist()
    }
    func chapterText(for chapter: Chapter, book: Book) -> String {
        guard let file = chapter.file else { return "" }
        let path = file.hasPrefix("/") ? file : (book.originalFile ?? "") + "/" + file
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }; return String(decoding: data, as: UTF8.self)
    }
    func flush() { persist() }
    private func load() {
        guard fm.fileExists(atPath: snapshotURL.path) else { return }
        do { let value = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: snapshotURL)); books = value.books; positions = value.positions; bookmarks = value.bookmarks; settings = value.settings; sources = value.sources }
        catch { lastError = "本地书库索引无法读取，请保留原文件并检查存储空间。" }
    }
    private func persist() {
        guard !loading else { return }
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true); let value = Snapshot(books: books, positions: positions, bookmarks: bookmarks, settings: settings, sources: sources); try JSONEncoder().encode(value).write(to: snapshotURL, options: .atomic) }
        catch { lastError = "保存书库失败：\(error.localizedDescription)" }
    }
}
