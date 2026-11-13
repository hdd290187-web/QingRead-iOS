import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        BrandMark(width: 76)
                        Text(YYTheme.name).font(YYTheme.title(30)).tracking(4).foregroundStyle(YYTheme.foreground)
                        Text(YYTheme.subtitle).font(.caption).tracking(2).foregroundStyle(YYTheme.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                Section("阅读") {
                    NavigationLink { ReaderSettingsForm() } label: { Label("字体、排版与主题", systemImage: "textformat.size") }
                    HStack { Label("本机书库", systemImage: "books.vertical"); Spacer(); Text("\(library.books.count) 本").foregroundStyle(YYTheme.secondary) }
                }.listRowBackground(YYTheme.background)
                Section("在线书源") {
                    NavigationLink { SourceManagerView() } label: { Label("书源管理（\(library.sources.count)）", systemImage: "safari") }
                    NavigationLink("兼容范围") { SourceGuideView() }
                }.listRowBackground(YYTheme.background)
                Section(YYTheme.name) {
                    HStack { Text("版本"); Spacer(); Text(version).foregroundStyle(YYTheme.secondary).font(.subheadline) }
                    NavigationLink("开源许可与素材来源") { LicenseView() }
                    Text("书籍、书签和阅读位置留在本机。更新时请覆盖安装，并保留原始书籍备份。").font(.footnote).foregroundStyle(YYTheme.secondary).lineSpacing(5)
                }.listRowBackground(YYTheme.background)
            }.navigationTitle("我的").yyPage()
        }
    }
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0.0") · Build \(info["CFBundleVersion"] as? String ?? "")"
    }
}

