import Foundation
import SwiftUI
import ReadiumShared
import ReadiumNavigator

// One command interface and one persisted position for both format adapters.
@MainActor
protocol ReadingEngine: AnyObject {
    func move(forward: Bool)
    func navigate(to position: ReadingPosition)
    func apply(settings: ReaderSettings)
}

@MainActor
final class ReaderSession: ObservableObject {
    @Published var position: ReadingPosition
    @Published var chapters: [Chapter]
    @Published var menuVisible = true
    @Published var isLoading = false
    @Published var error: String?
    @Published var pageInfo = ""
    let book: Book
    let library: LibraryStore
    weak var engine: (any ReadingEngine)?
    private var textCache: [Int: String] = [:]
    private var downloadTasks: [Int: Task<String, Error>] = [:]
    init(book: Book, library: LibraryStore) {
        self.book = book; self.library = library
        self.position = library.position(for: book)
        self.chapters = library.books.first(where: { $0.id == book.id })?.chapters ?? book.chapters
    }
    func report(_ newPosition: ReadingPosition, pageInfo: String = "") {
        position = newPosition; self.pageInfo = pageInfo
        library.update(position: newPosition, for: book)
        if book.format == .online { prefetch(near: newPosition.chapter) }
    }
    func move(_ forward: Bool) { engine?.move(forward: forward) }
    func jump(_ chapter: Int) {
        guard chapters.indices.contains(chapter) else { return }
        engine?.navigate(to: ReadingPosition(chapter: chapter))
    }
    func restore(_ saved: ReadingPosition) { engine?.navigate(to: saved) }
    func applySettings() { engine?.apply(settings: library.settings) }
    func bookmark() {
        let title = chapters.indices.contains(position.chapter) ? chapters[position.chapter].title : book.title
        library.addBookmark(Bookmark(bookID: book.id, position: position, title: title))
    }
    func text(at index: Int) -> String {
        if let cached = textCache[index] { return cached }
        guard chapters.indices.contains(index) else { return "" }
        var chapter = chapters[index]
        if book.format == .online, chapter.file == nil { chapter.file = library.cachedChapterFile(book: book, index: index) }
        let text = library.chapterText(for: chapter, book: book)
        textCache[index] = text
        trimCache(around: index)
        return text
    }
    func loadText(at index: Int) async throws -> String {
        guard chapters.indices.contains(index) else { return "" }
        let local = text(at: index)
        if !local.isEmpty || book.format != .online { return local }
        if let task = downloadTasks[index] { return try await task.value }
        guard let url = chapters[index].remoteURL, let source = book.source else { throw ReaderError.message("章节缺少正文地址。") }
        let task = Task { try await BookSourceService().chapterText(url: url, source: source) }
        downloadTasks[index] = task
        defer { downloadTasks[index] = nil }
        let content = try await task.value
        try library.cacheChapter(book: book, index: index, text: content)
        chapters[index].length = content.utf16.count
        chapters[index].file = library.cachedChapterFile(book: book, index: index)
        textCache[index] = content; trimCache(around: index)
        return content
    }
    func prefetch(near index: Int) {
        guard book.format == .online, chapters.indices.contains(index + 1) else { return }
        Task { _ = try? await loadText(at: index + 1) }
    }
    private func trimCache(around index: Int) { textCache = textCache.filter { abs($0.key - index) <= 2 } }
    func downloadAll() async {
        isLoading = true; defer { isLoading = false }
        for i in chapters.indices {
            if Task.isCancelled { break }
            do { _ = try await loadText(at: i) } catch { self.error = "缓存到第 \(i + 1) 章时中断：\(error.localizedDescription)"; break }
            pageInfo = "已缓存 \(i + 1) / \(chapters.count) 章"
        }
    }
}
