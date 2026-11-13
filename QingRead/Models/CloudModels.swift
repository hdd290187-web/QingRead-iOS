import Foundation

enum CloudFormat: String, Codable, CaseIterable, Identifiable {
    case txt, epub
    var id: String { rawValue }
}

struct CloudBook: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var format: CloudFormat
    var fileSize: Int64
    var originalName: String
    var sha256: String
    var updatedAt: String
    var revision: Int
    var coverUrl: String?
    var downloadUrl: String

    var validFile: Bool {
        fileSize > 0 && fileSize <= (format == .txt ? Int64(TXTParser.maxFileSize) : Int64(DocumentStager.maxEPUBSize)) &&
        sha256.count == 64 && sha256.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

struct CloudBookPage: Codable, Sendable {
    var items: [CloudBook]
    var total: Int
    var page: Int
    var pageSize: Int
}

struct CloudChanges: Codable, Sendable {
    struct Item: Codable, Sendable { var id: UUID; var updatedAt: String; var deletedAt: String?; var revision: Int }
    struct Cursor: Codable, Sendable { var since: String; var afterId: UUID }
    var items: [Item]
    var hasMore: Bool
    var next: Cursor?
}

/// This contains public book metadata only. Credentials never enter the library snapshot.
struct CloudBookLink: Codable, Hashable {
    var id: UUID
    var sha256: String
    var revision: Int
    var downloadedAt: Date = Date()
}

enum CloudSort: String, CaseIterable, Identifiable {
    case updated = "updated_desc", imported = "imported_desc", title = "title_asc", size = "size_desc"
    var id: String { rawValue }
    var title: String {
        switch self { case .updated: "最近更新"; case .imported: "最近上传"; case .title: "书名"; case .size: "文件大小" }
    }
}

enum CloudError: LocalizedError, Equatable {
    case disconnected, status(Int), invalidResponse, integrity, cancelled, keychain, network, changed, reading
    var errorDescription: String? {
        switch self {
        case .disconnected: return "请先连接云书库。"
        case .status(401): return "设备令牌已失效或被撤销，请重新连接。"
        case .status(403): return "此设备没有访问权限，请检查只读设备令牌。"
        case .status(404): return "书籍不存在，可能已被移至回收站。请刷新书库。"
        case .status(410): return "云端原文件已被清理，已下载的本地书仍可阅读。"
        case .status(416): return "下载进度已失效，请重试以重新下载。"
        case .status(429): return "请求较多，请稍后重试。"
        case .status: return "云书库暂时无法响应，请稍后重试。"
        case .invalidResponse: return "云书库响应不完整，请刷新后重试。"
        case .integrity: return "文件校验未通过，已清理损坏数据，请重试。"
        case .cancelled: return "下载已取消，可稍后继续。"
        case .keychain: return "无法安全保存设备令牌，请解锁设备后重试。"
        case .network: return "连接超时或网络不可用，请检查网络后重试。本地书仍可离线阅读。"
        case .changed: return "云端文件已更新，请刷新书库后重试。"
        case .reading: return "请先关闭这本书的阅读页面，再确认更新。"
        }
    }
    static func safe(_ error: Error) -> Error {
        if error is CloudError { return error }
        if error is CancellationError || (error as NSError).code == NSURLErrorCancelled { return CloudError.cancelled }
        return CloudError.network
    }
}

final class CloudCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

struct CloudImportContext {
    let book: CloudBook
    let allowsUpdate: Bool
    let cancellation: CloudCancellation
}
