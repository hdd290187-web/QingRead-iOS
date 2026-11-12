import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var positions: [UUID: ReadingPosition] = [:]
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: ImportProgress?
    private var importQueue: [ImportJob] = []
    private var drainingImports = false
    private var snapshotReadable = true
    private var pendingLocalIdentityMigration = false
    private var activeImportID: UUID?
    let importEnvironment: ImportEnvironment
    private struct ImportJob {
        let urls: [URL]
        let continuation: CheckedContinuation<ImportBatchResult, Never>
    }
    @Published var settings = ReaderSettings() { didSet { persist() } }
    @Published var sources: [BookSource] = [] { didSet { persist() } }
    @Published var lastError: String?
    private let fm = FileManager.default
    let root: URL
    private var snapshotURL: URL { root.appendingPathComponent("library.json") }
    private var loading = true
    struct Snapshot: Codable { var books: [Book]; var positions: [UUID: ReadingPosition]; var bookmarks: [Bookmark]; var settings: ReaderSettings; var sources: [BookSource] }
    init(rootURL: URL? = nil, importEnvironment: ImportEnvironment = .live) {
        self.importEnvironment = importEnvironment
        root = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QingRead", isDirectory: true)
        load(); loading = false
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
    private func writeSnapshot(_ value: Snapshot) throws {
        guard snapshotReadable else { throw ReaderError.message("书库索引无法读取，已阻止覆盖；请保留原文件。") }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Preserve the exact previous index once, before the optional identity migration.
        if pendingLocalIdentityMigration, fm.fileExists(atPath: snapshotURL.path) {
            let backup = root.appendingPathComponent("library-before-import-repair.json")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: snapshotURL, to: backup) }
        }
        try JSONEncoder().encode(value).write(to: snapshotURL, options: .atomic)
        pendingLocalIdentityMigration = false
    }
    private func load() {
        guard fm.fileExists(atPath: snapshotURL.path) else { return }
        do { let value = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: snapshotURL)); books = value.books; positions = value.positions; bookmarks = value.bookmarks; settings = value.settings; sources = value.sources }
        catch { snapshotReadable = false; lastError = "本地书库索引无法读取，已阻止写入以保护原书架。请保留原文件并检查存储空间。" }
    }
    private func persist() {
        guard !loading, snapshotReadable else { return }
        do { try fm.createDirectory(at: root, withIntermediateDirectories: true); let value = Snapshot(books: books, positions: positions, bookmarks: bookmarks, settings: settings, sources: sources); try writeSnapshot(value) }
        catch { lastError = "保存书库失败：\(error.localizedDescription)" }
    }
    @discardableResult
    func importFile(from url: URL) async -> Book? {
        let result = await importFiles(from: [url])
        if let failure = result.failures.first { lastError = failure.message; return nil }
        // Callers historically use the returned record for tests/reader setup. Queue
        // results carry stable IDs, not temporary external URLs.
        guard let id = result.bookIDs.first else { return nil }
        return books.first { $0.id == id }
    }

    func importFiles(from urls: [URL]) async -> ImportBatchResult {
        await withCheckedContinuation { continuation in
            importQueue.append(ImportJob(urls: urls, continuation: continuation))
            if !drainingImports {
                drainingImports = true
                isImporting = true
                Task { await drainImportQueue() }
            }
        }
    }

    private func drainImportQueue() async {
        while !importQueue.isEmpty {
            let job = importQueue.removeFirst()
            var result = ImportBatchResult()
            if job.urls.isEmpty {
                let error = ImportPipelineError(stage: .picker, reason: "文件选择器没有返回文件。", suggestion: "请重新点击加号，选中 TXT 或 EPUB 后点击‘打开’。", underlying: nil)
                result.failures = [ImportDiagnostics.failure(error, stage: .picker, url: URL(fileURLWithPath: "/所选文件"))]
            }
            for (index, url) in job.urls.enumerated() {
                importProgress = ImportProgress(current: index + 1, total: job.urls.count, fileName: ImportDiagnostics.safeDisplayName(url), stage: .permission)
                switch await performImport(url) {
                case .success(let success):
                    result.bookIDs.append(success.book.id)
                    if success.duplicate { result.duplicates.append(success.book.title) }
                    else { result.imported.append(success.book.title) }
                case .failure(let failure): result.failures.append(failure)
                }
            }
            job.continuation.resume(returning: result)
        }
        importProgress = nil; isImporting = false; drainingImports = false
    }

    private struct ImportSuccess { let book: Book; let duplicate: Bool }
    private enum ImportOutcome { case success(ImportSuccess), failure(ImportFailure) }
    private func performImport(_ url: URL) async -> ImportOutcome {
        let id = UUID()
        activeImportID = id
        let staging = root.appendingPathComponent("import-staging/\(id.uuidString)", isDirectory: true)
        let payload = staging.appendingPathComponent("payload", isDirectory: true)
        let finalDirectory = root.appendingPathComponent("books/\(id.uuidString)", isDirectory: true)
        var stage = ImportStage.permission
        var byteCount: Int?
        var moved = false
        var committed = false
        defer {
            activeImportID = nil
            try? fm.removeItem(at: staging)
            if moved && !committed { try? fm.removeItem(at: finalDirectory) }
        }
        func advance(_ next: ImportStage) {
            stage = next
            if var progress = importProgress { progress.stage = next; importProgress = progress }
            ImportDiagnostics.event("advance", stage: next, url: url, byteCount: byteCount)
        }
        do {
            guard snapshotReadable else {
                throw ImportPipelineError(stage: .commit, reason: "书库索引无法读取，已停止导入以保护已有数据。", suggestion: "请保留原书库与原始文件，检查设备空间；不要卸载 App，以免删除可恢复的数据。", underlying: nil)
            }
            advance(.stage)
            let document = try await importEnvironment.stage(url, staging) { [weak self] next in
                Task { @MainActor in
                    guard let self, self.activeImportID == id, var progress = self.importProgress,
                          [.permission, .download, .coordinate, .stage].contains(progress.stage) else { return }
                    progress.stage = next; self.importProgress = progress
                }
            }
            byteCount = document.byteCount
            let ext = url.pathExtension.lowercased()
            advance(.validate)
            let prepared: PreparedLocalBook
            if ext == "txt" {
                advance(.decode)
                prepared = try await Task.detached(priority: .userInitiated) {
                    try LocalBookImporter.prepareTXT(url: document.fileURL, title: url.deletingPathExtension().lastPathComponent, directory: payload, id: id)
                }.value
            } else {
                advance(.epub)
                let original = payload.appendingPathComponent("book.epub")
                do {
                    try fm.createDirectory(at: payload, withIntermediateDirectories: true)
                    try fm.moveItem(at: document.fileURL, to: original)
                } catch {
                    throw ImportPipelineError(stage: .stage, reason: ImportDiagnostics.userReason(error as NSError), suggestion: "请检查设备可用空间后重试。原始文件和已有书架已保留。", underlying: error)
                }
                let service = EPUBService()
                let publication = try await service.open(path: original.path)
                let toc = (try? await publication.tableOfContents().get()) ?? []
                let chapters = EPUBService.flatten(toc.isEmpty ? publication.readingOrder : toc).map { Chapter(title: $0.title ?? "章节", href: $0.href) }
                prepared = PreparedLocalBook(book: Book(id: id, title: publication.metadata.title ?? url.deletingPathExtension().lastPathComponent, author: publication.metadata.authors.map(\.name).joined(separator: "、"), format: .epub, chapters: chapters, originalFile: original.path), identity: "epub:sha256:" + document.identity)
            }
            advance(.parse)
            var identities: [UUID: String] = [:]
            // Migrate old local records in memory. The previous index is backed up
            // before the next successful atomic write; IDs, files and progress stay.
            for record in books where record.format != .online && record.sourceIdentity == nil {
                identities[record.id] = await Task.detached(priority: .utility) { LocalBookImporter.legacyIdentity(for: record) }.value
            }
            // Only merge identity fields into the current library after awaits;
            // a deletion or setting change during preparation must not be undone.
            var updatedBooks = books
            for index in updatedBooks.indices {
                if let identity = identities[updatedBooks[index].id] {
                    updatedBooks[index].sourceIdentity = identity
                    updatedBooks[index].originURL = nil
                    pendingLocalIdentityMigration = true
                }
            }
            if let existing = updatedBooks.first(where: { $0.format == prepared.book.format && $0.sourceIdentity == prepared.identity }) {
                advance(.commit)
                try importEnvironment.beforeCommit(root)
                try writeSnapshot(Snapshot(books: updatedBooks, positions: positions, bookmarks: bookmarks, settings: settings, sources: sources))
                books = updatedBooks
                return .success(ImportSuccess(book: existing, duplicate: true))
            }
            advance(.commit)
            try fm.createDirectory(at: finalDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: payload, to: finalDirectory); moved = true
            var book = prepared.book
            book.sourceIdentity = prepared.identity
            book.originURL = nil
            book.originalFile = book.format == .epub ? finalDirectory.appendingPathComponent("book.epub").path : finalDirectory.path
            updatedBooks.insert(book, at: 0)
            try importEnvironment.beforeCommit(root)
            try writeSnapshot(Snapshot(books: updatedBooks, positions: positions, bookmarks: bookmarks, settings: settings, sources: sources))
            committed = true
            books = updatedBooks
            advance(.complete)
            return .success(ImportSuccess(book: book, duplicate: false))
        } catch {
            return .failure(ImportDiagnostics.failure(error, stage: stage, url: url, byteCount: byteCount))
        }
    }
}
