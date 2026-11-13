import UIKit

final class ScrollTextCell: UITableViewCell {
    let textView = UITextView(usingTextLayoutManager: false)
    private var configuredText: ObjectIdentifier?
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        textView.isEditable = false; textView.isSelectable = false; textView.isScrollEnabled = false
        textView.layoutManager.usesFontLeading = false
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    func configure(text: NSAttributedString, settings: ReaderSettings) {
        ReaderPerformance.measure(.cellConfiguration) {
            backgroundColor = settings.theme.uiBackground
            textView.textContainerInset = UIEdgeInsets(top: 0, left: settings.sidePadding, bottom: 0, right: settings.sidePadding)
            if configuredText != ObjectIdentifier(text) {
                textView.attributedText = text
                configuredText = ObjectIdentifier(text)
            }
            applyTheme(settings)
            textView.accessibilityIdentifier = "reader.scrollContent"
        }
    }
    func applyTheme(_ settings: ReaderSettings) {
        backgroundColor = settings.theme.uiBackground
        textView.textColor = settings.theme.uiForeground
    }
    func character(at point: CGPoint) -> Int {
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let local = convert(point, to: textView)
        let textPoint = CGPoint(x: max(0, local.x - textView.textContainerInset.left), y: max(0, local.y - textView.textContainerInset.top))
        return min(textView.attributedText.length, textView.layoutManager.characterIndex(for: textPoint, in: textView.textContainer, fractionOfDistanceBetweenInsertionPoints: nil))
    }
    func y(for offset: Int) -> CGFloat {
        guard textView.attributedText.length > 0 else { return 0 }
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        let range = NSRange(location: min(max(0, offset), textView.attributedText.length - 1), length: 1)
        let glyph = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return textView.layoutManager.boundingRect(forGlyphRange: glyph, in: textView.textContainer).minY + textView.textContainerInset.top
    }
}
