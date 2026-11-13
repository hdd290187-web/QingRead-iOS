import Foundation
import SwiftUI
import UIKit

enum CloudDownloadState: Equatable {
    case downloading(Int64, Int64), importing, cancelled, failed(String)
    var busy: Bool {
        switch self { case .downloading, .importing: true; default: false }
    }
}

@MainActor
final class CloudLibraryStore: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var loading = false
    @Published private(set) var books: [CloudBook] = []
    @Published private(set) var hasMore = false
    @Published private(set) var downloads: [UUID: CloudDownloadState] = [:]
    @Published var message: String?
    @Published var bookToOpen: Book?
    @Published var query = ""
    @Published var format = ""
    @Published var sort = CloudSort.updated
    let client: CloudAPIClient
    private var page = 0
    private var generation = UUID()
    private var authGeneration = UUID()
    private var jobs: [UUID: (task: Task<Void, Never>, cancellation: CloudCancellation)] = [:]
    private let coverCache = NSCache<NSString, NSData>()
    private let downloadDirectory: URL

    init(client: CloudAPIClient? = nil, downloadDirectory: URL? = nil) {
        var selectedClient = client
        #if DEBUG
        if selectedClient == nil, ProcessInfo.processInfo.arguments.contains("--uitest-cloud") {
            selectedClient = CloudUITestTransport.client()
        }
        #endif
        self.client = selectedClient ?? CloudAPIClient()
        self.downloadDirectory = downloadDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("YuyingCloudDownloads", isDirectory: true)
        coverCache.totalCostLimit = 12 * 1024 * 1024
        do { connected = try self.client.tokens.read() != nil } catch { message = CloudError.keychain.localizedDescription }
    }

    func connect(_ input: String) async -> Bool {
        guard !connecting else { return false }
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CloudAPIClient.isValidToken(token) else { message = "请粘贴后台创建的完整只读设备令牌。"; return false }
        connecting = true; message = nil
        let attempt = UUID(); authGeneration = attempt
        defer { connecting = false }
        do {
            let result = try await client.books(token: token)
            guard authGeneration == attempt, !Task.isCancelled else { return false }
            for job in jobs.values { job.cancellation.cancel(); job.task.cancel() }
            try client.tokens.save(token)
            generation = UUID(); connected = true; loading = false
            books = result.items; page = 1; hasMore = result.total > result.items.count
            query = ""; format = ""; sort = .updated; coverCache.removeAllObjects()
            return true
        } catch { message = CloudError.safe(error).localizedDescription; return false }
    }

    func disconnect() {
        do { try client.tokens.remove() }
        catch { message = CloudError.keychain.localizedDescription; return }
        authGeneration = UUID(); generation = UUID()
        for job in jobs.values { job.cancellation.cancel(); job.task.cancel() }
        connected = false; loading = false; books = []; hasMore = false; message = nil
        coverCache.removeAllObjects()
    }

    func refresh() async {
        guard connected else { return }
        let request = UUID(); generation = request; loading = true; message = nil
        do {
            let result = try await client.books(query: query, format: format, sort: sort)
            guard generation == request, !Task.isCancelled else { if generation == request { loading = false }; return }
            books = result.items; page = 1; hasMore = result.total > books.count; loading = false
        } catch {
            guard generation == request else { return }
            loading = false
            if !Task.isCancelled { receive(error) }
        }
    }

    func nextPage() async {
        guard connected, !loading, hasMore else { return }
        let request = generation; loading = true
        do {
            let result = try await client.books(query: query, page: page + 1, format: format, sort: sort)
            guard generation == request, !Task.isCancelled else { if generation == request { loading = false }; return }
            let seen = Set(books.map(\.id))
            books += result.items.filter { !seen.contains($0.id) }
            page = result.page; hasMore = page * result.pageSize < result.total; loading = false
        } catch {
            guard generation == request else { return }
            loading = false; receive(error)
        }
    }

    func cover(_ book: CloudBook) async -> UIImage? {
        guard connected else { return nil }
        let authorization = authGeneration
        let key = "\(book.id.uuidString)-\(book.revision)" as NSString
        if let data = coverCache.object(forKey: key) { return UIImage(data: data as Data) }
        do {
            guard let data = try await client.cover(book), let image = UIImage(data: data) else { return nil }
            guard authorization == authGeneration, connected else { return nil }
            coverCache.setObject(data as NSData, forKey: key, cost: data.count)
            return image
        } catch {
            if authorization == authGeneration, (error as? CloudError) == .status(401) { receive(error) }
            return nil
        }
    }

    func needsUpdate(_ book: CloudBook, library: LibraryStore) -> Bool {
        guard let link = library.localBook(cloudID: book.id)?.cloudLinks?.first(where: { $0.id == book.id }) else { return false }
        return link.sha256 != book.sha256 || link.revision != book.revision
    }

    func open(_ book: CloudBook, library: LibraryStore) {
        if let local = library.localBook(cloudID: book.id) { bookToOpen = local }
        else { download(book, library: library, openAfter: true) }
    }

    func download(_ book: CloudBook, library: LibraryStore, allowsUpdate: Bool = false, openAfter: Bool = false) {
        guard jobs[book.id] == nil else { return }
        if let local = library.localBook(cloudID: book.id), !allowsUpdate {
            if openAfter { bookToOpen = local }
            return
        }
        guard connected else { message = CloudError.disconnected.localizedDescription; return }
        let cancellation = CloudCancellation()
        let authorization = authGeneration
        downloads[book.id] = .downloading(0, max(1, book.fileSize))
        let task = Task {
            let background = UIApplication.shared.beginBackgroundTask(withName: "云书籍下载") {
                Task { @MainActor [weak self] in self?.cancel(book.id) }
            }
            defer {
                jobs[book.id] = nil
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            }
            do {
                let latest = try await client.book(book.id)
                guard !cancellation.isCancelled, authorization == authGeneration else { throw CloudError.cancelled }
                if let index = books.firstIndex(where: { $0.id == latest.id }) { books[index] = latest }
                guard latest.sha256 == book.sha256, latest.revision == book.revision else { throw CloudError.changed }
                let transfer = CloudFileTransfer(book: latest, directory: downloadDirectory, configuration: client.configuration)
                let file = try await transfer.download(request: client.request(path: "/api/v1/books/\(book.id.uuidString)/download")) { [weak self] done, total in
                    Task { @MainActor in
                        guard let self, self.jobs[book.id]?.cancellation.isCancelled == false else { return }
                        self.downloads[book.id] = .downloading(done, total)
                    }
                }
                defer { try? FileManager.default.removeItem(at: file) }
                guard !cancellation.isCancelled else { throw CloudError.cancelled }
                downloads[book.id] = .importing
                let local = try await library.importCloudFile(from: file, context: CloudImportContext(book: latest, allowsUpdate: allowsUpdate, cancellation: cancellation))
                guard !cancellation.isCancelled else { throw CloudError.cancelled }
                downloads[book.id] = nil
                if openAfter && library.activeReaderIDs.isEmpty { bookToOpen = local }
            } catch {
                if cancellation.isCancelled || authorization != authGeneration || (error as? CloudError) == .cancelled { downloads[book.id] = .cancelled }
                else {
                    receive(error)
                    downloads[book.id] = .failed(error is ReaderError ? error.localizedDescription : CloudError.safe(error).localizedDescription)
                }
            }
        }
        jobs[book.id] = (task, cancellation)
    }

    func cancel(_ id: UUID) {
        jobs[id]?.cancellation.cancel(); jobs[id]?.task.cancel()
        downloads[id] = .cancelled
    }

    private func receive(_ error: Error) {
        let safe = CloudError.safe(error)
        message = error is ReaderError ? error.localizedDescription : safe.localizedDescription
        if (safe as? CloudError) == .status(401) {
            try? client.tokens.remove()
            connected = false; generation = UUID(); loading = false
            for job in jobs.values { job.cancellation.cancel(); job.task.cancel() }
        }
    }
}
