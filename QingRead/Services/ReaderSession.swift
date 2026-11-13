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
    func flushPosition()
    func containsReadingAnchor(_ position: ReadingPosition) -> Bool
}
extension ReadingEngine {
    func flushPosition() {}
    func containsReadingAnchor(_ position: ReadingPosition) -> Bool { false }
}

@MainActor
final class ReaderSession: ObservableObject {
    @Published var position: ReadingPosition
    @Published var chapters: [Chapter]
    @Published var menuVisible = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var pageInfo = ""
    var settingsPreviewActive = false
    let book: Book
    let library: LibraryStore
    weak var engine: (any ReadingEngine)?
    private var textCache: [Int: String] = [:]
    private var downloadTasks: [Int: Task<String, Error>] = [:]
    private var completedCharacters: [Int] = []
    init(book: Book, library: LibraryStore) {
        self.book = book; self.library = library
        self.position = library.position(for: book)
        self.chapters = library.books.first(where: { $0.id == book.id })?.chapters ?? book.chapters
        rebuildProgressIndex()
    }
    func report(_ newPosition: ReadingPosition, pageInfo: String = "") {
        stage(newPosition, pageInfo: pageInfo)
        commitPosition()
        if book.format == .online { prefetch(near: newPosition.chapter) }
    }
    func stage(_ newPosition: ReadingPosition, pageInfo: String = "") {
        if !sameLocation(position, newPosition) { position = newPosition }
        if self.pageInfo != pageInfo { self.pageInfo = pageInfo }
    }
    private func sameLocation(_ lhs: ReadingPosition, _ rhs: ReadingPosition) -> Bool {
        lhs.chapter == rhs.chapter && lhs.characterOffset == rhs.characterOffset && lhs.locatorJSON == rhs.locatorJSON && lhs.progression == rhs.progression
    }
    private func commitPosition() {
        guard library.positions[book.id] == nil || !sameLocation(library.position(for: book), position) else { return }
        ReaderPerformance.measure(.progressCommit) { library.update(position: position, for: book) }
    }
    func move(_ forward: Bool) { engine?.move(forward: forward) }
    func jump(_ chapter: Int) {
        guard chapters.indices.contains(chapter) else { return }
        engine?.navigate(to: ReadingPosition(chapter: chapter))
    }
    func restore(_ saved: ReadingPosition) { engine?.navigate(to: saved) }
    func applySettings() { engine?.apply(settings: library.settings) }
    func flush() { engine?.flushPosition(); commitPosition(); library.flushSettingsIfNeeded() }
    func progress(chapter: Int, offset: Int) -> Double {
        if book.format == .online {
            let length = chapters.indices.contains(chapter) ? max(1, chapters[chapter].length) : 1
            return min(1, (Double(chapter) + Double(offset) / Double(length)) / Double(max(1, chapters.count)))
        }
        let index = min(max(0, chapter), max(0, completedCharacters.count - 1))
        let completed = completedCharacters.isEmpty ? 0 : completedCharacters[index]
        return min(1, Double(completed + offset) / Double(max(1, completedCharacters.last ?? 0)))
    }
    var hasBookmark: Bool {
        matchingBookmark != nil
    }
    private var matchingBookmark: Bookmark? {
        library.bookmarks(for: book).first { engine?.containsReadingAnchor($0.position) == true } ?? library.matchingBookmark(bookID: book.id, position: position)
    }
    func bookmark() {
        engine?.flushPosition()
        let title = chapters.indices.contains(position.chapter) ? chapters[position.chapter].title : book.title
        if let existing = matchingBookmark { library.deleteBookmark(existing) }
        else { library.addBookmark(Bookmark(bookID: book.id, position: position, title: title)) }
    }
    func loadText(at index: Int) async throws -> String {
        guard chapters.indices.contains(index) else { return "" }
        if let local = textCache[index] { return local }
        if let task = downloadTasks[index] { return try await task.value }
        let chapter = chapters[index]
        let file = chapter.file ?? (book.format == .online ? library.cachedChapterFile(book: book, index: index) : nil)
        let path = file.map { $0.hasPrefix("/") ? $0 : (book.originalFile ?? "") + "/" + $0 }
        let task = Task { () throws -> String in
            let local = await Task.detached(priority: .userInitiated) {
                ReaderPerformance.measure(.fileRead) { () -> String? in
                    guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
                    return String(decoding: data, as: UTF8.self)
                }
            }.value
            if let local, !local.isEmpty { return local }
            guard book.format == .online, let url = chapter.remoteURL, let source = book.source else {
                throw ReaderError.message("章节文件无法读取，请检查本机书籍文件是否完整。")
            }
            let content = try await BookSourceService().chapterText(url: url, source: source)
            try library.cacheChapter(book: book, index: index, text: content)
            chapters[index].length = content.utf16.count
            chapters[index].file = library.cachedChapterFile(book: book, index: index)
            rebuildProgressIndex()
            return content
        }
        downloadTasks[index] = task
        defer { downloadTasks[index] = nil }
        let content = try await task.value
        textCache[index] = content; trimCache(around: index)
        return content
    }
    private func rebuildProgressIndex() {
        completedCharacters = [0]
        for chapter in chapters { completedCharacters.append((completedCharacters.last ?? 0) + chapter.length) }
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
