import SwiftUI

struct ReaderView: View {
    let book: Book
    @EnvironmentObject private var library: LibraryStore
    var body: some View { ReaderHost(session: ReaderSession(book: book, library: library)).environmentObject(library) }
}
private struct ReaderHost: View {
    @StateObject var session: ReaderSession
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showContents = false
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var chapterSlider = 0.0
    @State private var draggingProgress = false
    @State private var originalBrightness: CGFloat?
    @State private var bookmarkAdded = false
    var body: some View {
        ZStack {
            library.settings.theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Text(session.chapters.indices.contains(session.position.chapter) ? session.chapters[session.position.chapter].title : session.book.title)
                    .font(.caption).foregroundStyle(library.settings.theme.foreground.opacity(0.6)).lineLimit(1).padding(.horizontal, 24).frame(height: 28)
                Group {
                    if session.book.format == .epub { EPUBReader(session: session, settings: library.settings) }
                    else { NativeReader(session: session, settings: library.settings) }
                }
                HStack { Text(Date(), style: .time); Spacer(); Text(session.pageInfo).accessibilityIdentifier("reader.pageInfo"); Spacer(); Text("\(Int(session.position.progression * 100))%") }
                    .font(.caption2).monospacedDigit().foregroundStyle(library.settings.theme.foreground.opacity(0.6)).padding(.horizontal, 24).frame(height: 24)
            }
            if session.isLoading { ProgressView("正在准备正文…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            if session.menuVisible { controls.transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.18), value: session.menuVisible)
        .preferredColorScheme(library.settings.systemColorScheme)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showContents) { ContentsSheet(session: session) }
        .sheet(isPresented: $showSettings, onDismiss: { session.applySettings() }) { NavigationStack { ReaderSettingsForm().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showSettings = false } } } }.presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showBookmarks) { bookmarksSheet }
        .alert("阅读提示", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("重试本章") { session.error = nil; session.restore(session.position) }
            Button("关闭", role: .cancel) { session.error = nil }
        } message: { Text(session.error ?? "") }
        .onChange(of: library.settings) { _, _ in applyBrightness() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { library.update(position: session.position, for: session.book) } }
        .onAppear { originalBrightness = UIScreen.main.brightness; applyBrightness() }
        .onDisappear { library.update(position: session.position, for: session.book); if let originalBrightness { UIScreen.main.brightness = originalBrightness } }
    }
    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel("返回书架")
                Text(session.book.title).font(.headline).lineLimit(1); Spacer()
                Button { session.bookmark(); bookmarkAdded = true } label: { Image(systemName: bookmarkAdded ? "bookmark.fill" : "bookmark").frame(width: 44, height: 44) }.accessibilityLabel("添加书签")
            }.padding(.horizontal, 8).background(.regularMaterial)
            Spacer()
            VStack(spacing: 16) {
                HStack {
                    Button("上一章") { session.jump(session.position.chapter - 1) }.disabled(session.position.chapter <= 0)
                    Spacer(); Text("\(min(session.position.chapter + 1, session.chapters.count)) / \(session.chapters.count) 章").font(.caption).monospacedDigit(); Spacer()
                    Button("下一章") { session.jump(session.position.chapter + 1) }.disabled(session.position.chapter + 1 >= session.chapters.count)
                }.font(.subheadline)
                Slider(value: Binding(get: { draggingProgress ? chapterSlider : Double(session.position.chapter) }, set: { chapterSlider = $0 }), in: 0...Double(max(1, session.chapters.count - 1)), step: 1) { editing in if editing { chapterSlider = Double(session.position.chapter) }; draggingProgress = editing; if !editing { session.jump(Int(chapterSlider)) } }.accessibilityLabel("阅读进度")
                HStack {
                    Button { showContents = true } label: { Label("目录", systemImage: "list.bullet") }; Spacer()
                    Button { showSettings = true } label: { Label("排版", systemImage: "textformat.size") }; Spacer()
                    Button { showBookmarks = true } label: { Label("书签", systemImage: "bookmark") }
                }.font(.subheadline)
                if session.book.format == .epub && [.cover, .curl].contains(library.settings.mode) { Text("此 EPUB 使用滑动翻页").font(.caption).foregroundStyle(.secondary) }
            }.padding(20).background(.regularMaterial)
        }.foregroundStyle(.primary)
    }
    private var bookmarksSheet: some View {
        NavigationStack { List {
            if library.bookmarks(for: session.book).isEmpty { Text("暂无书签，在阅读菜单右上角添加。") }
            ForEach(library.bookmarks(for: session.book)) { bookmark in
                Button { session.restore(bookmark.position); showBookmarks = false } label: { VStack(alignment: .leading) { Text(bookmark.title); Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) } }
                    .swipeActions { Button("删除", role: .destructive) { library.deleteBookmark(bookmark) } }
            }
        }.navigationTitle("书签").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showBookmarks = false } } } }
    }
    private func applyBrightness() { if library.settings.customBrightness { UIScreen.main.brightness = library.settings.brightness } else if let originalBrightness { UIScreen.main.brightness = originalBrightness } }
}
private struct ContentsSheet: View {
    @ObservedObject var session: ReaderSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(session.chapters.enumerated()), id: \.element.id) { index, chapter in
                        if query.isEmpty || chapter.title.localizedCaseInsensitiveContains(query) {
                            Button { session.jump(index); dismiss() } label: {
                                HStack { Text(chapter.title).foregroundStyle(index == session.position.chapter ? Color.accentColor : .primary); Spacer(); if index == session.position.chapter { Image(systemName: "book.fill") } }
                            }.id(index)
                        }
                    }
                }.onAppear { proxy.scrollTo(session.position.chapter, anchor: .center) }
            }.searchable(text: $query, prompt: "查找章节").navigationTitle("目录")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }; if session.book.format == .online { ToolbarItem(placement: .bottomBar) { Button("缓存全部章节") { Task { await session.downloadAll() } }.disabled(session.isLoading) } } }
        }
    }
}
