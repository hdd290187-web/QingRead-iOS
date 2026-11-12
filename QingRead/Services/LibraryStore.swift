import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var positions: [UUID: ReadingPosition] = [:]
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var settings = ReaderSettings() { didSet { persist() } }
    @Published var sources: [BookSource] = [] { didSet { persist() } }
    @Published var lastError: String?

    private let fm = FileManager.default
    private var root: URL { fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingRead", isDirectory: true) }
    private var snapshotURL: URL { root.appendingPathComponent("library.json") }
    private struct Snapshot: Codable { var books: [Book]; var positions: [UUID: ReadingPosition]; var bookmarks: [Bookmark]; var settings: ReaderSettings; var sources: [BookSource] }

    init() { load() }

    func importFile(from url: URL) {
        do {
            let accessing = url.startAccessingSecurityScopedResource(); defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let id = UUID(); let folder = root.appendingPathComponent("books/\(id.uuidString)", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let ext = url.pathExtension.lowercased(); guard ext == "txt" || ext == "epub" else { throw ReaderError.message("仅支持 TXT 和 EPUB 文件。") }
            let data = try Data(contentsOf: url); let book: Book
            if ext == "txt" {
                let decoded = try TXTParser.decode(data); let sections = try TXTParser.sections(from: decoded.text, title: url.deletingPathExtension().lastPathComponent)
                var chapters: [Chapter] = []
                for (index, section) in sections.enumerated() { let file = "chapter-\(index).txt"; try section.text.data(using: .utf8)?.write(to: folder.appendingPathComponent(file), options: .atomic); chapters.append(Chapter(title: section.title, length: section.text.utf16.count, file: file)) }
                book = Book(title: url.deletingPathExtension().lastPathComponent, format: .txt, chapters: chapters, originalFile: folder.path, originURL: url)
            } else {
                let localFile = folder.appendingPathComponent("book.epub"); try data.write(to: localFile, options: .atomic)
                book = Book(title: url.deletingPathExtension().lastPathComponent, format: .epub, chapters: [Chapter(title: "目录", length: 1)], originalFile: localFile.path, originURL: url)
            }
            books.removeAll { $0.originURL?.standardizedFileURL == url.standardizedFileURL }; books.insert(book, at: 0); persist()
        } catch { lastError = error.localizedDescription }
    }

    func add(_ book: Book) { books.removeAll { $0.id == book.id }; books.insert(book, at: 0); persist() }
    func remove(_ book: Book) { books.removeAll { $0.id == book.id }; positions[book.id] = nil; bookmarks.removeAll { $0.bookID == book.id }; if let path = book.originalFile { try? fm.removeItem(atPath: path) }; persist() }
    func position(for book: Book) -> ReadingPosition { positions[book.id] ?? .beginning }
    func update(position: ReadingPosition, for book: Book) { positions[book.id] = position; persist() }
    func addBookmark(_ bookmark: Bookmark) { bookmarks.append(bookmark); persist() }
    func bookmarks(for book: Book) -> [Bookmark] { bookmarks.filter { $0.bookID == book.id }.sorted { $0.createdAt > $1.createdAt } }
    func deleteBookmark(_ bookmark: Bookmark) { bookmarks.removeAll { $0.id == bookmark.id }; persist() }
    func saveSource(_ source: BookSource) { sources.removeAll { $0.id == source.id }; sources.append(source); persist() }
    func removeSource(at index: Int) { guard sources.indices.contains(index) else { return }; sources.remove(at: index); persist() }
    func cachedChapterFile(book: Book, index: Int) -> String { (book.originalFile ?? "") + "/cached-\(index).txt" }
    func cacheChapter(book: Book, index: Int, text: String) throws { try text.data(using: .utf8)?.write(to: URL(fileURLWithPath: cachedChapterFile(book: book, index: index)), options: .atomic) }
    func chapterText(for chapter: Chapter, book: Book) -> String {
        guard let file = chapter.file else { return "" }; let path = file.hasPrefix("/") ? file : (book.originalFile ?? "") + "/" + file
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }; return String(decoding: data, as: UTF8.self)
    }
    private func load() { guard let data = try? Data(contentsOf: snapshotURL), let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }; books = value.books; positions = value.positions; bookmarks = value.bookmarks; settings = value.settings; sources = value.sources }
    private func persist() { do { try fm.createDirectory(at: root, withIntermediateDirectories: true); let value = Snapshot(books: books, positions: positions, bookmarks: bookmarks, settings: settings, sources: sources); try JSONEncoder().encode(value).write(to: snapshotURL, options: .atomic) } catch { lastError = error.localizedDescription } }
}
