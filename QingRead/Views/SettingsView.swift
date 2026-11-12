import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        NavigationStack {
            List {
                Section("阅读") { NavigationLink("字体、排版与主题") { ReaderSettingsForm() } }
                Section("在线书源") { NavigationLink("书源管理（\(library.sources.count)）") { SourceManagerView() }; NavigationLink("兼容范围") { SourceGuideView() } }
                Section("阅简") {
                    Text("个人本地书库 · TXT / EPUB").foregroundStyle(.secondary)
                    NavigationLink("开源许可") { LicenseView() }
                    Text("文件、书签和阅读进度保存在本机。卸载会清除数据，请自行备份原始书籍。").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("设置")
        }
    }
}
struct ReaderSettingsForm: View {
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        Form {
            Section("字体") {
                valueSlider("字号", value: $library.settings.fontSize, range: 14...36, unit: "pt")
                Picker("字体", selection: $library.settings.font) { ForEach(ReaderFont.allCases) { Text($0.title).tag($0) } }
                valueSlider("字重", value: $library.settings.fontWeight, range: -0.3...0.5, unit: "")
            }
            Section("排版") {
                valueSlider("行距", value: $library.settings.lineSpacing, range: 0...20, unit: "pt")
                valueSlider("段距", value: $library.settings.paragraphSpacing, range: 0...32, unit: "pt")
                valueSlider("页边距", value: $library.settings.sidePadding, range: 12...48, unit: "pt")
                valueSlider("首行缩进", value: $library.settings.firstLineIndent, range: 0...3, unit: "字")
            }
            Section("主题") {
                Picker("纸张", selection: $library.settings.theme) { ForEach(ReaderTheme.allCases) { Text($0.title).tag($0) } }
                Toggle("自定义屏幕亮度", isOn: $library.settings.customBrightness)
                if library.settings.customBrightness { Slider(value: $library.settings.brightness, in: 0.05...1).accessibilityLabel("屏幕亮度") }
            }
            Section("翻页") {
                Picker("模式", selection: $library.settings.mode) { ForEach(ReaderMode.allCases) { Text($0.title).tag($0) } }
                valueSlider("两侧点击区", value: $library.settings.tapZoneRatio, range: 0.18...0.42, unit: "")
                Toggle("右手单手：左右两侧均向后翻", isOn: $library.settings.rightHanded)
                Text("轻触中央显示或隐藏菜单。TXT 支持原生卷曲与覆盖；EPUB 使用 Readium 滑动 / 滚动，卷曲及覆盖模式自动降级为滑动。").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Button("恢复舒适默认值") { library.settings = ReaderSettings() } }
        }.navigationTitle("阅读设置").navigationBarTitleDisplayMode(.inline)
    }
    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading) { HStack { Text(title); Spacer(); Text(String(format: range.upperBound <= 1 ? "%.2f%@" : "%.0f%@", value.wrappedValue, unit)).foregroundStyle(.secondary).monospacedDigit() }; Slider(value: value, in: range).accessibilityLabel(title) }
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
                ForEach(library.sources) { source in
                    VStack(alignment: .leading, spacing: 5) { Text(source.name).font(.headline); Text(source.compatibilityNote).font(.caption).foregroundStyle(source.issues.isEmpty ? .secondary : .orange) }
                }.onDelete { library.sources.remove(atOffsets: $0) }
            }
        }.navigationTitle("书源管理")
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
        ScrollView { VStack(alignment: .leading, spacing: 20) { Text("阅简使用 Readium Swift Toolkit（BSD-3-Clause）与 SwiftSoup（MIT）及其传递依赖。许可文本随 App 分发。"); ForEach(files, id: \.self) { file in Text((try? String(contentsOf: file)) ?? "").font(.caption.monospaced()).textSelection(.enabled) } }.padding() }.navigationTitle("开源许可")
    }
    private var files: [URL] { (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }
}
