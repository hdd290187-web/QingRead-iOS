import Foundation
import SwiftUI
import UIKit

// Offsets are always UTF-16 code units, matching CoreText, TextKit and NSString.
enum BookFormat: String, Codable { case txt, epub, online
    var title: String { rawValue.uppercased() }
}
struct Chapter: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var length: Int = 0
    var file: String? = nil
    var href: String? = nil
    var remoteURL: URL? = nil
}
struct Book: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var author: String = "未知作者"
    var format: BookFormat
    var importedAt: Date = Date()
    var chapters: [Chapter] = []
    var originalFile: String? = nil
    var source: BookSource? = nil
    var originURL: URL? = nil
    var characterCount: Int { chapters.reduce(0) { $0 + $1.length } }
}
struct ReadingPosition: Codable, Hashable {
    var chapter: Int = 0
    var characterOffset: Int = 0
    var locatorJSON: String? = nil
    var progression: Double = 0
    var updatedAt: Date = Date()
    static var beginning: ReadingPosition { .init() }
}
struct Bookmark: Codable, Hashable, Identifiable {
    var id = UUID()
    var bookID: UUID
    var position: ReadingPosition
    var title: String
    var createdAt = Date()
}
enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case system, white, cream, dark, green
    var id: String { rawValue }
    var title: String { switch self { case .system: "随系统"; case .white: "白纸"; case .cream: "米黄"; case .dark: "深色"; case .green: "护眼" } }
    var uiBackground: UIColor { switch self {
    case .system: .systemBackground
    case .white: UIColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1)
    case .cream: UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1)
    case .dark: UIColor(red: 0.075, green: 0.085, blue: 0.10, alpha: 1)
    case .green: UIColor(red: 0.88, green: 0.93, blue: 0.84, alpha: 1) } }
    var uiForeground: UIColor { self == .system ? .label : self == .dark ? UIColor(white: 0.86, alpha: 1) : UIColor(white: 0.15, alpha: 1) }
    var background: Color { Color(uiColor: uiBackground) }
    var foreground: Color { Color(uiColor: uiForeground) }
}
enum ReaderMode: String, Codable, CaseIterable, Identifiable {
    case slide, cover, curl, scroll
    var id: String { rawValue }
    var title: String { switch self { case .slide: "滑动"; case .cover: "覆盖"; case .curl: "仿真卷曲"; case .scroll: "连续滚动" } }
}
enum ReaderFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif
    var id: String { rawValue }
    var title: String { switch self { case .system: "苹方"; case .rounded: "圆体"; case .serif: "系统衬线" } }
}
struct ReaderSettings: Codable, Equatable {
    var fontSize: Double = 20
    var font: ReaderFont = .system
    var fontWeight: Double = 0
    var lineSpacing: Double = 8
    var paragraphSpacing: Double = 12
    var sidePadding: Double = 24
    var firstLineIndent: Double = 2
    var theme: ReaderTheme = .cream
    var mode: ReaderMode = .slide
    var tapZoneRatio: Double = 0.28
    var rightHanded = false
    var brightness: Double = 0.5
    var customBrightness = false
    var systemColorScheme: ColorScheme? { theme == .dark ? .dark : theme == .system ? nil : .light }
    var uiFont: UIFont {
        let base = UIFont.systemFont(ofSize: fontSize, weight: UIFont.Weight(rawValue: fontWeight))
        let design: UIFontDescriptor.SystemDesign = font == .rounded ? .rounded : font == .serif ? .serif : .default
        return UIFont(descriptor: base.fontDescriptor.withDesign(design) ?? base.fontDescriptor, size: fontSize)
    }
}
struct BookSource: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var searchURL: String
    var headers: [String: String] = [:]
    var search: [String: String] = [:]
    var info: [String: String] = [:]
    var toc: [String: String] = [:]
    var content: [String: String] = [:]
    var issues: [String] = []
    var enabled: Bool = true
    var compatibilityNote: String { issues.isEmpty ? "支持 CSS/基础 JSONPath 子集，未经当前站点实测。" : issues.joined(separator: "\n") }
}
