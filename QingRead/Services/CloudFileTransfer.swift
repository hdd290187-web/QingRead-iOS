import Foundation

/// Response bytes go directly to a private file on a serial queue, never a whole-book Data buffer.
/// A partial file contains bytes only; URLSession resume blobs could persist Authorization headers.
final class CloudFileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.hdd290187.qingread.cloud-transfer", qos: .utility)
    private let book: CloudBook
    private let directory: URL
    private let configuration: URLSessionConfiguration
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var handle: FileHandle?
    private var failure: Error?
    private var cancelled = false
    private var received: Int64 = 0
    private var responseAccepted = false
    private var lastProgressTime = 0.0
    private var progress: (@Sendable (Int64, Int64) -> Void)?
    private var partial: URL { directory.appendingPathComponent("\(book.id.uuidString)-\(book.sha256).part") }
    private var complete: URL { directory.appendingPathComponent("\(book.id.uuidString)-\(book.sha256).\(book.format.rawValue)") }

    init(book: CloudBook, directory: URL, configuration: URLSessionConfiguration) {
        self.book = book; self.directory = directory; self.configuration = configuration
    }

    func download(request: URLRequest, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation; self.progress = progress
                    do {
                        guard !self.cancelled else { throw CloudError.cancelled }
                        guard self.book.validFile else { throw CloudError.invalidResponse }
                        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
                        var folder = self.directory; try folder.setResourceValues(resource)
                        let size = (try? self.partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                        if size > self.book.fileSize { try? FileManager.default.removeItem(at: self.partial) }
                        self.received = Int64((try? self.partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        if self.received == self.book.fileSize { try self.finishVerifiedFile(); return }
                        var request = request
                        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                        if self.received > 0 {
                            request.setValue("bytes=\(self.received)-", forHTTPHeaderField: "Range")
                            request.setValue("\"\(self.book.sha256)\"", forHTTPHeaderField: "If-Range")
                        }
                        let delegateQueue = OperationQueue(); delegateQueue.maxConcurrentOperationCount = 1; delegateQueue.underlyingQueue = self.queue
                        self.session = URLSession(configuration: self.configuration, delegate: self, delegateQueue: delegateQueue)
                        self.task = self.session?.dataTask(with: request)
                        self.progress?(self.received, self.book.fileSize)
                        self.task?.resume()
                    } catch { self.finish(.failure(CloudError.safe(error))) }
                }
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            self.task?.cancel()
            if self.task == nil { self.finish(.failure(CloudError.cancelled)) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a device credential to a redirect, including a different origin.
        failure = CloudError.invalidResponse
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard !cancelled else { throw CloudError.cancelled }
            guard let http = response as? HTTPURLResponse, response.url?.host == CloudAPIClient.origin.host,
                  response.url?.scheme == "https" else { throw CloudError.invalidResponse }
            guard http.statusCode == 200 || http.statusCode == 206 else {
                if [404, 410, 416].contains(http.statusCode) { try? FileManager.default.removeItem(at: partial) }
                throw CloudError.status(http.statusCode)
            }
            guard http.value(forHTTPHeaderField: "ETag") == "\"\(book.sha256)\"" else {
                try? FileManager.default.removeItem(at: partial)
                throw CloudError.changed
            }
            if http.statusCode == 206 {
                guard Self.validRange(http.value(forHTTPHeaderField: "Content-Range"), start: received, total: book.fileSize),
                      response.expectedContentLength == book.fileSize - received else {
                    try? FileManager.default.removeItem(at: partial); throw CloudError.invalidResponse
                }
            } else {
                // If-Range mismatch and servers ignoring Range both require starting from byte zero.
                received = 0
                guard response.expectedContentLength == book.fileSize else { throw CloudError.changed }
                try? FileManager.default.removeItem(at: partial)
            }
            if !FileManager.default.fileExists(atPath: partial.path) {
                guard FileManager.default.createFile(atPath: partial.path, contents: nil,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw CloudError.invalidResponse }
            }
            handle = try FileHandle(forWritingTo: partial)
            try handle?.seek(toOffset: UInt64(received))
            responseAccepted = true
            completionHandler(.allow)
        } catch {
            failure = CloudError.safe(error)
            completionHandler(.cancel)
        }
    }

    static func validRange(_ value: String?, start: Int64, total: Int64) -> Bool {
        guard let value, value.hasPrefix("bytes ") else { return false }
        let halves = value.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 2, Int64(halves[1]) == total else { return false }
        let ends = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        return ends.count == 2 && Int64(ends[0]) == start && Int64(ends[1]) == total - 1 && start < total
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, responseAccepted, !cancelled else { return }
        do {
            guard received + Int64(data.count) <= book.fileSize else {
                try? FileManager.default.removeItem(at: partial); throw CloudError.integrity
            }
            try handle?.write(contentsOf: data)
            received += Int64(data.count)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastProgressTime >= 0.1 || received == book.fileSize {
                lastProgressTime = now; progress?(received, book.fileSize)
            }
        } catch { failure = CloudError.safe(error); dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        do {
            try handle?.synchronize(); try handle?.close(); handle = nil
            if cancelled { throw CloudError.cancelled }
            if let failure { throw failure }
            if let error { throw CloudError.safe(error) }
            guard responseAccepted, received == book.fileSize else { throw CloudError.network }
            try finishVerifiedFile()
        } catch { finish(.failure(CloudError.safe(error))) }
    }

    private func finishVerifiedFile() throws {
        guard try DocumentStager.contentIdentity(at: partial) == book.sha256 else {
            try? FileManager.default.removeItem(at: partial); throw CloudError.integrity
        }
        try? FileManager.default.removeItem(at: complete)
        try FileManager.default.moveItem(at: partial, to: complete)
        progress?(book.fileSize, book.fileSize)
        finish(.success(complete))
    }
    private func finish(_ result: Result<URL, Error>) {
        try? handle?.close(); handle = nil
        let continuation = continuation; self.continuation = nil
        session?.finishTasksAndInvalidate(); session = nil; task = nil
        progress = nil
        continuation?.resume(with: result)
    }
}
