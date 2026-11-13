import SwiftUI
import UIKit

struct CloudLibraryView: View {
    @EnvironmentObject private var cloud: CloudLibraryStore
    @EnvironmentObject private var library: LibraryStore
    @State private var showConnection = false
    @State private var updateBook: CloudBook?
    private var searchKey: String { cloud.query + "|" + cloud.format + "|" + cloud.sort.rawValue }

    var body: some View {
        VStack(spacing: 0) {
            if cloud.connected { filters }
            if !cloud.connected {
                ContentUnavailableView {
                    Label("你的私人云书库", systemImage: "books.vertical")
                } description: {
                    Text(cloud.message ?? "连接后即可浏览、下载自己的 TXT 和 EPUB，下载后从书架离线阅读。")
                } actions: {
                    Button("连接云书库") { showConnection = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("cloud.connect")
                }
            } else {
                List {
                    if let message = cloud.message {
                        Section {
                            Text(message).font(.footnote).foregroundStyle(YYTheme.secondary).accessibilityIdentifier("cloud.error")
                            Button("重试") { Task { await cloud.refresh() } }.accessibilityIdentifier("cloud.retry")
                        }.listRowBackground(YYTheme.background)
                    }
                    if cloud.books.isEmpty {
                        Section {
                            if cloud.loading { HStack { Spacer(); ProgressView("正在读取书库…"); Spacer() }.padding(.vertical, 32) }
                            else if cloud.message == nil {
                                ContentUnavailableView(cloud.query.isEmpty ? "云书库暂无小说" : "没有找到小说", systemImage: "books.vertical",
                                                       description: Text(cloud.query.isEmpty ? "在网页后台上传 TXT 或 EPUB 后，下拉刷新即可。" : "试试其他书名或作者。"))
                            }
                        }.listRowBackground(YYTheme.background)
                    }
                    ForEach(cloud.books) { book in cloudRow(book).listRowBackground(YYTheme.background) }
                    if cloud.hasMore {
                        HStack {
                            Spacer()
                            if cloud.loading { ProgressView() }
                            else { Button("加载更多") { Task { await cloud.nextPage() } }.accessibilityIdentifier("cloud.nextPage") }
                            Spacer()
                        }.listRowBackground(YYTheme.background)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .refreshable { await cloud.refresh() }.accessibilityIdentifier("cloud.books")
            }
        }.background(YYTheme.background)
            .task(id: searchKey) {
                do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
                await cloud.refresh()
            }
            .sheet(isPresented: $showConnection) {
                NavigationStack { CloudConnectionView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showConnection = false } } } }
            }
            .confirmationDialog("更新这本书？", isPresented: Binding(get: { updateBook != nil }, set: { if !$0 { updateBook = nil } }), presenting: updateBook) { book in
                Button("确认更新") { cloud.download(book, library: library, allowsUpdate: true); updateBook = nil }
                Button("取消", role: .cancel) { updateBook = nil }
            } message: { _ in Text("校验完成后更新本地内容，并尽量恢复原章节和文字位置。请先关闭本书的阅读页面。") }
    }

