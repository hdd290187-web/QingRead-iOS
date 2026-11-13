import UIKit

private final class ScrollTextCanvas: UIView {
    var drawing: ScrollTextDrawing?
    var padding: CGFloat = 28
    override func draw(_ rect: CGRect) {
        drawing?.draw(at: CGPoint(x: padding, y: 0))
    }
}

final class ScrollTextCell: UITableViewCell {
    private let canvas = ScrollTextCanvas()
    private var chunk: ScrollTextChunk?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        canvas.isOpaque = true; canvas.clipsToBounds = true
        canvas.isAccessibilityElement = true; canvas.accessibilityTraits = .staticText
        canvas.accessibilityIdentifier = "reader.scrollContent"
        canvas.accessibilityLabel = "正文"
        contentView.clipsToBounds = false
        contentView.addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: chunk?.height ?? bounds.height)
    }
    func configure(chunk: ScrollTextChunk, settings: ReaderSettings) {
        ReaderPerformance.measure(.cellConfiguration) {
            if self.chunk?.drawing !== chunk.drawing {
                self.chunk = chunk; canvas.drawing = chunk.drawing
                canvas.accessibilityValue = chunk.attributed.string
            }
            canvas.padding = settings.sidePadding
            applyTheme(settings); setNeedsLayout()
        }
    }
    func applyTheme(_ settings: ReaderSettings) {
        backgroundColor = settings.theme.uiBackground
        canvas.backgroundColor = settings.theme.uiBackground
        canvas.drawing?.setForeground(settings.theme.uiForeground.resolvedColor(with: traitCollection))
        canvas.setNeedsDisplay()
    }
    #if DEBUG
    var renderedText: String { chunk?.attributed.string ?? "" }
    #endif
    var renderedTextBounds: CGRect { chunk?.drawing.usedRect ?? .zero }
    var renderedHeight: CGFloat { canvas.bounds.height }
    var renderedUTF16Length: Int { chunk?.drawing.coveredUTF16 ?? 0 }
    func character(at point: CGPoint) -> Int {
        chunk?.drawing.character(at: CGPoint(x: max(0, point.x - canvas.padding), y: max(0, point.y))) ?? 0
    }
    func y(for offset: Int) -> CGFloat { chunk?.drawing.y(for: offset) ?? 0 }
}
