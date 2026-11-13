import Foundation
import UIKit
import CryptoKit
import ReadiumShared

final class BookCover: NSObject {
    enum Kind: String { case epub, generated }
    let image: UIImage
    let kind: Kind
    init(image: UIImage, kind: Kind) { self.image = image; self.kind = kind }
}

/// Small, local thumbnails only. This cache never writes into the library or changes a Book.
@MainActor
final class BookCoverCache {
    static let shared = BookCoverCache()
    private let memory = NSCache<NSString, BookCover>()
    private var inFlight: [String: Task<BookCover, Never>] = [:]
    private let directory: URL
    private let service = EPUBService()
    static let thumbnailSize = CGSize(width: 400, height: 588)

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("YYBookCovers-v1", isDirectory: true)
        memory.totalCostLimit = 24 * 1024 * 1024
        memory.countLimit = 48
        let folder = self.directory
        Task.detached(priority: .utility) { Self.trimDisk(folder) }
    }

    func cover(for book: Book) async -> BookCover {
        let key = Self.key(for: book)
        if let value = memory.object(forKey: key as NSString) { return value }
        if let task = inFlight[key] { return await task.value }
        let folder = directory
        let task = Task<BookCover, Never> {
            if let disk = await Task.detached(priority: .utility, operation: { Self.readDisk(folder, key: key) }).value { return disk }
            let result: BookCover
            if book.format == .epub, let path = book.originalFile,
               let publication = try? await service.open(path: path),
               let image = try? await publication.coverFitting(maxSize: Self.thumbnailSize).get() {
                result = BookCover(image: image, kind: .epub)
            } else {
                let image = await Task.detached(priority: .utility) { NatureCover.render(seed: NatureCover.seed(for: book)) }.value
                result = BookCover(image: image, kind: .generated)
            }
            await Task.detached(priority: .utility) {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if let data = result.image.jpegData(compressionQuality: 0.88) {
                    try? data.write(to: folder.appendingPathComponent("\(key).\(result.kind.rawValue).jpg"), options: .atomic)
                }
                Self.trimDisk(folder)
            }.value
            return result
        }
        inFlight[key] = task
        let result = await task.value
        memory.setObject(result, forKey: key as NSString, cost: (result.image.cgImage?.bytesPerRow ?? 1600) * (result.image.cgImage?.height ?? 588))
        inFlight[key] = nil
        return result
    }

    nonisolated static func key(for book: Book) -> String {
        let base = "v1|\(book.id.uuidString)|\(book.title)|\(book.format.rawValue)"
        let versions = (book.cloudLinks ?? []).map { "\($0.id):\($0.sha256):\($0.revision)" }.sorted().joined(separator: "|")
        let key = versions.isEmpty ? base : base + "|cloud:" + versions
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private nonisolated static func readDisk(_ directory: URL, key: String) -> BookCover? {
        for kind in [BookCover.Kind.epub, .generated] {
            let url = directory.appendingPathComponent("\(key).\(kind.rawValue).jpg")
            if let image = UIImage(contentsOfFile: url.path), image.size.width <= 401, image.size.height <= 589 {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
                return BookCover(image: image, kind: kind)
            }
        }
        return nil
    }
    private nonisolated static func trimDisk(_ directory: URL) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else { return }
        let entries = urls.compactMap { url -> (URL, Date, Int)? in
            guard url.pathExtension == "jpg", let value = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, value.contentModificationDate ?? .distantPast, value.fileSize ?? 0)
        }.sorted { $0.1 < $1.1 }
        var bytes = entries.reduce(0) { $0 + $1.2 }
        for entry in entries where bytes > 64 * 1024 * 1024 { try? fm.removeItem(at: entry.0); bytes -= entry.2 }
    }
}

