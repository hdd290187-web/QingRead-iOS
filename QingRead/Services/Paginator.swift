import Foundation
import CoreText
import UIKit

struct PageRange: Hashable { let start: Int; let length: Int; var end: Int { start + length } }
struct TextLayout {
    let attributed: NSAttributedString
    let ranges: [PageRange]
    let size: CGSize
    func page(containing offset: Int) -> Int {
        ranges.lastIndex { $0.start <= offset } ?? 0
    }
}
struct TextPaginator {
    static func attributed(_ text: String, settings: ReaderSettings, chapterTitle: String? = nil) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = settings.lineSpacing
        style.paragraphSpacing = settings.paragraphSpacing
        style.firstLineHeadIndent = settings.firstLineIndent * settings.fontSize
        style.alignment = .justified
        style.lineBreakMode = .byWordWrapping
        let result = NSMutableAttributedString(string: text, attributes: [.font: settings.uiFont, .foregroundColor: settings.theme.uiForeground, .paragraphStyle: style])
        // Decorate the existing heading without adding/removing a single UTF-16 unit.
        // Persisted positions and bookmarks therefore retain their original meaning.
        if let chapterTitle, let regex = try? NSRegularExpression(pattern: "\\A[\\r\\n\\t ]*([^\\r\\n]+)"),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: result.length)) {
            let range = match.range(at: 1)
            if (text as NSString).substring(with: range).trimmingCharacters(in: .whitespaces) == chapterTitle.trimmingCharacters(in: .whitespaces) {
                let heading = NSMutableParagraphStyle()
                heading.firstLineHeadIndent = 0; heading.alignment = .left
                heading.paragraphSpacingBefore = 12; heading.paragraphSpacing = 24; heading.lineSpacing = 6
                result.addAttributes([.font: YYTheme.serif(max(22, settings.fontSize * 1.15), weight: .semibold), .paragraphStyle: heading], range: range)
            }
        }
        return result
    }
    static func layout(_ text: String, size: CGSize, settings: ReaderSettings, chapterTitle: String? = nil) -> TextLayout {
        let attributed = attributed(text, settings: settings, chapterTitle: chapterTitle)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let safeSize = CGSize(width: max(80, size.width), height: max(settings.fontSize * 3, size.height))
        let path = CGPath(rect: CGRect(origin: .zero, size: safeSize), transform: nil)
        var ranges: [PageRange] = []; var start = 0
        while start < attributed.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            // A zero range signals impossible geometry. Never loop or drop a code unit.
            guard visible.length > 0 else { break }
            ranges.append(PageRange(start: start, length: visible.length)); start += visible.length
        }
        if ranges.isEmpty { ranges = [PageRange(start: 0, length: 0)] }
        return TextLayout(attributed: attributed, ranges: ranges, size: safeSize)
    }
}
