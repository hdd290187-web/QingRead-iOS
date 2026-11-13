import SwiftUI

struct CoverView: View {
    let book: Book
    var size: CGSize? = nil
    @State private var cover: BookCover?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: YYTheme.champagne).opacity(0.55)
                if let cover {
                    Image(uiImage: cover.image).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }.aspectRatio(400.0 / 588, contentMode: .fit)
            .frame(width: size?.width, height: size?.height)
            .clipShape(RoundedRectangle(cornerRadius: YYTheme.coverRadius))
            .overlay(RoundedRectangle(cornerRadius: YYTheme.coverRadius).stroke(.black.opacity(0.035), lineWidth: 0.5))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(book.title)的封面")
            .accessibilityValue(cover == nil ? "正在准备" : cover?.kind == .epub ? "书籍原封面" : "自然图案")
            .accessibilityIdentifier("book.cover.\(book.title)")
            .task(id: book.id) {
                let result = await BookCoverCache.shared.cover(for: book)
                guard !Task.isCancelled else { return }; cover = result
            }
    }
}
