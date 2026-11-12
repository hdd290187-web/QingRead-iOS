# 阅简 1.0.0 Build 24：导入故障修复与交付

日期：2026-11-12 UTC。软件导入链路已修复并生成新包，用户真机原故障仍需复测；不宣称真机已修复。

## 产物与实际构建

- App/CI 提交：522029c45ddda10f5e0b5e2e4f3a342a0a39c00a。
- 成功 run：43275314601，https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43275314601。
- 版本：1.0.0；Build：24（旧包为 Build 9）；Bundle ID 保持 com.hdd290187.qingread。
- macos-15 runner，实际 macOS 15.8.2，Xcode 26.3 / 17C529，iPhoneOS SDK 26.2。
- generic/platform=iOS，Release，ARCHS=arm64，CODE_SIGNING_ALLOWED=NO，日志明确 BUILD SUCCEEDED。
- 本地 IPA：/opt/projects/QingRead-iOS/releases/QingRead-1.0.0-build24-run43275314601.ipa。
- 最新副本：/opt/projects/QingRead-iOS/releases/latest/QingRead.ipa。
- IPA SHA256：6aed664b4dae148e410989598ea6a991e9166344c37de1c4666b216e8f0baedc。
- 大小：23,008,841 bytes；最低 iOS 17.0。
- ZIP、arm64 Mach-O、包内版本/SDK、无 LC_CODE_SIGNATURE、无签名目录或描述文件均已核验。Release 二进制中未找到 DEBUG 导入测试入口和 picker-selected 日志字符串。字体许可和原资源保留。
- 日志、xcresult、截图、环境、Package.resolved、生成工程和原始测试汇总：releases/run43275314601/。

## 根因证据与修改

Build 9 可确认的缺口是：fileImporter failure/空结果被忽略；外部提供器 URL 未先协调物化到私有目录就解析；保存索引失败被吞后仍可能返回成功；URL 去重不能识别不同来源的同内容文件。没有用户原故障的 NSError，因此不能把任何特定错误码认定为其真机唯一根因。

多次系统 Files 模拟器诊断还捕获到 NSFileProviderErrorDomain/-1005（文件不存在），DocumentManager 记录 did Pick URLs []，发生于 App 获得有效文件前。关键无隐私路径证据见 provider-handoff-evidence.log；完整排查与失败 run 记录见 INVESTIGATION.md。一次实际系统导入、重启读正文和重复导入曾成功，但后续不稳定，故未作为完整验收通过。

主要改动：

- Views/RootView.swift、Views/BookDocumentPicker.swift：保留加号/导入按钮，使用明确 UIKit 文档选择器 delegate 和 asCopy，让提供器先提供本机副本；所有结果经同一控制器处理。
- Services/DocumentImportController.swift、Views/ImportFeedbackView.swift：立即显示导入状态，选择器关闭后显示完整结果；书架保留“查看结果”；成功/重复/部分成功/失败/取消区分，失败可复制中文阶段、原因、主错误码、底层错误码和建议。
- Services/DocumentStager.swift：安全作用域有效期内，必要时等待 iCloud 下载，NSFileCoordinator 协调并复制到私有暂存；startAccessing 返回 false 时继续按实际可读性处理，不一律拒绝或忽略错误。只从内部副本解析。
- Services/LocalBookImporter.swift：保留 UTF-8、UTF-16、GB18030/GBK 分章，分阶段呈现解码/解析/写入错误，拒绝空文件、二进制伪 TXT 和过大文件。
- Services/LibraryStore.swift、Models/BookModels.swift：串行队列、每本事务、成功保存索引后才发布书架；失败回滚新目录；TXT 规范文本/EPUB 文件哈希去重。新本地书不保存外部临时 originURL。
- 旧记录身份迁移前备份 library-before-import-repair.json；保留书籍/章节 ID、阅读位置和书签。损坏索引拒绝覆盖。原文件、已有书库不删除。
- Services/ImportDiagnostics.swift：DEBUG OSLog 记录阶段/扩展名/大小/权限状态/域与代码/短哈希；不记录正文、完整隐私路径、密钥；Release 不输出该日志。

翻页、ReaderView、ReaderSession、书源与设置代码未改动。ScreenTranslator-iOS 工作区干净，两项原脚本 SHA256 与基线一致。

## 自动测试：42 通过、0 失败、3 跳过

最终在 iPhone SE (3rd generation) / iOS 26.2 Simulator 执行，共 45 个测试计划项，xcresulttool 汇总：passedTests=42、failedTests=0、skippedTests=3。日志 TEST SUCCEEDED。**这不表示所有系统 Files 场景验收完成。**

| 实际执行的组 | 数量 | 覆盖 |
|---|---:|---|
| 原有单元/集成 | 19 | 编码、中文分章、大/空/过大文本、CoreText 边界与排版定位、持久化、离线缓存、EPUB 目录/图片资源/locator、在线规则与异常 |
| 新 ImportRepairTests | 13 | 真实协调复制；scope false 可读分支；复制后外部 URL 消失；改名/换路径内容去重；旧索引备份迁移保留 ID/位置/书签；批量部分成功；并发串行；提交失败磁盘错误 640 回滚；权限 257 与底层 Provider/-1005；取消/空回调；模拟云下载超时；二进制文本；EPUB 换路径重复 |
| 原有阅读与导航 UI | 5 | 中文导航、滑动、覆盖取消回弹、卷曲、滚动/目录、书签和重启位置 |
| 新 ImportFeedbackTests | 5 | 从选择回调边界输入后，真实复制/解析/书架刷新并重启可读；failure 显示阶段/257/建议/复制入口并重新查看；空结果建议；部分成功保留正确书；取消正常且实际打开/取消原生选择器 |

新增 UI 的成功输入是明确的 DEBUG 回调输入，后续存储和解析是真实实现。它不验证 FileProvider 交付回调之前的行为，不能当作用户真机导入成功的证明。

DocumentImportTests 的三项完整原生 Files 诊断保留源码与失败证据，在标准 CI 逐项 XCTSkip 标注 HUMAN_PENDING，未计入 42 个通过项。可显式重跑：

```bash
gh workflow run build-ios.yml --repo hdd290187-web/QingRead-iOS -f import_only=true
```

诊断模式只运行真实系统 Files 场景，不生成 IPA。标准模式才执行 device Release、所有必跑测试并打包。模拟器 iCloud 未登录错误不代表用户账号状态；iCloud/第三方 Provider 均未真机验证。

## HUMAN_PENDING：用户最少复测步骤

1. 用与旧包一致的 Bundle ID/签名方式覆盖安装 Build 24，保留 App 数据，不要先卸载。unsigned IPA 仍需用户有效签名/设备授权，不能直接安装。
2. 书架点加号，选择以前失败的 TXT → 打开。应能看到正在导入及成功书名，书架立即出现；点书能读，再选同文件应提示“已在书架，阅读进度已保留”。
3. 退出并重新启动 App 确认书架和正文仍在；如原文件来自 iCloud/第三方 Provider，再从原位置测试一次。若失败，点结果面板“复制错误信息”（或书架“查看结果”），发送失败阶段、错误域/代码、底层代码及诊断编号即可，无需发送小说正文或完整隐私路径。

用户原故障、真实系统提供器交接、同签名升级数据保留：HUMAN_PENDING。没有以全绿结果代替这些人工验证。
