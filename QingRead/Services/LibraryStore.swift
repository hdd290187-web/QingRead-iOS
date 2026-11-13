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
    private var pendingReaderSettingsMigration = false
    private var settingsWriteTask: Task<Void, Never>?
    private var activeImportID: UUID?
    private(set) var activeReaderIDs: Set<UUID> = []
    func readerOpened(_ id: UUID) { activeReaderIDs.insert(id) }
    func readerClosed(_ id: UUID) { activeReaderIDs.remove(id) }
    let importEnvironment: ImportEnvironment
    private struct ImportJob {
        let urls: [URL]
        let cloud: CloudImportContext?
        let continuation: CheckedContinuation<ImportBatchResult, Never>
    }
    @Published var settings = ReaderSettings() { didSet { scheduleSettingsWrite() } }
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
    func addBookmark(_ bookmark: Bookmark) {
        guard !bookmarks.contains(where: { $0.locationKey == bookmark.locationKey }) else { return }
        bookmarks.append(bookmark); persist()
    }
    func matchingBookmark(bookID: UUID, position: ReadingPosition) -> Bookmark? {
        let key = Bookmark(bookID: bookID, position: position, title: "").locationKey
        return bookmarks.first { $0.locationKey == key }
    }
    func toggleBookmark(bookID: UUID, position: ReadingPosition, title: String) {
        let item = Bookmark(bookID: bookID, position: position, title: title)
        if bookmarks.contains(where: { $0.locationKey == item.locationKey }) { bookmarks.removeAll { $0.locationKey == item.locationKey }; persist() }
        else { addBookmark(item) }
    }
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
    func flushSettingsIfNeeded() { if settingsWriteTask != nil { persist() } }
    private func scheduleSettingsWrite() {
        guard !loading else { return }
        settingsWriteTask?.cancel()
        settingsWriteTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self, !Task.isCancelled else { return }; persist()
        }
    }
    private func writeSnapshot(_ value: Snapshot) throws {
        guard snapshotReadable else { throw ReaderError.message("书库索引无法读取，已阻止覆盖；请保留原文件。") }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Preserve the exact previous index once, before the optional identity migration.
        if pendingLocalIdentityMigration, fm.fileExists(atPath: snapshotURL.path) {
            let backup = root.appendingPathComponent("library-before-import-repair.json")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: snapshotURL, to: backup) }
        }
        if pendingReaderSettingsMigration, fm.fileExists(atPath: snapshotURL.path) {
            let backup = root.appendingPathComponent("library-before-build44.json")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: snapshotURL, to: backup) }
        }
        try JSONEncoder().encode(value).write(to: snapshotURL, options: .atomic)
        settingsWriteTask?.cancel(); settingsWriteTask = nil
        pendingReaderSettingsMigration = false
        pendingLocalIdentityMigration = false
    }
    private func load() {
        guard fm.fileExists(atPath: snapshotURL.path) else { return }
        do {
            let bytes = try Data(contentsOf: snapshotURL)
            let value = try JSONDecoder().decode(Snapshot.self, from: bytes)
            books = value.books; positions = value.positions; settings = value.settings; sources = value.sources
            var seen = Set<String>()
            bookmarks = value.bookmarks.filter { seen.insert($0.locationKey).inserted }
            let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            pendingReaderSettingsMigration = (object?["settings"] as? [String: Any])?["showBottomProgress"] == nil || bookmarks.count != value.bookmarks.count
        }
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
            importQueue.append(ImportJob(urls: urls, cloud: nil, continuation: continuation))
            if !drainingImports {
                drainingImports = true
                isImporting = true
                Task { await drainImportQueue() }
            }
        }
    }

    func localBook(cloudID: UUID) -> Book? {
        books.first { $0.cloudLinks?.contains(where: { $0.id == cloudID }) == true }
    }

    func importCloudFile(from url: URL, context: CloudImportContext) async throws -> Book {
        let result: ImportBatchResult = await withCheckedContinuation { continuation in
            importQueue.append(ImportJob(urls: [url], cloud: context, continuation: continuation))
            if !drainingImports {
                drainingImports = true; isImporting = true
                Task { await drainImportQueue() }
            }
        }
        if context.cancellation.isCancelled { throw CloudError.cancelled }
        if let failure = result.failures.first { throw ReaderError.message(failure.message) }
        guard let id = result.bookIDs.first, let book = books.first(where: { $0.id == id }) else { throw CloudError.invalidResponse }
        return book
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
                switch await performImport(url, cloud: job.cloud) {
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
    private func performImport(_ url: URL, cloud: CloudImportContext? = nil) async -> ImportOutcome {
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
            if cloud?.cancellation.isCancelled == true { throw CloudError.cancelled }
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
            if let cloud, document.identity != cloud.book.sha256 || Int64(document.byteCount) != cloud.book.fileSize {
                throw CloudError.integrity
            }
            let ext = url.pathExtension.lowercased()
            advance(.validate)
            let prepared: PreparedLocalBook
            if ext == "txt" {
                advance(.decode)
                let title = cloud?.book.title ?? url.deletingPathExtension().lastPathComponent
                let preferredEncoding = cloud?.book.encoding
                prepared = try await Task.detached(priority: .userInitiated) {
                    try LocalBookImporter.prepareTXT(url: document.fileURL, title: title, directory: payload, id: id, preferredEncoding: preferredEncoding)
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
            var cloudAnchors: [ReadingPosition: CloudTextAnchor] = [:]
            if let cloud, let old = localBook(cloudID: cloud.book.id), old.format == .txt {
                let anchors = [positions[old.id]].compactMap { $0 } + bookmarks.filter { $0.bookID == old.id }.map(\.position)
                let replacement = prepared.book
                cloudAnchors = await Task.detached(priority: .utility) {
                    CloudTextAnchors.build(old: old, new: replacement, positions: anchors)
                }.value
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
            if cloud?.cancellation.isCancelled == true { throw CloudError.cancelled }
            let target = cloud.flatMap { context in updatedBooks.firstIndex { $0.cloudLinks?.contains(where: { $0.id == context.book.id }) == true } }
            if let cloud, let target {
                let existing = updatedBooks[target]
                guard !activeReaderIDs.contains(existing.id) else { throw CloudError.reading }
                guard cloud.allowsUpdate || existing.cloudLinks?.first(where: { $0.id == cloud.book.id })?.sha256 == cloud.book.sha256 else { throw CloudError.changed }
                if existing.sourceIdentity == prepared.identity {
                    var book = existing; book.title = cloud.book.title; book.author = cloud.book.author.isEmpty ? "未知作者" : cloud.book.author
                    book.cloudLinks = Self.linking(existing.cloudLinks, cloud.book)
                    updatedBooks[target] = book
                    advance(.commit); try importEnvironment.beforeCommit(root)
                    try writeSnapshot(Snapshot(books: updatedBooks, positions: positions, bookmarks: bookmarks, settings: settings, sources: sources))
                    books = updatedBooks
                    return .success(ImportSuccess(book: book, duplicate: true))
                }
            }
            if target == nil, let index = updatedBooks.firstIndex(where: { $0.format == prepared.book.format && $0.sourceIdentity == prepared.identity }) {
                if let cloud { updatedBooks[index].cloudLinks = Self.linking(updatedBooks[index].cloudLinks, cloud.book) }
                let existing = updatedBooks[index]
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
            var updatedPositions = positions
            var updatedBookmarks = bookmarks
            var previous: Book?
            if let cloud {
                book.title = cloud.book.title; book.author = cloud.book.author.isEmpty ? "未知作者" : cloud.book.author
                if let target {
                    let old = updatedBooks[target]; previous = old
                    book.id = old.id; book.importedAt = old.importedAt
                    book.cloudLinks = Self.linking(old.cloudLinks, cloud.book)
                    var used = Set<UUID>()
                    for index in book.chapters.indices {
                        if let match = old.chapters.first(where: { !used.contains($0.id) && Self.chapterKey($0) == Self.chapterKey(book.chapters[index]) }) {
                            book.chapters[index].id = match.id; used.insert(match.id)
                        }
                    }
                    if let position = positions[old.id] { updatedPositions[old.id] = remapCloudPosition(position, from: old, to: book, anchors: cloudAnchors) }
                    updatedBookmarks = bookmarks.map { bookmark in
                        guard bookmark.bookID == old.id else { return bookmark }
                        var value = bookmark; value.position = remapCloudPosition(value.position, from: old, to: book, anchors: cloudAnchors); return value
                    }
                    updatedBooks[target] = book
                } else { book.cloudLinks = Self.linking(nil, cloud.book); updatedBooks.insert(book, at: 0) }
            } else { updatedBooks.insert(book, at: 0) }
            try importEnvironment.beforeCommit(root)
            if cloud?.cancellation.isCancelled == true { throw CloudError.cancelled }
            try writeSnapshot(Snapshot(books: updatedBooks, positions: updatedPositions, bookmarks: updatedBookmarks, settings: settings, sources: sources))
            committed = true
            books = updatedBooks; positions = updatedPositions; bookmarks = updatedBookmarks
            if let previous, let path = previous.originalFile {
                let old = previous.format == .epub ? URL(fileURLWithPath: path).deletingLastPathComponent() : URL(fileURLWithPath: path)
                if old.standardizedFileURL.path.hasPrefix(root.appendingPathComponent("books").path + "/"), old != finalDirectory {
                    try? fm.removeItem(at: old)
                }
            }
            advance(.complete)
            return .success(ImportSuccess(book: book, duplicate: false))
        } catch {
            return .failure(ImportDiagnostics.failure(error, stage: stage, url: url, byteCount: byteCount))
        }
    }

    private static func linking(_ links: [CloudBookLink]?, _ book: CloudBook) -> [CloudBookLink] {
        (links ?? []).filter { $0.id != book.id } + [CloudBookLink(id: book.id, sha256: book.sha256, revision: book.revision)]
    }
    private static func chapterKey(_ chapter: Chapter) -> String { chapter.href ?? chapter.title }
    private func remapCloudPosition(_ position: ReadingPosition, from old: Book, to new: Book, anchors: [ReadingPosition: CloudTextAnchor]) -> ReadingPosition {
        guard !new.chapters.isEmpty else { return .beginning }
        var value = position
        let original = old.chapters.indices.contains(position.chapter) ? old.chapters[position.chapter] : nil
        let index = original.flatMap { chapter in new.chapters.firstIndex { $0.id == chapter.id } } ?? min(max(0, position.chapter), new.chapters.count - 1)
        value.chapter = index
        if new.format == .txt {
            value.locatorJSON = nil
            value.characterOffset = min(max(0, position.characterOffset), new.chapters[index].length)
            if let anchor = anchors[position], anchor.bookID == old.id, anchor.chapter == index {
                value.characterOffset = min(anchor.offset, new.chapters[index].length)
            }
            let prefix = new.chapters.prefix(index).reduce(0) { $0 + $1.length }
            value.progression = Double(prefix + value.characterOffset) / Double(max(1, new.characterCount))
        } else if original?.href != new.chapters[index].href { value.locatorJSON = nil }
        return value
    }
}