    private var filters: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(YYTheme.secondary)
                TextField("搜索书名或作者", text: $cloud.query).submitLabel(.search).autocorrectionDisabled()
                    .accessibilityIdentifier("cloud.search")
                if !cloud.query.isEmpty { Button { cloud.query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清空云书库搜索") }
                Menu {
                    Picker("排序", selection: $cloud.sort) { ForEach(CloudSort.allCases) { Text($0.title).tag($0) } }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 32, height: 32) }.accessibilityLabel("云书库排序")
                Button { showConnection = true } label: { Image(systemName: "key.horizontal").frame(width: 32, height: 32) }.accessibilityLabel("云书库连接")
            }.padding(.horizontal, 12).padding(.vertical, 6).background(YYTheme.separator.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            Picker("小说格式", selection: $cloud.format) { Text("全部").tag(""); Text("TXT").tag("txt"); Text("EPUB").tag("epub") }
                .pickerStyle(.segmented).accessibilityIdentifier("cloud.format")
        }.padding(.horizontal, YYTheme.screenInset).padding(.vertical, 12)
    }

    private func cloudRow(_ book: CloudBook) -> some View {
        let local = library.localBook(cloudID: book.id)
        let state = cloud.downloads[book.id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { cloud.open(book, library: library) } label: {
                    HStack(spacing: 14) {
                        CloudCoverView(book: book)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(book.title).font(YYTheme.title(18)).foregroundStyle(YYTheme.foreground).lineLimit(2)
                            Text(book.author.isEmpty ? "未知作者" : book.author).font(.caption).foregroundStyle(YYTheme.secondary).lineLimit(1)
                            Text("\(book.format.rawValue.uppercased()) · \(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))")
                                .font(.caption2).foregroundStyle(YYTheme.secondary)
                            if local != nil { Label("已下载，可离线阅读", systemImage: "checkmark.circle").font(.caption2).foregroundStyle(YYTheme.accent) }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("cloud.open.\(book.id.uuidString)")
                if state?.busy == true {
                    Button("取消") { cloud.cancel(book.id) }.font(.caption).accessibilityIdentifier("cloud.cancel.\(book.id.uuidString)")
                } else if cloud.needsUpdate(book, library: library) {
                    Button("可更新") { updateBook = book }.font(.caption).accessibilityIdentifier("cloud.update.\(book.id.uuidString)")
                } else if local == nil {
                    Button { cloud.download(book, library: library) } label: { Label(state == nil ? "下载" : "重试", systemImage: "arrow.down.circle") }
                        .font(.caption).accessibilityIdentifier("cloud.download.\(book.id.uuidString)")
                }
            }
            if let state {
                switch state {
                case .downloading(let done, let total):
                    ProgressView(value: Double(done), total: Double(max(1, total))) {
                        Text("下载中 \(Int(Double(done) / Double(max(1, total)) * 100))%").font(.caption2)
                    }.accessibilityIdentifier("cloud.progress.\(book.id.uuidString)")
                case .importing: HStack { ProgressView(); Text("正在加入本机书架…").font(.caption) }
                case .cancelled: Text("已取消，可重试继续下载").font(.caption2).foregroundStyle(YYTheme.secondary)
                case .failed(let message): Text(message).font(.caption2).foregroundStyle(YYTheme.secondary)
                }
            }
        }.padding(.vertical, 10)
    }
}

private struct CloudCoverView: View {
    let book: CloudBook
    @EnvironmentObject private var cloud: CloudLibraryStore
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(YYTheme.selection)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "book.closed").font(.title2).foregroundStyle(YYTheme.accent.opacity(0.65)) }
        }.frame(width: 54, height: 78).clipShape(RoundedRectangle(cornerRadius: 5)).accessibilityHidden(true)
            .task(id: "\(book.id)-\(book.revision)") { image = await cloud.cover(book) }
    }
}

struct CloudConnectionView: View {
    @EnvironmentObject private var cloud: CloudLibraryStore
    @State private var token = ""
    @State private var connectedMessage = false
    @State private var confirmRemoval = false
    var body: some View {
        Form {
            Section {
                LabeledContent("服务地址", value: "1.113188.xyz")
                Label(cloud.connected ? "已连接" : "尚未连接", systemImage: cloud.connected ? "checkmark.shield" : "key.horizontal")
                    .accessibilityIdentifier("cloud.connectionStatus")
                Link("打开云书库后台", destination: CloudAPIClient.origin)
            }
            Section {
                SecureField("粘贴只读设备令牌", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().accessibilityIdentifier("cloud.token")
                Button(cloud.connecting ? "正在验证…" : "验证并连接") {
                    Task { if await cloud.connect(token) { token = ""; connectedMessage = true } }
                }.disabled(token.isEmpty || cloud.connecting).accessibilityIdentifier("cloud.saveToken")
                if cloud.connecting { ProgressView() }
                if connectedMessage { Text("连接成功，在“发现 → 云书库”浏览小说。").foregroundStyle(YYTheme.accent) }
                if let message = cloud.message { Text(message).font(.footnote).foregroundStyle(YYTheme.secondary) }
            } header: { Text(cloud.connected ? "重新连接" : "连接我的书库") } footer: {
                Text("在网页后台的设备管理中创建只读令牌，并粘贴到这里。令牌安全保存在本机钥匙串，可随时在后台撤销。下载后的书籍无需联网即可阅读。")
            }
            if cloud.connected {
                Section {
                    Button("删除连接凭据", role: .destructive) { confirmRemoval = true }.accessibilityIdentifier("cloud.removeToken")
                } footer: { Text("删除凭据后，已下载的本地小说、书签和阅读位置仍会保留。") }
            }
        }.navigationTitle("云书库连接").navigationBarTitleDisplayMode(.inline).yyPage()
            .onDisappear { token = "" }
            .confirmationDialog("删除此设备上的云书库凭据？", isPresented: $confirmRemoval) {
                Button("删除凭据", role: .destructive) { token = ""; cloud.disconnect(); connectedMessage = false }
                Button("取消", role: .cancel) {}
            }
    }
}