struct ReaderSettingsForm: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                fontSection
                rule
                sizeSection
                rule
                lineSection
                rule
                themeSection
                rule
                modeSection
                rule
                NavigationLink { AdvancedReaderSettings() } label: {
                    HStack { Text("更多排版与亮度"); Spacer(); Image(systemName: "chevron.right").font(.caption) }.font(.subheadline).foregroundStyle(YYTheme.foreground).padding(.vertical, 24)
                }.accessibilityIdentifier("settings.advanced")
                rule
                VStack(alignment: .leading, spacing: 14) {
                    Text("即时预览").font(.caption).foregroundStyle(YYTheme.secondary)
                    ReadingPreview(settings: library.settings).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(YYTheme.separator, lineWidth: 0.5))
                }.padding(.top, 24).padding(.bottom, 32)
            }.frame(width: max(240, min(geometry.size.width, 560) - YYTheme.screenInset * 2))
                .padding(.horizontal, YYTheme.screenInset).frame(maxWidth: .infinity)
        }
        }.navigationTitle("阅读设置").navigationBarTitleDisplayMode(.inline).yyPage()
    }
    private var rule: some View { Rectangle().fill(YYTheme.separator).frame(height: 0.5) }
    private var fontSection: some View {
        NavigationLink { ReaderFontPicker() } label: {
            HStack {
                Text("字体").foregroundStyle(YYTheme.foreground)
                Spacer()
                Text(library.settings.font.title).foregroundStyle(YYTheme.secondary)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(YYTheme.secondary)
            }.font(.subheadline).padding(.vertical, 25)
        }.accessibilityIdentifier("settings.font")
    }
    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("字号"); Spacer(); Text("\(Int(library.settings.fontSize)) pt").foregroundStyle(YYTheme.secondary).monospacedDigit().accessibilityIdentifier("settings.fontSize.value") }.font(.subheadline)
            HStack(spacing: 16) {
                Text("A").font(.system(size: 15))
                Slider(value: $library.settings.fontSize, in: 14...36, step: 1).tint(YYTheme.accent).accessibilityLabel("字号").accessibilityIdentifier("settings.fontSize")
                Text("A").font(.system(size: 23))
            }.foregroundStyle(YYTheme.foreground)
        }.padding(.vertical, 24)
    }
    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("行距"); Spacer(); Text("\(Int(library.settings.lineSpacing)) pt").foregroundStyle(YYTheme.secondary).monospacedDigit() }.font(.subheadline)
            HStack(spacing: 14) {
                lineOption("紧凑", value: 4, spacing: 3)
                lineOption("舒适", value: 8, spacing: 5)
                lineOption("宽松", value: 12, spacing: 7)
            }
        }.padding(.vertical, 24)
    }
    private func lineOption(_ title: String, value: Double, spacing: CGFloat) -> some View {
        let selected = abs(library.settings.lineSpacing - value) < 0.1
        return Button { library.settings.lineSpacing = value } label: {
            VStack(spacing: 8) {
                VStack(spacing: spacing) { ForEach(0..<3) { _ in Capsule().frame(width: 22, height: 1) } }.frame(height: 22)
                Text(title).font(.caption2)
            }.foregroundStyle(YYTheme.foreground).frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(selected ? YYTheme.selection : YYTheme.separator.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("\(title)行距").accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("settings.line.\(Int(value))")
    }
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("背景").font(.subheadline)
            HStack(spacing: 0) {
                ForEach([ReaderTheme.white, .cream, .gray, .green, .dark]) { theme in
                    let selected = library.settings.theme == theme
                    Button { library.settings.theme = theme } label: {
                        VStack(spacing: 10) {
                            Circle().fill(theme.background).frame(width: 36, height: 36)
                                .overlay(Circle().stroke(YYTheme.separator, lineWidth: 0.5))
                                .padding(4).overlay(Circle().stroke(selected ? YYTheme.accent.opacity(0.8) : .clear, lineWidth: 1.5))
                            Text(theme.title).font(.system(size: 10)).foregroundStyle(YYTheme.secondary)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("\(theme.title)背景").accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("settings.theme.\(theme.rawValue)")
                }
            }
            Button { library.settings.theme = .system } label: {
                HStack(spacing: 6) {
                    Image(systemName: library.settings.theme == .system ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                    Text("跟随系统外观")
                }.font(.caption).foregroundStyle(YYTheme.secondary)
            }.buttonStyle(.plain).accessibilityIdentifier("settings.theme.system")
        }.padding(.vertical, 24)
    }
    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("翻页方式").font(.subheadline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ReaderMode.allCases) { mode in
                    let selected = library.settings.mode == mode
                    Button { library.settings.mode = mode } label: {
                        HStack(spacing: 8) { Image(systemName: modeIcon(mode)); Text(mode.title).font(.system(size: 13)) }
                            .foregroundStyle(YYTheme.foreground).frame(maxWidth: .infinity, minHeight: 46)
                            .background(selected ? YYTheme.selection : YYTheme.separator.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier("settings.mode.\(mode.rawValue)")
                }
            }
            Text("EPUB 的覆盖与卷曲模式使用滑动翻页。").font(.caption2).foregroundStyle(YYTheme.secondary).lineSpacing(4)
        }.padding(.vertical, 24)
    }
    private func modeIcon(_ mode: ReaderMode) -> String {
        switch mode { case .slide: "arrow.left.and.right"; case .cover: "square.on.square"; case .curl: "book.pages"; case .scroll: "arrow.up.and.down" }
    }
}

private struct ReaderFontPicker: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        List {
            ForEach(ReaderFont.allCases) { font in
                Button { library.settings.font = font } label: {
                    HStack {
                        Text(font.title).font(font == .serif ? YYTheme.title(20) : .system(size: 18, design: font == .rounded ? .rounded : .default)).foregroundStyle(YYTheme.foreground)
                        Spacer()
                        if library.settings.font == font { Image(systemName: "checkmark").foregroundStyle(YYTheme.accent) }
                    }.padding(.vertical, 12)
                }.accessibilityIdentifier("settings.font.\(font.rawValue)").accessibilityAddTraits(library.settings.font == font ? .isSelected : [])
                    .listRowBackground(YYTheme.background)
            }
            Section { Text("思源宋体随 App 提供，遵循 SIL Open Font License；苹方及系统圆体由 iOS 提供。").font(.footnote).foregroundStyle(YYTheme.secondary) }.listRowBackground(YYTheme.background)
        }.navigationTitle("字体").navigationBarTitleDisplayMode(.inline).yyPage()
    }
}

private struct AdvancedReaderSettings: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        Form {
            Section("排版细节") {
                valueSlider("字重", value: $library.settings.fontWeight, range: -0.3...0.5, unit: "")
                valueSlider("行距", value: $library.settings.lineSpacing, range: 0...20, unit: "pt")
                valueSlider("段距", value: $library.settings.paragraphSpacing, range: 0...32, unit: "pt")
                valueSlider("页边距", value: $library.settings.sidePadding, range: 12...48, unit: "pt")
                valueSlider("首行缩进", value: $library.settings.firstLineIndent, range: 0...3, unit: "字")
            }.listRowBackground(YYTheme.background)
            Section("亮度") {
                Toggle("自定义屏幕亮度", isOn: $library.settings.customBrightness)
                if library.settings.customBrightness { Slider(value: $library.settings.brightness, in: 0.05...1).accessibilityLabel("屏幕亮度") }
            }.listRowBackground(YYTheme.background)
            Section("点击与手势") {
                valueSlider("两侧点击区", value: $library.settings.tapZoneRatio, range: 0.18...0.42, unit: "")
                Toggle("右手单手：左右两侧均向后翻", isOn: $library.settings.rightHanded)
                Text("轻触中央显示或隐藏工具栏。四种翻页方式互斥，选择一种即可。").font(.footnote).foregroundStyle(YYTheme.secondary)
            }.listRowBackground(YYTheme.background)
            Section { Button("恢复舒适默认值") { library.settings = ReaderSettings() } }.listRowBackground(YYTheme.background)
        }.navigationTitle("更多阅读设置").navigationBarTitleDisplayMode(.inline).yyPage()
    }
    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title); Spacer(); Text(String(format: range.upperBound <= 3 ? "%.2f%@" : "%.0f%@", value.wrappedValue, unit)).foregroundStyle(YYTheme.secondary).monospacedDigit() }
            Slider(value: value, in: range).accessibilityLabel(title)
        }.font(.subheadline).padding(.vertical, 8)
    }
}

