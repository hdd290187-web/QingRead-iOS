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
    @State private var settingsDetent: PresentationDetent = .fraction(0.55)

    private var chapterTitle: String { session.chapters.indices.contains(session.position.chapter) ? session.chapters[session.position.chapter].title : session.book.title }
    private var foreground: Color { library.settings.theme.foreground }
    var body: some View {
        ZStack {
            library.settings.theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    if session.book.format == .epub { EPUBReader(session: session, settings: library.settings) }
                    else { NativeReader(session: session, settings: library.settings) }
                }.transaction { $0.animation = nil }
                if library.settings.showBottomProgress {
                    compactProgress.frame(height: 28).contentShape(Rectangle())
                        .onTapGesture { session.menuVisible.toggle() }
                        .accessibilityIdentifier("reader.compactProgress")
                }
            }
            if session.menuVisible {
                VStack(spacing: 0) {
                    header.frame(height: 52).background(library.settings.theme.background.opacity(0.98))
                    Spacer(minLength: 0)
                    controls.padding(.bottom, library.settings.showBottomProgress ? 28 : 0)
                }.transition(.opacity)
            }
            if session.isLoading { ProgressView("正在准备正文…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
        }.tint(YYTheme.accent)
        .animation(.easeOut(duration: 0.18), value: session.menuVisible)
        .preferredColorScheme(library.settings.systemColorScheme)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showContents) { ContentsSheet(session: session).presentationBackground(YYTheme.background) }
        .sheet(isPresented: $showSettings, onDismiss: { library.flushSettingsIfNeeded() }) {
            NavigationStack {
                ReaderSettingsForm().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showSettings = false }.accessibilityIdentifier("reader.settings.done") } }
            }.environment(\.readerSettingsOverlay, true)
                .presentationDetents([.fraction(0.55), .fraction(0.78)], selection: $settingsDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.78)))
                .presentationBackground {
                    Rectangle().fill(.thinMaterial).overlay(library.settings.theme.background.opacity(0.28))
                }.preferredColorScheme(library.settings.systemColorScheme)
        }
        .sheet(isPresented: $showBookmarks) { bookmarksSheet.presentationBackground(YYTheme.background) }
        .alert("阅读提示", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("重试本章") { session.error = nil; session.restore(session.position) }
            Button("关闭", role: .cancel) { session.error = nil }
        } message: { Text(session.error ?? "") }
        .onChange(of: library.settings) { _, _ in applyBrightness(); session.applySettings() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.flush() } }
        .onAppear { originalBrightness = UIScreen.main.brightness; applyBrightness() }
        .onDisappear { session.flush(); if let originalBrightness { UIScreen.main.brightness = originalBrightness } }
    }
    private var header: some View {
        ZStack {
            HStack(spacing: 0) {
                tool("返回书架", icon: "chevron.left") { dismiss() }
                Text(session.book.title).font(.system(size: 12)).foregroundStyle(foreground.opacity(0.5)).lineLimit(1).padding(.horizontal, 8)
                Spacer(minLength: 4)
                Button { showSettings = true } label: { Text("Aa").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44) }
                    .accessibilityLabel("阅读设置").accessibilityIdentifier("reader.settings")
                tool(session.hasBookmark ? "取消书签" : "添加书签", icon: session.hasBookmark ? "bookmark.fill" : "bookmark") { session.bookmark() }
                    .accessibilityIdentifier("reader.bookmark").accessibilityValue(session.hasBookmark ? "已收藏" : "未收藏")
                Menu {
                    Button("目录", systemImage: "list.bullet") { showContents = true }
                    Button("书签", systemImage: "bookmark") { showBookmarks = true }
                    Divider()
                    Button("上一章", systemImage: "chevron.left") { session.jump(session.position.chapter - 1) }.disabled(session.position.chapter <= 0)
                    Button("下一章", systemImage: "chevron.right") { session.jump(session.position.chapter + 1) }.disabled(session.position.chapter + 1 >= session.chapters.count)
                } label: { Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 44, height: 44) }
                    .accessibilityLabel("更多阅读操作").accessibilityIdentifier("reader.more")
            }.foregroundStyle(foreground).padding(.horizontal, 10).opacity(session.menuVisible ? 1 : 0).allowsHitTesting(session.menuVisible)
        }
    }
    private func tool(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 19, weight: .regular)).frame(width: 44, height: 44) }.accessibilityLabel(label)
    }
    private var compactProgress: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(chapterTitle).lineLimit(1).accessibilityIdentifier("reader.chapterTitle")
                Text(session.pageInfo).accessibilityIdentifier("reader.pageInfo")
                Spacer(minLength: 0)
                Text("\(Int(min(1, max(0, session.position.progression)) * 100))%").accessibilityIdentifier("reader.progress")
            }.font(.system(size: 10)).monospacedDigit().foregroundStyle(foreground.opacity(0.55))
            ProgressView(value: min(1, max(0, session.position.progression))).tint(YYTheme.accent).frame(height: 2)
        }.padding(.horizontal, library.settings.sidePadding).padding(.bottom, 4)
    }
    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Button("上一章") { session.jump(session.position.chapter - 1) }.disabled(session.position.chapter <= 0)
                Spacer()
                Text("\(min(session.position.chapter + 1, session.chapters.count)) / \(session.chapters.count) 章").monospacedDigit()
                Spacer()
                Button("下一章") { session.jump(session.position.chapter + 1) }.disabled(session.position.chapter + 1 >= session.chapters.count)
            }.font(.system(size: 12)).frame(height: 32)
            Slider(value: Binding(get: { draggingProgress ? chapterSlider : Double(session.position.chapter) }, set: { chapterSlider = $0 }), in: 0...Double(max(1, session.chapters.count - 1)), step: 1) { editing in
                if editing { chapterSlider = Double(session.position.chapter) }
                draggingProgress = editing
                if !editing { session.jump(Int(chapterSlider)) }
            }.accessibilityLabel("阅读进度").frame(height: 32)
            HStack {
                Button { showContents = true } label: { Label("目录", systemImage: "list.bullet") }
                Spacer()
                Button { showSettings = true } label: { Label("排版", systemImage: "textformat.size") }
                Spacer()
                Button { showBookmarks = true } label: { Label("书签", systemImage: "bookmark") }
            }.font(.system(size: 13)).frame(height: 44)
        }.foregroundStyle(foreground.opacity(0.86)).padding(.horizontal, library.settings.sidePadding).padding(.top, 8)
            .background(library.settings.theme.background.opacity(0.98))
    }
    private var bookmarksSheet: some View {
        NavigationStack {
            List {
                if library.bookmarks(for: session.book).isEmpty { Text("暂无书签，点阅读页右上角添加。").foregroundStyle(YYTheme.secondary) }
                ForEach(library.bookmarks(for: session.book)) { bookmark in
                    Button { session.restore(bookmark.position); showBookmarks = false } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(bookmark.title).foregroundStyle(YYTheme.foreground)
                            Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(YYTheme.secondary)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("reader.bookmark.item.\(bookmark.id.uuidString)").swipeActions { Button("删除", role: .destructive) { library.deleteBookmark(bookmark) } }
                }.listRowBackground(YYTheme.background)
            }.navigationTitle("书签").navigationBarTitleDisplayMode(.inline).yyPage()
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showBookmarks = false } } }
        }
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
            }.searchable(text: $query, prompt: "查找章节").navigationTitle("目录").navigationBarTitleDisplayMode(.inline).yyPage()
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }; if session.book.format == .online { ToolbarItem(placement: .bottomBar) { Button("缓存全部章节") { Task { await session.downloadAll() } }.disabled(session.isLoading) } } }
        }
    }
}