/// Deterministic original artwork: quiet landscapes and blossom studies, no remote service.
enum NatureCover {
    nonisolated static func seed(for book: Book) -> [UInt8] { Array(SHA256.hash(data: Data("YuyingCover/v1/987|\(book.title)".utf8))) }
    nonisolated static func render(seed: [UInt8]) -> UIImage {
        let palettes: [[UInt32]] = [
            [0xB8BAC0, 0xE8DAC9, 0xC1BCB5, 0x9C9F9B, 0x686F69],
            [0xE5D5D0, 0xF1E4D9, 0xDBC4C0, 0xBBA3A0, 0x927A76],
            [0x182C36, 0x314A50, 0x29444B, 0x1D363F, 0x132A32],
            [0xD4BEC0, 0xEED7BD, 0xCCBBC1, 0xA8A2B0, 0x7F8194],
            [0xAFBDB2, 0xE1E1CD, 0xABB7A3, 0x849B8C, 0x55786D],
            [0xA8B9C3, 0xE3DFD4, 0xB2BDC1, 0x8A9FA8, 0x5D7C89]
        ]
        let style = Int(seed[0]) % palettes.count, palette = palettes[style]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 400, height: 588), format: format).image { renderer in
            let ctx = renderer.cgContext, width: CGFloat = 400, height: CGFloat = 588
            let colors = [UIColor(hex: palette[0]).cgColor, UIColor(hex: palette[1]).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
            }
            let sun = CGPoint(x: width * (0.65 + Double(seed[1]) / 255 * 0.15), y: height * (0.2 + Double(seed[2]) / 255 * 0.13))
            if style != 1 {
                ctx.setFillColor(UIColor(hex: style == 2 ? 0xF3E7C7 : 0xF8E5C4).withAlphaComponent(style == 2 ? 0.9 : 0.68).cgColor)
                let radius: CGFloat = style == 2 ? 14 : 20
                ctx.fillEllipse(in: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))
            }
            if style == 2 {
                ctx.setFillColor(UIColor(white: 0.9, alpha: 0.32).cgColor)
                for i in 0..<20 {
                    let x = CGFloat(seed[(i + 3) % seed.count]) / 255 * width
                    let y = CGFloat(seed[(i + 7) % seed.count]) / 255 * height * 0.43
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: i % 4 == 0 ? 2 : 1, height: i % 4 == 0 ? 2 : 1))
                }
            }
            for layer in 0..<4 {
                let path = CGMutablePath()
                let base = 0.47 + Double(layer) * 0.14
                let phase = Double(seed[layer + 4]) / 40
                path.move(to: CGPoint(x: 0, y: height))
                for step in 0...60 {
                    let x = Double(step) / 60
                    let hill = sin(x * 8 + phase) * 0.045 + sin(x * 19 + phase * 0.6) * 0.023
                    let peak = max(0, 1 - abs(x - (0.35 + Double(seed[layer + 9]) / 900)) * 4) * (layer == 0 ? 0.18 : 0.07)
                    path.addLine(to: CGPoint(x: x * width, y: (base + hill - peak) * height))
                }
                path.addLine(to: CGPoint(x: width, y: height)); path.closeSubpath()
                ctx.addPath(path); ctx.setFillColor(UIColor(hex: palette[min(4, layer + 2)]).withAlphaComponent(layer == 0 ? 0.6 : 0.87).cgColor); ctx.fillPath()
            }
            if style == 1 { blossoms(in: ctx, seed: seed) }
            // A restrained paper/spine highlight, without baked-in typography.
            ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.13).cgColor); ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 5, y: 0)); ctx.addLine(to: CGPoint(x: 5, y: height)); ctx.strokePath()
        }
    }
    private nonisolated static func blossoms(in ctx: CGContext, seed: [UInt8]) {
        ctx.setStrokeColor(UIColor(hex: 0x8F7470).withAlphaComponent(0.7).cgColor); ctx.setLineWidth(2.2)
        ctx.move(to: CGPoint(x: 330, y: 588)); ctx.addCurve(to: CGPoint(x: 170, y: 110), control1: CGPoint(x: 220, y: 420), control2: CGPoint(x: 320, y: 250)); ctx.strokePath()
        for i in 0..<14 {
            let y = 155 + CGFloat(i) * 27, x = 180 + CGFloat(seed[i + 1]) / 255 * 145
            ctx.setLineWidth(0.9); ctx.move(to: CGPoint(x: 255, y: y + 50)); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.strokePath()
            for petal in 0..<5 {
                let angle = CGFloat(petal) * .pi * 2 / 5
                ctx.setFillColor(UIColor(hex: i % 2 == 0 ? 0xF1D6CE : 0xE4BCB4).withAlphaComponent(0.92).cgColor)
                ctx.fillEllipse(in: CGRect(x: x + cos(angle) * 5 - 5, y: y + sin(angle) * 5 - 7, width: 10, height: 14))
            }
            ctx.setFillColor(UIColor(hex: 0xB9947B).cgColor); ctx.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
        }
    }
}
