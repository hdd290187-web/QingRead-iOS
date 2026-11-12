import Foundation
import CryptoKit

struct StagedDocument: Sendable {
    let fileURL: URL
    let identity: String
    let byteCount: Int
    let securityScopeGranted: Bool
}
struct DocumentAccess: Sendable {
    var begin: @Sendable (URL) -> Bool
    var end: @Sendable (URL) -> Void
    static var live: DocumentAccess {
        DocumentAccess(begin: { $0.startAccessingSecurityScopedResource() }, end: { $0.stopAccessingSecurityScopedResource() })
    }
}

enum DocumentStager {
    static let maxEPUBSize = 256 * 1024 * 1024
    static func copyIntoPrivateDirectory(source: URL, directory: URL, access: DocumentAccess = .live, progress: @Sendable (ImportStage) -> Void = { _ in }) throws -> StagedDocument {
        guard source.isFileURL else {
            throw ImportPipelineError(stage: .validate, reason: "所选地址不是本地文件。", suggestion: "请在系统‘文件’中重新选择一个文件。", underlying: nil)
        }
        let scopeGranted = access.begin(source)
        progress(.permission)
        ImportDiagnostics.event("security-scope", stage: .permission, url: source, accessGranted: scopeGranted)
        defer { if scopeGranted { access.end(source) } }
        do { try waitForUbiquitousDownloadIfNeeded(source, progress: progress) }
        catch { if let pipeline = error as? ImportPipelineError { throw pipeline }; throw wrap(error, stage: .permission, ext: source.pathExtension.lowercased()) }
        let ext = source.pathExtension.lowercased()
        guard ext == "txt" || ext == "epub" else {
            throw ImportPipelineError(stage: .validate, reason: "不支持 .\(ext.isEmpty ? "未知" : ext) 格式。", suggestion: "请选择 TXT 或 EPUB 文件。", underlying: nil)
        }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw wrap(error, stage: .stage, ext: ext) }
        let destination = directory.appendingPathComponent("source.\(ext)")
        var coordinationError: NSError?
        var copyError: Error?
        var coordinated = false
        progress(.coordinate)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            coordinated = true
            do {
                let values = try coordinatedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw ImportPipelineError(stage: .validate, reason: "所选项目不是普通文件。", suggestion: "请选择 TXT 或 EPUB 文件。", underlying: nil) }
                let limit = ext == "txt" ? TXTParser.maxFileSize : maxEPUBSize
                if let size = values.fileSize, size > limit { throw ImportPipelineError(stage: .validate, reason: "文件超过 \(ext == "txt" ? "64 MB" : "256 MB") 导入上限。", suggestion: "请拆分或缩小文件后再试。", underlying: nil) }
                progress(.stage)
                try FileManager.default.copyItem(at: coordinatedURL, to: destination)
            }
            catch { copyError = error }
        }
        if let error = coordinationError ?? copyError {
            try? FileManager.default.removeItem(at: destination)
            if let pipeline = error as? ImportPipelineError { throw pipeline }
            throw wrap(error, stage: coordinationError != nil ? .coordinate : .stage, ext: ext)
        }
        guard coordinated else { throw ImportPipelineError(stage: .coordinate, reason: "文件提供器没有交出可读取的文件。", suggestion: "请关闭文件选择器后重新选择；若文件在 iCloud 中，请先在‘文件’中下载到本机。", underlying: nil) }
        do {
            let values = try destination.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw ImportPipelineError(stage: .validate, reason: "所选项目不是普通文件。", suggestion: "请直接选择 TXT 或 EPUB 文件，不要选择文件夹或快捷方式。", underlying: nil) }
            let size = values.fileSize ?? 0
            let limit = ext == "txt" ? TXTParser.maxFileSize : maxEPUBSize
            guard size > 0 else { throw ImportPipelineError(stage: .validate, reason: "所选文件为空。", suggestion: "请确认原文件包含正文后重新导入。", underlying: nil) }
            guard size <= limit else { throw ImportPipelineError(stage: .validate, reason: "文件大小为 \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))，超过 \(ext == "txt" ? "64 MB" : "256 MB") 导入上限。", suggestion: "请拆分 TXT，或缩小/重新导出 EPUB 后再试。", underlying: nil) }
            let identity = try contentIdentity(at: destination)
            ImportDiagnostics.event("staged", stage: .stage, url: source, byteCount: size, accessGranted: scopeGranted)
            return StagedDocument(fileURL: destination, identity: identity, byteCount: size, securityScopeGranted: scopeGranted)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if let pipeline = error as? ImportPipelineError { throw pipeline }
            throw wrap(error, stage: .validate, ext: ext)
        }
    }

    static func contentIdentity(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hasher = CryptoKit.SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func waitForUbiquitousDownloadIfNeeded(_ url: URL, progress: @Sendable (ImportStage) -> Void) throws {
        var downloadURL = url
        let values: URLResourceValues
        do { values = try downloadURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) }
        catch { throw wrap(error, stage: .permission, ext: url.pathExtension.lowercased()) }
        guard values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current else { return }
        progress(.download)
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            for _ in 0..<60 {
                Thread.sleep(forTimeInterval: 1)
                downloadURL.removeCachedResourceValue(forKey: .ubiquitousItemDownloadingStatusKey)
                let current = try downloadURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if current.ubiquitousItemDownloadingStatus == .current { return }
            }
            throw NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: [NSLocalizedDescriptionKey: "iCloud 文件在等待期间未完成下载。"])
        } catch {
            throw wrap(error, stage: .download, ext: url.pathExtension.lowercased())
        }
    }

    private static func wrap(_ error: Error, stage: ImportStage, ext: String) -> ImportPipelineError {
        let nsError = error as NSError
        return ImportPipelineError(stage: stage, reason: ImportDiagnostics.userReason(nsError), suggestion: ImportDiagnostics.suggestion(for: nsError, stage: stage, ext: ext), underlying: error)
    }
}
