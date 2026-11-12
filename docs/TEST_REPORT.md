# Build 9 历史构建与测试报告

当前导入修复交付为 Build 24，请阅读 [本次报告](import-repair/BUILD24_REPORT.md)：42 通过、0 失败、3 个系统 Files 诊断跳过/HUMAN_PENDING。下面 24 项全通过仅是历史结果，不代表真实文件选择器已验证。

日期：2026-11-12 UTC。App：阅简 QingRead 1.0.0，构建号 9，最低 iOS 17.0。

## 已通过的构建

- 源码提交：`a11e90b5a7e1c9b34feb797bccd0fabd0e5ed27e`
- GitHub 私有仓库：<https://github.com/hdd290187-web/QingRead-iOS>
- 成功运行：<https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43212305708>
- 云端环境：macos-15，实际 macOS 15.8.2；Xcode 26.3 (17C529)，Swift 6.2.4；iPhoneOS SDK 26.2。
- Device Release：`generic/platform=iOS` + `-sdk iphoneos` + `ARCHS=arm64`，`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO`。日志包含 `** BUILD SUCCEEDED **`。
- 测试环境：iPhone 16 Pro、arm64、iOS 18.5 Simulator。日志包含 `** TEST SUCCEEDED **`。
- XCTest 19 项 + XCUITest 5 项，共 24 项通过，0 失败、0 跳过。通过数量由 xcresulttool 导出的 test-summary.json 核对。
- IPA：`releases/QingRead-1.0.0-build9-run43212305708.ipa`（约 22 MB）。最新副本：`releases/latest/QingRead.ipa`。
- IPA SHA256：`23a09654ba48923c845a7903d074c2b7c3837a8fb410506e84d8e5fadf019bbc`。

VPS 上验证 ZIP 完整性、SHA256、Info.plist、arm64 Mach-O CPU 类型、无 LC_CODE_SIGNATURE、无 _CodeSignature/描述文件、字体 SHA256 与 14 份许可资源。生成的 Xcode 工程也已从这次成功 artifact 取回。Linux 未执行 Xcode 编译或冒称 iPhone 真机运行。

## 自动验证范围

| 测试组 | 数量 | 实际内容 |
|---|---:|---|
| CoreTests | 6 | UTF-8/UTF-16/GB18030 中文、章节切分字符完全保留、无章节/空书/大文本分块、CoreText 页范围无空洞和重叠、字号变化后字符锚点、位置编码、中文字体与 TextKit 字符映射 |
| EPUBTests | 2 | 原创 EPUB 3 元数据、两章真实目录、图片资源存在、locator 序列化与重启保存；损坏 EPUB 拒绝导入 |
| LibraryTests | 4 | TXT 导入与分文件内容、书架/设置/书签/进度重启恢复、重复导入不丢进度、缓存正文重启离线读取、空文件不加入书架、64 MB 超限提前拒绝 |
| OnlineFlowTests | 1 | 通过 URLSession stub 完成关键字搜索、相对 URL、目录、正文、缓存与重启离线读取，确认缓存读取不新增网络请求 |
| SourceTests | 6 | CSS 搜索、基础 JSONPath、备选规则/正则、目录去重、段落换行和脚本清理、异常 JSON/JS/XPath 禁用提示、robots 规则解析 |
| NavigationTests | 1 | 书架/找书/设置三个中文入口 |
| ReaderTests | 4 | TXT 滑动点击翻页、覆盖拖拽取消不换页并可继续翻页、UIKit 卷曲可翻页、滚动后目录选择显示第二章正文、书签操作与退出/终止/重启后内容位置恢复 |

测试 EPUB、在线 HTML/JSON、TXT 都为测试原创内容；没有提交有版权的整本小说。在线测试没有声称外部小说站点实测或永久可用。EPUB 自动测试检查图片资源和结构，复杂 EPUB 的实际视觉表现仍在真机清单中。

Linux 静态检查：plist 结构、字体 SHA256、依赖固定 revision 与许可文本、EPUB ZIP、shell 语法、git diff --check、跟踪文本中未发现密钥/证书/Token。可重复执行 `python3 scripts/validate-repository.py`。

## CI 修复记录

先修复 Swift 类型/Readium API 集成问题，再修复模拟器安装时缺失 CFBundleExecutable。UI 测试随后发现滚动章节切换期间旧表格回调覆盖新章位置，已加重建保护并验证实际第二章正文。最后使用 TextKit 字符映射替代滚动位置估算，并新增在线端到端夹具测试。成功运行 43211499799 为较早构建；本次交付使用最终代码运行 43212305708 的产物。

## 明确边界与 HUMAN_PENDING

- unsigned IPA 需要有效签名与设备授权，不能直接安装到普通 iPhone。签名/安装详见 INSTALL.md。
- 真实翻页跟手、长时间性能、亮度、刘海/灵动岛、横竖屏、系统文件分享注册、飞行模式外站缓存与复杂 EPUB 视觉验收，见 DEVICE_CHECKLIST.md，均未宣称真机完成。
- TXT 与在线文本支持滑动、覆盖、卷曲、连续滚动；EPUB 由 Readium 提供滑动/滚动，覆盖/卷曲会明确降级。
- Legado 为 CSS/JSONPath/正则子集，未实现 JS/XPath/登录/POST/动态签名/网页分页；不兼容规则禁用，不宣称 100% 兼容。
- TXT 单文件最大 64 MB；超长章节分为 24,000 UTF-16 字符左右的续段。导入会解码文本一次；阅读只布局当前与相邻章节，不为整书生成页面。
- 系统圆体的中文字形可由 iOS 字体回退；独立中文宋体通过随包 Noto Serif SC 提供。

## 原项目只读核验

`/opt/projects/ScreenTranslator-iOS` 及其仓库未修改，git status 干净；两项原流程文件的前后 SHA256 一致：

- `.github/workflows/build-ios.yml`：`578806bf217a15b17c9f0fc5d7af86af5df3627a0c4c7d27e31d499fd673d5f2`
- `scripts/fetch-ipa.sh`：`afefe48d5cd004854b8077d423c7b2cb98ba733803df2f2bbb5e23c85883d520`
