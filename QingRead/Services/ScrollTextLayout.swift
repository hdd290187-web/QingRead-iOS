import Foundation
import UIKit

struct ScrollTextLine {
    let start: Int
    let y: CGFloat
}

struct ScrollTextChunk {
    let range: PageRange
    let attributed: NSAttributedString
    let height: CGFloat
    let lines: [ScrollTextLine]

    /// An O(log lines) UTF-16 anchor, using the same TextKit layout as the cell.
    /// No glyph generation or layout is performed in the scroll delegate.
    func character(atY y: CGFloat) -> Int {
        var low = 0, high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].y <= y { low = middle + 1 } else { high = middle }
        }
        return lines.isEmpty ? 0 : lines[max(0, low - 1)].start
    }
}

struct ScrollChapterLayout {
    let chunks: [ScrollTextChunk]
    let length: Int

    /// Worker-thread-only TextKit objects are discarded before returning immutable
    /// text, exact row heights and line anchors. UITableView only creates visible cells.
    static func make(_ text: String, width: CGFloat, settings: ReaderSettings, chapterTitle: String?, foreground: UIColor) -> ScrollChapterLayout {
        ReaderPerformance.measure(.scrollLayout) {
            let attributed = TextPaginator.attributed(text, settings: settings, chapterTitle: chapterTitle, foreground: foreground)
            let source = text as NSString
            let ranges = chunkRanges(in: source)
            let chunks = ranges.map { range in
                autoreleasepool { () -> ScrollTextChunk in
                    let substring = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: NSRange(location: range.start, length: range.length)))
                    if range.start > 0, !CharacterSet.newlines.contains(UnicodeScalar(source.character(at: range.start - 1)) ?? " ") {
                        // A very long paragraph may span chunks. Its continuation is
                        // not a new paragraph and must not gain a new first-line indent.
                        if let style = substring.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
                           let continuation = style.mutableCopy() as? NSMutableParagraphStyle {
                            continuation.firstLineHeadIndent = continuation.headIndent
                            continuation.paragraphSpacingBefore = 0
                            let firstParagraph = (substring.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
                            substring.addAttribute(.paragraphStyle, value: continuation, range: firstParagraph)
                        }
                    }
                    let immutable = NSAttributedString(attributedString: substring)
                    let storage = NSTextStorage(attributedString: immutable)
                    let manager = NSLayoutManager()
                    manager.usesFontLeading = false
                    manager.allowsNonContiguousLayout = false
                    let container = NSTextContainer(size: CGSize(width: max(80, width - settings.sidePadding * 2), height: .greatestFiniteMagnitude))
                    container.lineFragmentPadding = 0
                    manager.addTextContainer(container); storage.addLayoutManager(manager)
                    manager.ensureLayout(for: container)
                    var lines: [ScrollTextLine] = []
                    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
                        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                        lines.append(ScrollTextLine(start: characters.location, y: rect.minY))
                    }
                    // A trailing newline points at the next chunk's first line.
                    // Keep its paragraph spacing, but do not reserve that empty
                    // line twice across two adjacent table cells.
                    let tail = range.end < attributed.length ? manager.extraLineFragmentRect.minY : manager.extraLineFragmentRect.maxY
                    let height = ceil(max(1, max(manager.usedRect(for: container).maxY, tail)))
                    return ScrollTextChunk(range: range, attributed: immutable, height: height, lines: lines)
                }
            }
            return ScrollChapterLayout(chunks: chunks, length: attributed.length)
        }
    }

    static func chunkRanges(in source: NSString, limit: Int = 1600) -> [PageRange] {
        guard source.length > 0 else { return [] }
        var ranges: [PageRange] = [], start = 0
        while start < source.length {
            var end = min(source.length, start + max(64, limit))
            if end < source.length {
                let newline = source.rangeOfCharacter(from: .newlines, options: .backwards, range: NSRange(location: start, length: end - start))
                if newline.location != NSNotFound, newline.location - start >= limit / 3 { end = NSMaxRange(newline) }
                else { end = NSMaxRange(source.rangeOfComposedCharacterSequence(at: end - 1)) }
                if end < source.length, source.character(at: end - 1) == 13, source.character(at: end) == 10 { end += 1 }
            }
            ranges.append(PageRange(start: start, length: end - start)); start = end
        }
        return ranges
    }
}

struct PreparedReaderChapter {
    var pages: TextLayout?
    var scroll: ScrollChapterLayout?
}

/// Serial background actor bounds layout work and lets superseded font/size
/// requests cancel before expensive work begins. No UIView is created here.
actor ReaderLayoutWorker {
    static let shared = ReaderLayoutWorker()
    func prepare(text: String, size: CGSize, width: CGFloat, settings: ReaderSettings, title: String?, foreground: UIColor) throws -> PreparedReaderChapter {
        try Task.checkCancellation()
        let result: PreparedReaderChapter
        if settings.mode == .scroll {
            result = PreparedReaderChapter(scroll: ScrollChapterLayout.make(text, width: width, settings: settings, chapterTitle: title, foreground: foreground))
        } else {
            result = PreparedReaderChapter(pages: TextPaginator.layout(text, size: size, settings: settings, chapterTitle: title, foreground: foreground))
        }
        try Task.checkCancellation()
        return result
    }
}
