import Foundation

struct CloudTextAnchor: Sendable {
    let bookID: UUID
    let chapter: Int
    let offset: Int
}

enum CloudTextAnchors {
    /// Called on a detached utility task; neither whole-chapter reads nor searches run on the UI thread.
    static func build(old: Book, new: Book, positions: [ReadingPosition]) -> [ReadingPosition: CloudTextAnchor] {
        guard old.format == .txt, new.format == .txt else { return [:] }
        var result: [ReadingPosition: CloudTextAnchor] = [:]
        var oldTexts: [Int: NSString] = [:]
        var newTexts: [Int: NSString] = [:]
        func text(_ book: Book, _ chapter: Chapter) -> NSString? {
            guard let file = chapter.file, let folder = book.originalFile else { return nil }
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : URL(fileURLWithPath: folder).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return String(decoding: data, as: UTF8.self) as NSString
        }
        for position in Set(positions) {
            guard old.chapters.indices.contains(position.chapter) else { continue }
            let original = old.chapters[position.chapter]
            let occurrence = old.chapters.prefix(position.chapter).filter { $0.title == original.title }.count
            let matches = new.chapters.indices.filter { new.chapters[$0].title == original.title }
            let index = occurrence < matches.count ? matches[occurrence] : min(position.chapter, max(0, new.chapters.count - 1))
            guard new.chapters.indices.contains(index) else { continue }
            if oldTexts[position.chapter] == nil { oldTexts[position.chapter] = text(old, original) }
            if newTexts[index] == nil { newTexts[index] = text(new, new.chapters[index]) }
            guard let previous = oldTexts[position.chapter], let current = newTexts[index] else { continue }
            let start = min(max(0, position.characterOffset), previous.length)
            guard previous.length - start >= 8 else { continue }
            let quote = previous.substring(with: NSRange(location: start, length: min(40, previous.length - start)))
            let lower = max(0, min(start, current.length) - 2048)
            let upper = min(current.length, start + 2048 + (quote as NSString).length)
            var search = NSRange(location: lower, length: max(0, upper - lower))
            var nearest: Int?
            while search.length > 0 {
                let range = current.range(of: quote, options: [], range: search)
                if range.location == NSNotFound { break }
                if nearest == nil || abs(range.location - start) < abs(nearest! - start) { nearest = range.location }
                if range.location >= start { break }
                let next = range.location + 1
                search = NSRange(location: next, length: max(0, upper - next))
            }
            if nearest == nil {
                let first = current.range(of: quote)
                if first.location != NSNotFound {
                    let next = first.location + 1
                    let second = current.range(of: quote, options: [], range: NSRange(location: next, length: current.length - next))
                    if second.location == NSNotFound { nearest = first.location }
                }
            }
            if let nearest { result[position] = .init(bookID: old.id, chapter: index, offset: nearest) }
        }
        return result
    }
}
