import SwiftUI
import UIKit

/// Brand values are centralized here; book data and reader preferences keep their existing keys.
enum YYTheme {
    static let name = "予盈"
    static let subtitle = "赠予盈盈的阅读时光"
    static let ink = UIColor(hex: 0x242424)
    static let champagne = UIColor(hex: 0xE7D6C2)
    static let warmWhite = UIColor(hex: 0xF7F6F2)
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xD8BD99) : UIColor(hex: 0x9A744B) })
    static let background = Color(uiColor: uiBackground)
    static let foreground = Color(uiColor: uiForeground)
    static let secondary = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xACA79E) : UIColor(hex: 0x858078) })
    static let separator = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x3A3732) : UIColor(hex: 0xE9E5DE) })
    static let selection = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x4A4033) : champagne.withAlphaComponent(0.62) })
    static let uiBackground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0x22211F) : warmWhite }
    static let uiForeground = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xE5E0D7) : ink }
    static let screenInset: CGFloat = 24
    static let coverRadius: CGFloat = 7
    static let rowSpacing: CGFloat = 24

    static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: "Noto Serif SC", .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
        return UIFont(descriptor: descriptor, size: size)
    }
    static func title(_ size: CGFloat, weight: UIFont.Weight = .semibold) -> Font { Font(serif(size, weight: weight)) }

    static func configureNativeAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = uiBackground
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: uiForeground]
        navigation.largeTitleTextAttributes = [.foregroundColor: uiForeground, .font: serif(30, weight: .semibold)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = uiBackground
        tab.shadowColor = UIColor(hex: 0xDAD4CA).withAlphaComponent(0.45)
        let selected = UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: 0xD8BD99) : UIColor(hex: 0x9A744B) }
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(hex: 0x8A857D)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(hex: 0x8A857D)]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

private struct YYPageStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(YYTheme.background)
            .toolbarBackground(YYTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(YYTheme.accent)
    }
}
extension View { func yyPage() -> some View { modifier(YYPageStyle()) } }

struct BrandMark: View {
    var width: CGFloat = 100
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Image("BrandMark").resizable().scaledToFit().frame(width: width)
            .background {
                RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: YYTheme.warmWhite))
                    .padding(-10).opacity(colorScheme == .dark ? 1 : 0)
            }
            .accessibilityLabel("予盈书本标志")
    }
}

struct BrandLaunchView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(uiColor: YYTheme.warmWhite)
                PaperWaves().fill(Color(uiColor: YYTheme.champagne).opacity(0.35))
                    .frame(height: proxy.size.height * 0.3).frame(maxHeight: .infinity, alignment: .bottom)
                PaperWaves(reverse: true).fill(Color(uiColor: YYTheme.champagne).opacity(0.25))
                    .frame(height: proxy.size.height * 0.23).frame(maxHeight: .infinity, alignment: .bottom)
                VStack(spacing: 0) {
                    BrandMark(width: 116).padding(.bottom, 24)
                    Text(YYTheme.name).font(YYTheme.title(38)).tracking(6).foregroundStyle(Color(uiColor: YYTheme.ink)).padding(.bottom, 18)
                    Text(YYTheme.subtitle).font(.system(size: 12)).tracking(3).foregroundStyle(Color(uiColor: UIColor(hex: 0x756E64)))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).offset(y: -proxy.size.height * 0.055)
            }
        }.ignoresSafeArea().accessibilityIdentifier("brand.launch")
    }
}

/// Original, quiet paper curves, used only as decoration, never as an image of the UI.
struct PaperWaves: Shape {
    var reverse = false
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * (reverse ? 0.9 : 0.18)))
            path.addCurve(to: CGPoint(x: rect.width, y: rect.height * (reverse ? 0.2 : 0.7)), control1: CGPoint(x: rect.width * 0.35, y: rect.height * (reverse ? 0.45 : 0.32)), control2: CGPoint(x: rect.width * 0.62, y: rect.height * (reverse ? 0.28 : 0.85)))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height)); path.closeSubpath()
        }
    }
}
