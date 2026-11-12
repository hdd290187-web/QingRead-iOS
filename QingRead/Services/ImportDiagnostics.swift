import Foundation
import OSLog
import CryptoKit

enum ImportStage: String, Codable, CaseIterable {
    case picker = "选择文件"
    case permission = "访问授权"
    case download = "下载 iCloud 文件"
    case coordinate = "协调读取"
    case stage = "复制到本机"
    case validate = "检查文件"
    case decode = "识别文字编码"
    case parse = "解析正文"
    case epub = "读取 EPUB 目录"
    case commit = "保存到书架"
    case complete = "导入完成"
}

struct ImportFailure: Identifiable, Sendable {
    let id = UUID()
    let displayName: String
    let stage: ImportStage
    let reason: String
    let suggestion: String
    let errorDomain: String
    let errorCode: Int
    let fileToken: String
    let underlyingCodes: [String]

    var message: String {
        "\(displayName)\n失败阶段：\(stage.rawValue)\n原因：\(reason)\n错误码：\(errorDomain) / \(errorCode)\n\(underlyingCodes.isEmpty ? "" : "底层错误：" + underlyingCodes.joined(separator: " → ") + "\n")\(suggestion)\n诊断编号：\(fileToken)"
    }
}

struct ImportBatchResult: Sendable {
    var bookIDs: [UUID] = []
    var imported: [String] = []
    var duplicates: [String] = []
    var failures: [ImportFailure] = []
    var cancelled = false
    var succeeded: Bool { failures.isEmpty && (!imported.isEmpty || !duplicates.isEmpty) }
}

struct ImportProgress: Sendable {
    var current: Int
    var total: Int
    var fileName: String
    var stage: ImportStage
}

struct ImportFeedback: Identifiable {
    let id = UUID()
    let result: ImportBatchResult
    var title: String {
        if result.failures.isEmpty { return result.duplicates.isEmpty ? "导入完成" : "书籍已在书架" }
        return result.imported.isEmpty && result.duplicates.isEmpty ? "导入失败" : "部分导入完成"
    }
    var message: String {
        var lines: [String] = []
        if !result.imported.isEmpty { lines.append("已加入 \(result.imported.count) 本：\(result.imported.joined(separator: "、"))") }
        if !result.duplicates.isEmpty { lines.append("已在书架，阅读进度已保留：\(result.duplicates.joined(separator: "、"))") }
        if !result.failures.isEmpty { lines.append(result.failures.map(\.message).joined(separator: "\n\n")) }
        return lines.joined(separator: "\n\n")
    }
}

struct ImportPipelineError: LocalizedError {
    let stage: ImportStage
    let reason: String
    let suggestion: String
    let underlying: Error?
    var errorDescription: String? { reason }
    var nsError: NSError { underlying.map { $0 as NSError } ?? NSError(domain: "QingRead.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]) }
}

enum ImportDiagnostics {
    private static let logger = Logger(subsystem: "com.hdd290187.qingread", category: "document-import")
    static func event(_ name: String, stage: ImportStage, url: URL, byteCount: Int? = nil, accessGranted: Bool? = nil) {
        #if DEBUG
        let fileToken = String(SHA256Token.value(url.absoluteString).prefix(8))
        logger.debug("event=\(name, privacy: .public) stage=\(stage.rawValue, privacy: .public) extension=\(url.pathExtension.lowercased(), privacy: .public) bytes=\(byteCount ?? -1) access=\(String(describing: accessGranted), privacy: .public) file=\(fileToken, privacy: .public)")
        #endif
    }
    static func failure(_ error: Error, stage: ImportStage, url: URL, byteCount: Int? = nil) -> ImportFailure {
        let pipeline = error as? ImportPipelineError
        let nsError = pipeline?.nsError ?? error as NSError
        let resolvedStage = pipeline?.stage ?? stage
        let reason = pipeline?.reason ?? userReason(nsError)
        let suggestion = pipeline?.suggestion ?? Self.suggestion(for: nsError, stage: resolvedStage, ext: url.pathExtension.lowercased())
        let token = String(SHA256Token.value(url.absoluteString).prefix(10))
        #if DEBUG
        logger.error("result=failure stage=\(resolvedStage.rawValue, privacy: .public) extension=\(url.pathExtension.lowercased(), privacy: .public) bytes=\(byteCount ?? -1) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) file=\(token, privacy: .public)")
        #endif
        var codes: [String] = []
        var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        while let current = underlying, codes.count < 5 {
            codes.append("\(current.domain) / \(current.code)")
            underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return ImportFailure(displayName: safeDisplayName(url), stage: resolvedStage, reason: redacted(reason), suggestion: suggestion, errorDomain: nsError.domain, errorCode: nsError.code, fileToken: token, underlyingCodes: codes)
    }
    static func safeDisplayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? "所选文件" : name
    }
    static func userReason(_ error: NSError) -> String {
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError): "文件不存在或文件提供器已移除它。"
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSCocoaErrorDomain, NSFileWriteNoPermissionError): "iOS 未授予文件读取权限。"
        case (NSCocoaErrorDomain, NSFileReadUnknownError): "无法读取此文件。"
        case (NSCocoaErrorDomain, NSFileReadCorruptFileError): "文件内容损坏或格式无效。"
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError): "设备可用空间不足，无法保存导入文件。"
        case (NSURLErrorDomain, NSURLErrorFileDoesNotExist): "iCloud 或文件提供器中的文件尚未下载或已不可用。"
        default: error.localizedDescription
        }
    }
    private static func redacted(_ message: String) -> String {
        // NSError.localizedDescription occasionally includes an absolute provider
        // path. Keep the error itself and its codes, strip the private location.
        message.replacingOccurrences(of: #"(?:file://)?/(?:private|var|Users|Volumes|tmp|System|Library)/[^\s\"'，。；）)]+"#, with: "[文件路径]", options: .regularExpression)
    }
    static func suggestion(for error: NSError, stage: ImportStage, ext: String) -> String {
        if (error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code)) { return "请在系统‘文件’中重新选择文件，并允许阅简访问；也可先复制到‘在我的 iPhone 上’后再试。" }
        if stage == .download || error.code == NSURLErrorFileDoesNotExist { return "请先在‘文件’中打开该 iCloud 文件并等待下载完成，再返回阅简重新导入。" }
        if stage == .decode { return "请确认文件是 UTF-8、UTF-16 或 GB18030/GBK 编码的纯文本；重新另存为 UTF-8 后再试。" }
        if stage == .epub || ext == "epub" { return "请确认这是未加密、未损坏的 EPUB 文件；本地副本无法解析时请从原来源重新下载。" }
        if stage == .commit || stage == .stage { return "请检查 iPhone 可用空间，然后重新选择原始文件。原文件和已有书架未被删除。" }
        return "请检查文件是否完整且未被其他 App 移动；可以先复制到‘在我的 iPhone 上’，再重试。原文件已保留。"
    }
}

private enum SHA256Token {
    static func value(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
