import Foundation
import ReadiumShared
import ReadiumStreamer

@MainActor
final class EPUBService {
    private let http = DefaultHTTPClient()
    private lazy var retriever = AssetRetriever(httpClient: http)
    private lazy var opener = PublicationOpener(parser: DefaultPublicationParser(httpClient: http, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory()))
    func open(path: String) async throws -> Publication {
        guard let url = FileURL(url: URL(fileURLWithPath: path)) else { throw ReaderError.message("EPUB 文件路径无效") }
        let asset = try await retriever.retrieve(url: url).get()
        let publication = try await opener.open(asset: asset, allowUserInteraction: false).get()
        guard !publication.isRestricted else { throw ReaderError.message("此 EPUB 受 DRM 保护，暂不支持解锁。") }
        guard !publication.readingOrder.isEmpty else { throw ReaderError.message("EPUB 没有可阅读的章节。") }
        return publication
    }
    static func flatten(_ links: [ReadiumShared.Link]) -> [ReadiumShared.Link] {
        links.flatMap { [$0] + flatten($0.children) }
    }
}
