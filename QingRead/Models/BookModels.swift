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
    var sourceIdentity: String? = nil
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
    var locationKey: String {
        if let json = position.locatorJSON,
           let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            let locations = value["locations"] as? [String: Any] ?? [:]
            let text = value["text"] as? [String: Any] ?? [:]
            let stableLocations: [String: Any] = [
                "fragments": locations["fragments"] ?? [],
                "position": locations["position"] ?? NSNull()
            ]
            let stableText: [String: Any] = ["before": text["before"] ?? NSNull(), "after": text["after"] ?? NSNull()]
            var anchor: [String: Any] = ["href": value["href"] ?? "", "locations": stableLocations, "text": stableText]
            if stableLocations["position"] is NSNull,
               (stableLocations["fragments"] as? [Any] ?? []).isEmpty,
               stableText["before"] is NSNull, stableText["after"] is NSNull {
                let progression = (locations["progression"] as? Double) ?? position.progression
                anchor["progressionBucket"] = (progression * 10_000).rounded() / 10_000
            }
            if let data = try? JSONSerialization.data(withJSONObject: anchor, options: [.sortedKeys]),
               let key = String(data: data, encoding: .utf8) { return bookID.uuidString + ":epub:" + key }
            return bookID.uuidString + ":epub:" + json
        }
        return "\(bookID.uuidString):\(position.chapter):\(position.characterOffset)"
    }
}
enum ReaderTheme: String, Codable, CaseIterable, Identifiable {
    case system, white, cream, dark, green, gray
    var id: String { rawValue }
    var title: String { switch self { case .system: "随系统"; case .white: "暖白"; case .cream: "米黄"; case .dark: "深色"; case .green: "护眼绿"; case .gray: "浅灰" } }
    var uiBackground: UIColor { switch self {
    case .system: YYTheme.uiBackground
    case .white: YYTheme.warmWhite
    case .cream: UIColor(hex: 0xEFE3D2)
    case .dark: UIColor(hex: 0x242321)
    case .green: UIColor(hex: 0xE1E7D9)
    case .gray: UIColor(hex: 0xEAE9E5) } }
    var uiForeground: UIColor { self == .system ? YYTheme.uiForeground : self == .dark ? UIColor(hex: 0xDAD5CB) : YYTheme.ink }
    var background: Color { Color(uiColor: uiBackground) }
    var foreground: Color { Color(uiColor: uiForeground) }
}
enum ReaderMode: String, Codable, CaseIterable, Identifiable {
    case slide, cover, curl, scroll
    var id: String { rawValue }
    var title: String { switch self { case .slide: "滑动"; case .cover: "覆盖"; case .curl: "仿真卷曲"; case .scroll: "连续滚动" } }
}
enum ReaderFont: String, Codable, CaseIterable, Identifiable {
    case system, rounded, serif, kaiti, heiti
    var id: String { rawValue }
    var title: String { switch self {
    case .system: "苹方"; case .rounded: "系统圆体"; case .serif: "思源宋体"
    case .kaiti: "霞鹜文楷"; case .heiti: "华文黑体" } }
    var installedName: String? {
        let candidates: [String]
        switch self {
        case .kaiti: candidates = ["LXGWWenKaiLite-Regular"]
        case .heiti: candidates = ["STHeitiSC-Light"]
        default: return nil
        }
        return candidates.first { UIFont(name: $0, size: 20) != nil }
    }
    static var available: [ReaderFont] { allCases.filter { [.system, .rounded, .serif].contains($0) || $0.installedName != nil } }
    var cssFamily: String {
        switch self {
        case .serif: return "Noto Serif SC"
        case .rounded: return "ui-rounded"
        case .system: return "sans-serif"
        default: return installedName.flatMap { UIFont(name: $0, size: 20)?.familyName } ?? "Noto Serif SC"
        }
    }
}
struct ReaderSettings: Codable, Equatable {
    var fontSize: Double = 20
    var font: ReaderFont = .serif
    var fontWeight: Double = 0
    var lineSpacing: Double = 8
    var paragraphSpacing: Double = 12
    var sidePadding: Double = 28
    var firstLineIndent: Double = 2
    var theme: ReaderTheme = .white
    var mode: ReaderMode = .slide
    var tapZoneRatio: Double = 0.28
    var rightHanded = false
    var brightness: Double = 0.5
    var customBrightness = false
    var showBottomProgress = true

    init() {}
    private enum CodingKeys: String, CodingKey {
        case fontSize, font, fontWeight, lineSpacing, paragraphSpacing, sidePadding, firstLineIndent, theme, mode, tapZoneRatio, rightHanded, brightness, customBrightness, showBottomProgress
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        fontSize = try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize
        font = try values.decodeIfPresent(ReaderFont.self, forKey: .font) ?? font
        fontWeight = try values.decodeIfPresent(Double.self, forKey: .fontWeight) ?? fontWeight
        lineSpacing = try values.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? lineSpacing
        paragraphSpacing = try values.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? paragraphSpacing
        sidePadding = try values.decodeIfPresent(Double.self, forKey: .sidePadding) ?? sidePadding
        firstLineIndent = try values.decodeIfPresent(Double.self, forKey: .firstLineIndent) ?? firstLineIndent
        theme = try values.decodeIfPresent(ReaderTheme.self, forKey: .theme) ?? theme
        mode = try values.decodeIfPresent(ReaderMode.self, forKey: .mode) ?? mode
        tapZoneRatio = try values.decodeIfPresent(Double.self, forKey: .tapZoneRatio) ?? tapZoneRatio
        rightHanded = try values.decodeIfPresent(Bool.self, forKey: .rightHanded) ?? rightHanded
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? brightness
        customBrightness = try values.decodeIfPresent(Bool.self, forKey: .customBrightness) ?? customBrightness
        showBottomProgress = try values.decodeIfPresent(Bool.self, forKey: .showBottomProgress) ?? true
    }
    func hasSameTextLayout(as other: ReaderSettings) -> Bool {
        fontSize == other.fontSize && font == other.font && fontWeight == other.fontWeight &&
        lineSpacing == other.lineSpacing && paragraphSpacing == other.paragraphSpacing &&
        sidePadding == other.sidePadding && firstLineIndent == other.firstLineIndent
    }
    var systemColorScheme: ColorScheme? { theme == .dark ? .dark : theme == .system ? nil : .light }
    var uiFont: UIFont {
        if let name = font.installedName, let face = UIFont(name: name, size: fontSize) {
            let descriptor = face.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: fontWeight]])
            return UIFont(descriptor: descriptor, size: fontSize)
        }
        if font == .serif || !ReaderFont.available.contains(font) {
            let descriptor = UIFontDescriptor(fontAttributes: [.family: "Noto Serif SC", .traits: [UIFontDescriptor.TraitKey.weight: fontWeight]])
            return UIFont(descriptor: descriptor, size: fontSize)
        }
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
