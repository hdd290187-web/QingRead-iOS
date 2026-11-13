import Foundation
import UIKit

struct ScrollTextLine {
    let start: Int
    let y: CGFloat
}

/// Created and fully laid out by one worker, then used exclusively on the main
/// actor. Drawing the prepared glyphs avoids UITextView performing a second
/// layout with different paragraph metrics.
final class ScrollTextDrawing {
    private let storage: NSTextStorage
    private let manager: NSLayoutManager
    private let container: NSTextContainer
    private let glyphs: NSRange
    private var foreground: UIColor
    let usedRect: CGRect
    let coveredUTF16: Int
    init(storage: NSTextStorage, manager: NSLayoutManager, container: NSTextContainer, foreground: UIColor) {
        self.storage = storage; self.manager = manager; self.container = container; self.foreground = foreground
        glyphs = manager.glyphRange(for: container)
        usedRect = manager.usedRect(for: container)
        coveredUTF16 = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).length
    }
    @MainActor func setForeground(_ color: UIColor) {
        guard !foreground.isEqual(color) else { return }
        foreground = color
        manager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: NSRange(location: 0, length: storage.length))
    }
    @MainActor func draw(at origin: CGPoint) {
        manager.drawBackground(forGlyphRange: glyphs, at: origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }
    @MainActor func character(at point: CGPoint) -> Int {
        min(storage.length, manager.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil))
    }
    @MainActor func y(for offset: Int) -> CGFloat {
        guard storage.length > 0 else { return 0 }
        let characters = NSRange(location: min(max(0, offset), storage.length - 1), length: 1)
        let glyph = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: glyph, in: container).minY
    }
}

struct ScrollTextChunk {
    let range: PageRange
    let attributed: NSAttributedString
    let height: CGFloat
    let lines: [ScrollTextLine]
    let drawing: ScrollTextDrawing

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

    /// Each TextKit stack is laid out on one worker and handed off to the main
    /// actor for drawing. No worker accesses it after publication to the UI.
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
                    let drawing = ScrollTextDrawing(storage: storage, manager: manager, container: container, foreground: foreground)
                    return ScrollTextChunk(range: range, attributed: immutable, height: height, lines: lines, drawing: drawing)
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
