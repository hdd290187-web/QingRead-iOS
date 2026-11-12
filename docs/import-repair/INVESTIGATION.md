# Build 9 本地导入定点排障

基线：609799399e19e5aa6f7c344e7895cb852cee9bd5；App 与 Build 9 的 a11e90b 完全相同。开始时 git status 干净，安全标签 pre-import-repair-build9-20261112。未连接用户 iPhone，也没有用户此次失败的 NSError/Console 记录，因此不能确定它实际落在文件授权、提供器可用性或解析的哪一阶段。

## 可由源码直接确认的缺口

1. RootView 的 fileImporter 回调只处理 success；failure 和空 URL 列表会静默结束，没有取消/失败的区分。
2. LibraryStore 从外部 Files URL 直接调用 Task.detached 解析 TXT，或直接 copyItem EPUB；没有先用 NSFileCoordinator 取得稳定本机副本，没有 iCloud 就绪处理。安全作用域虽然用 defer 保持，但无法把提供器 URL 当普通测试临时文件使用。
3. 新书先插入 @Published books，再调用会吞错误的 persist。即使磁盘写失败，importFile 仍可能返回 Book，无法证明持久化成功。
4. 仅按 originURL 判断重复；同内容从另一个提供器或另一临时 URL 再次导入会生成新记录。
5. 原单元测试只从进程可直接访问的 temporaryDirectory 导入；原 UI 测试直接 seed 书籍，没有打开系统文件选择器。

这些缺口确定造成“可能静默/误报成功”和提供器导入不可靠。修复前没有依据宣称某个特定 NSError 就是用户真机的根因。

## 修改后的完整链路

按钮禁用重入 → UIKit 文档选择器（asCopy）提供器物化与 delegate 回调 → success/failure/取消/空结果 → 立即显示“正在导入…” → 串行导入队列 → 安全作用域开始 → 查询 iCloud 状态并必要时启动下载 → NSFileCoordinator 协调读取 → 在 scope 有效期间复制到 Application Support/QingRead/import-staging/随机ID/source.ext → 后续只解析私有副本 → TXT 分章/EPUB Readium 验证 → 文件内容身份去重 → 将文件目录 move 到 books/随机ID → 原子写入完整 library.json → 成功后发布 books → 等选择器关闭后显示结果。

- startAccessingSecurityScopedResource 返回 false 时不直接否定：App Documents/temporaryDirectory 本就不需要 scope。后续资源查询/协调/复制以实际 NSError 判断授权和可用性。
- 所有错误记录真实阶段、主域/代码、底层 NSError 域/代码链、扩展名/大小和短哈希标识。DEBUG OSLog 不输出正文、文件名、完整路径或凭据；Release 不输出这些诊断日志。
- 结果面板和书架上的“查看结果”都保留反馈。失败可复制中文原因、建议、错误码和诊断编号，避免 document picker 关闭动画吞掉提示。
- 每本独立事务：部分失败不回滚已成功项。写入索引失败时保留原索引，清理仅本次暂存/新目录，不删除源文件或已有书籍。
- TXT 以解码并规范换行后的 UTF-8 文本 SHA256 去重，EPUB 以私有副本原始 SHA256 去重。新本地记录不保存外部 originURL。
- 旧记录在私有文件可读时计算同样身份，保留 ID、章节 ID、位置和书签；首次迁移写入之前保留 library-before-import-repair.json。旧文件不可读时保留记录，不猜测删除或合并。损坏的 library.json 阻止覆盖。

## 自动化与人工边界

新单元/集成测试覆盖真实 NSFileCoordinator+copyItem 的 App 内文件、复制后外部 URL 消失、内容哈希重复、旧索引迁移备份、并发队列、部分成功批量、权限/NSFileProvider 底层错误、云下载超时边界、空/不支持/二进制/过大文件以及写满磁盘的事务回滚。提供器和云超时用受控注入，不能据此称 iCloud 真正已验证。

新 XCUITest 通过系统 Files 选择器选择 App Documents 里的原创 TXT/EPUB，检查真实复制/解析/书架、失败反馈、重复、取消后重新打开和重启读取。测试只在 DEBUG 创建文件；Release 不带测试入口。

iCloud 未下载文件、第三方 File Provider、用户 iPhone 本次原文件和签名升级保留数据，仍需要真机验收。最终构建号、测试结果和日志在本次交付报告中记录，不能用 Build 9 的 24 项结果冒充修复验证。

## 系统 Files 测试的实际发现

Run 43255297538 的首次测试有一个错误前提：App 自有 URL 的 startAccessing 在该模拟器返回 true，测试原先要求 false。已改为显式模拟 begin 返回 false，但后续仍走真实 NSFileCoordinator 与真实复制；其余 12 项新增测试当时通过。该次 UI 控件树显示 Files 停在 Documents 的父目录，已补进入测试目录的真实点击。

Run 43256941444 的 32 项单元/集成测试全部通过。两项系统选择器测试中，点“打开”后仍能在控件树看到 Files 的 Open 按钮和已选中文件，App 仍为空书架；取消再重开后的导入测试则通过。这是选择器交接阶段的复现证据，不是解析/存储失败证据，也不能据此声称与用户真机底层错误相同。入口因此改为 UIKit UIDocumentPickerViewController(forOpeningContentTypes:asCopy:true)，使用持有明确的 coordinator/delegate 交付一次结果，先让提供器物化本机副本，再经 NSFileCoordinator 复制到私有暂存并解析。界面导航与按钮保持原样。
