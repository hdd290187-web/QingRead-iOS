import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator
import WebKit

struct EPUBReader: UIViewControllerRepresentable {
    @ObservedObject var session: ReaderSession
    var settings: ReaderSettings
    func makeUIViewController(context: Context) -> EPUBReaderController { EPUBReaderController(session: session, settings: settings) }
    func updateUIViewController(_ controller: EPUBReaderController, context: Context) { controller.apply(settings: settings) }
}
@MainActor
final class EPUBReaderController: UIViewController, ReadingEngine, EPUBNavigatorDelegate {
    private let session: ReaderSession
    private var settings: ReaderSettings
    private let service = EPUBService()
    private var publication: Publication?
    private var navigator: EPUBNavigatorViewController?
    private var toc: [ReadiumShared.Link] = []
    init(session: ReaderSession, settings: ReaderSettings) { self.session = session; self.settings = settings; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad(); session.engine = self; view.backgroundColor = settings.theme.uiBackground
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: EPUBReaderController, _: UITraitCollection) in
            if controller.settings.theme == .system { controller.navigator?.submitPreferences(controller.preferences()) }
        }
        Task { await open() }
    }
    private func open() async {
        session.isLoading = true; defer { session.isLoading = false }
        do {
            guard let path = session.book.originalFile else { throw ReaderError.message("书籍文件已丢失，请重新导入。") }
            let publication = try await service.open(path: path); self.publication = publication
            let tableOfContents = (try? await publication.tableOfContents().get()) ?? []
            toc = EPUBService.flatten(tableOfContents.isEmpty ? publication.readingOrder : tableOfContents)
            session.chapters = toc.map { Chapter(title: $0.title ?? "章节", href: $0.href) }
            var locator: Locator?
            if let json = session.position.locatorJSON { locator = try Locator(json: JSONValue(jsonString: json), warnings: nil) }
            let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: locator, config: .init(preferences: preferences(), disablePageTurnsWhileScrolling: true, fontFamilyDeclarations: fontDeclarations()))
            navigator.delegate = self; self.navigator = navigator
            navigator.addObserver(.tap { [weak self] event in
                guard let self else { return false }
                let ratio = event.location.x / max(1, self.view.bounds.width)
                if ratio < self.settings.tapZoneRatio { self.move(forward: self.settings.rightHanded) }
                else if ratio > 1 - self.settings.tapZoneRatio { self.move(forward: true) }
                else { self.session.menuVisible.toggle() }
                return true
            })
            addChild(navigator); navigator.view.frame = view.bounds; navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(navigator.view); navigator.didMove(toParent: self)
        } catch { session.error = "EPUB 打开失败：\(error.localizedDescription)" }
    }
    private func fontDeclarations() -> [AnyHTMLFontFamilyDeclaration] {
        guard let url = Bundle.main.url(forResource: "NotoSerifSC", withExtension: "ttf"), let file = FileURL(url: url) else { return [] }
        return [CSSFontFamilyDeclaration(fontFamily: "Noto Serif SC", fontFaces: [CSSFontFace(file: file, style: .normal, weight: .variable(200...900))]).eraseToAnyHTMLFontFamilyDeclaration()]
    }
    private func preferences() -> EPUBPreferences {
        Self.preferences(settings: settings, traits: traitCollection)
    }
    static func preferences(settings: ReaderSettings, traits: UITraitCollection) -> EPUBPreferences {
        var prefs = EPUBPreferences()
        prefs.fontSize = settings.fontSize / 16
        prefs.fontWeight = 1 + settings.fontWeight
        prefs.lineHeight = (settings.fontSize + settings.lineSpacing) / settings.fontSize
        prefs.paragraphSpacing = settings.paragraphSpacing / settings.fontSize
        prefs.paragraphIndent = settings.firstLineIndent
        prefs.pageMargins = settings.sidePadding / 24
        prefs.publisherStyles = false
        prefs.scroll = settings.mode == .scroll
        prefs.columnCount = .one
        prefs.backgroundColor = ReadiumNavigator.Color(uiColor: settings.theme.uiBackground.resolvedColor(with: traits))
        prefs.textColor = ReadiumNavigator.Color(uiColor: settings.theme.uiForeground.resolvedColor(with: traits))
        prefs.fontFamily = FontFamily(rawValue: settings.font == .serif ? "Noto Serif SC" : settings.font == .rounded ? "ui-rounded" : "sans-serif")
        prefs.theme = settings.theme == .dark || (settings.theme == .system && traits.userInterfaceStyle == .dark) ? .dark : settings.theme == .cream ? .sepia : .light
        return prefs
    }
    func apply(settings newSettings: ReaderSettings) { guard settings != newSettings else { return }; settings = newSettings; view.backgroundColor = settings.theme.uiBackground; navigator?.submitPreferences(preferences()) }
    func move(forward: Bool) { Task { guard let navigator else { return }; if forward { _ = await navigator.goForward() } else { _ = await navigator.goBackward() } } }
    func navigate(to position: ReadingPosition) {
        Task {
            guard let navigator else { return }
            if let json = position.locatorJSON, let locator = try? Locator(json: JSONValue(jsonString: json), warnings: nil) { _ = await navigator.go(to: locator); return }
            if toc.indices.contains(position.chapter) { _ = await navigator.go(to: toc[position.chapter]) }
        }
    }
    func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
        // ReaderHost already places this child inside safe areas and reserves both
        // toolbars. Readium's window-based defaults would apply those insets twice.
        UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    }
    func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts controller: WKUserContentController) {
        guard publication?.metadata.layout != .fixed else { return }
        let script = """
        (() => {
          const style = document.createElement('style');
          style.textContent = 'h1,h2 { font-size:1.15em !important; font-family:inherit !important; font-weight:600 !important; line-height:1.5 !important; text-align:left !important; margin-block-start:12px !important; margin-block-end:24px !important; }';
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }
    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        let href = locator.href.string.components(separatedBy: "#")[0]
        let index = toc.lastIndex(where: { $0.href.components(separatedBy: "#")[0] == href }) ?? 0
        let json = try? locator.jsonString()
        session.report(ReadingPosition(chapter: index, locatorJSON: json, progression: locator.locations.totalProgression ?? 0), pageInfo: "\(Int((locator.locations.totalProgression ?? 0) * 100))%")
    }
    func navigator(_ navigator: Navigator, presentError error: NavigatorError) { session.error = "阅读器无法完成当前操作。" }
    func navigator(_ navigator: Navigator, presentExternalURL url: URL) { /* Book links cannot silently leave the reader. */ }
    func navigator(_ navigator: Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) { session.error = "无法加载 EPUB 内部资源，请检查原书是否完整。" }
}
