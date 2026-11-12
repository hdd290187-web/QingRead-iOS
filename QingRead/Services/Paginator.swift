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
    static func attributed(_ text: String, settings: ReaderSettings) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = settings.lineSpacing
        style.paragraphSpacing = settings.paragraphSpacing
        style.firstLineHeadIndent = settings.firstLineIndent * settings.fontSize
        style.alignment = .justified
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [.font: settings.uiFont, .foregroundColor: settings.theme.uiForeground, .paragraphStyle: style])
    }
    static func layout(_ text: String, size: CGSize, settings: ReaderSettings) -> TextLayout {
        let attributed = attributed(text, settings: settings)
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