private struct ReadingPreview: UIViewRepresentable {
    var settings: ReaderSettings
    func makeUIView(context: Context) -> UITextView {
        let text = UITextView(usingTextLayoutManager: false)
        text.isEditable = false; text.isSelectable = false; text.isScrollEnabled = false
        text.textContainer.lineFragmentPadding = 0
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.accessibilityIdentifier = "settings.preview"
        return text
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // UITextView's intrinsic width grows with its text/font. The preview must
        // accept SwiftUI's offered width, or it pushes every settings row offscreen.
        let width = proposal.width ?? 0
        let height = proposal.height ?? 180
        return CGSize(width: width.isFinite ? max(0, width) : 0, height: height.isFinite ? max(0, height) : 180)
    }
    func updateUIView(_ view: UITextView, context: Context) {
        view.backgroundColor = settings.theme.uiBackground
        view.textContainerInset = UIEdgeInsets(top: 16, left: settings.sidePadding, bottom: 16, right: settings.sidePadding)
        view.attributedText = TextPaginator.attributed("窗外的雨下得很轻，像是不忍打扰屋内的安静。\n有些故事，从一开始，就注定会让人沉浸。", settings: settings)
        view.accessibilityValue = "\(settings.font.title)，\(Int(settings.fontSize))点，\(settings.theme.title)背景"
    }
}
struct SourceManagerView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importFile = false
    @State private var url = ""
    @State private var text = ""
    @State private var message: String?
    @State private var busy = false
    var body: some View {
        List {
            Section("导入") {
                Button("从文件导入 JSON") { importFile = true }
                TextField("https://…/sources.json", text: $url).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                Button("从 URL 导入") { importURL() }.disabled(busy || url.isEmpty)
                TextEditor(text: $text).frame(minHeight: 90).overlay(alignment: .topLeading) { if text.isEmpty { Text("粘贴书源 JSON").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false) } }
                Button("导入粘贴内容") { accept(Data(text.utf8)) }.disabled(text.isEmpty)
                if busy { ProgressView() }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            Section("已导入") {
                ForEach(Array(library.sources.enumerated()), id: \.element.id) { _, source in
                    VStack(alignment: .leading, spacing: 5) { Text(source.name).font(.headline); Text(source.compatibilityNote).font(.caption).foregroundStyle(source.issues.isEmpty ? Color.secondary : Color.orange) }
                }.onDelete { offsets in for index in offsets.sorted(by: >) { library.removeSource(at: index) } }
            }
        }.navigationTitle("书源管理").yyPage()
            .fileImporter(isPresented: $importFile, allowedContentTypes: [.json]) { result in
                do { let file = try result.get(); let access = file.startAccessingSecurityScopedResource(); defer { if access { file.stopAccessingSecurityScopedResource() } }; accept(try Data(contentsOf: file)) } catch { message = error.localizedDescription }
            }
    }
    private func accept(_ data: Data) {
        do { let sources = try BookSourceService.importSources(data); sources.forEach { library.saveSource($0) }; message = "已导入 \(sources.count) 个书源。兼容性说明见下方。" } catch { message = error.localizedDescription }
    }
    private func importURL() {
        busy = true
        Task { defer { busy = false }; do { accept(try await BookSourceService().downloadSource(url)) } catch { message = error.localizedDescription } }
    }
}
struct LicenseView: View {
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { Text("予盈使用 Readium Swift Toolkit（BSD-3-Clause）与 SwiftSoup（MIT）及其传递依赖。许可文本随 App 分发。"); ForEach(files, id: \.self) { file in Text((try? String(contentsOf: file)) ?? "").font(.caption.monospaced()).textSelection(.enabled) } }.padding() }.navigationTitle("开源许可与素材来源").yyPage()
    }
    private var files: [URL] { (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }
}
