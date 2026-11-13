# 予盈 1.0.0 Build 31：交付与验证

日期：2026-11-13 UTC。现有 QingRead App 完成“予盈”品牌与原生界面改造，保留 Build 24 的导入修复和阅读引擎。用户在本次上传说明中已确认 Build 24 TXT 导入在真实 iPhone 正常；本次新包的覆盖升级与真机手感仍需复测。

## 实际构建与安装包

- App / CI 构建提交：`8bb6d683702d35907f9826a0d3558d995fef101d`。
- 成功 Actions：[run 43355596782](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43355596782)。
- 版本：1.0.0；Build：31（大于 24）；桌面及 App 品牌：予盈。
- Bundle ID：`com.hdd290187.qingread`，保持不变；最低 iOS 17.0。
- macos-15 runner，实际 macOS 15.8.2，Xcode 26.3 / 17C529，iPhoneOS SDK 26.2。
- `generic/platform=iOS`、Release、arm64、禁用签名，日志 `BUILD SUCCEEDED`。
- IPA：`/opt/projects/QingRead-iOS/releases/QingRead-1.0.0-build31-run43355596782.ipa`。
- 最新副本：`/opt/projects/QingRead-iOS/releases/latest/QingRead.ipa`。
- 大小：23,981,086 bytes。
- SHA256：`5e6358f23ea8715eb5d2010c0797a4f9ad2ea4db6cb6cd55661ed5c5452289b6`。
- 完整日志、xcresult、两组原始截图、环境和生成工程：`releases/run43355596782/`。

实际 IPA 已检查 ZIP 完整性、arm64 Mach-O、版本与名称、Bundle ID、编译后 LaunchScreen、字体哈希及无签名状态。无 LC_CODE_SIGNATURE、签名目录或描述文件；Release 二进制不含 DEBUG 导入、品牌预览或测试书籍启动参数。`build-verification.json` 是下载后校验的机器可读结果。Linux 未运行 Xcode，实际编译和 XCTest 均在 GitHub macOS 完成。

交付源码归档包含 CI 实际生成的 Xcode 工程、文档、报告和关键截图；App 源码对应以上构建提交，后续交付提交仅同步这些生成工程与证据，不混称为另一轮编译。

## 视觉与交互

- **品牌与图标**：可见 UI 统一为“予盈”，副标题“赠予盈盈的阅读时光”。AppIcon 直接复制用户指定的 `app-icon-1024.png`，逐字节 SHA256 为 `47bb96e82f2988b1de39a11245aaa6bf6c7c0b867464e1942cebb6784842b7b0`；没有重新设计、裁剪或调色。桌面安装后的名称与图标另有模拟器截图。另已解码 IPA 内 Apple CgBI 120px/60pt 图标，与原图缩放结果比较，RGB 平均差异均小于 1/255（缩放算法差异），记录见 icon-verification.json。
- **统一主题与启动**：墨黑 #242424、香槟米 #E7D6C2、暖白 #F7F6F2；中文标题使用已许可的 Noto Serif SC，原生导航及控件保持清晰。系统静态 LaunchScreen 采用居中书本标志、品牌字样和浅纸页曲线，没有人为等待或品牌动画阻塞。
- **书架**：默认两列、轻微圆角、书名与已读进度；右上搜索和加号，简洁菜单保留排序及列表切换。EPUB 优先取包内封面，TXT/无封面书籍使用本地稳定生成的自然图案。缩略图为 400×588，内存上限 24 MB，磁盘缓存约束为 64 MB，不写书库或上传小说。
- **阅读**：暖色纸张、宋体章标题、协调的首行缩进和段落留白；顶部返回/Aa/书签/更多操作，页底章节及进度。工具栏显隐保持正文容器大小；TXT 标题及空白行只改样式，不改变 UTF-16 字符；EPUB 使用现有 Readium 的设置及边距接口，流式 XHTML 章标题应用真实样式，固定版式不注入标题样式。
- **设置与导航**：Tab 为书架/发现/我的；阅读设置分组展示字体、字号、行距、背景和互斥的四种模式，带真实文字预览。高级页边距、段距、缩进、字重、亮度、点击区和单手选项均保留。暖白/米黄/浅灰/护眼绿/深色与跟随系统可用，深色品牌标志有浅色底板以维持辨识度。

## 功能与数据保留

`BookDocumentPicker`、`DocumentImportController`、`DocumentStager`、`ImportFeedbackView`、`LibraryStore`、`LocalBookImporter` 保持 Build 24 实现；ImportDiagnostics 只替换两处建议中的旧品牌文字。原有 TXT UTF-8/UTF-16/GB18030/GBK、EPUB、在线书源、书签、目录、亮度、缓存和进度持久化继续保留。没有网站、后端、账号、广告、收费、社交或 AI 新功能。

保持 Application Support/QingRead、书籍与章节 ID、library.json 结构、书签/进度/设置键不变。既有用户偏好不被新安装默认值覆盖。封面只放可清理的 Caches。所有开源许可、NOTICE、固定依赖版本和字体许可随源码/App 保留；素材来源另见 `QingRead/Resources/Notices/yuying-assets.txt`。ScreenTranslator-iOS 未修改。

## 本次实际测试

| 验证组 | 设备与结果 | 覆盖 |
| --- | --- | --- |
| 单元/集成 | iPhone SE 3 / iOS 26.2，37/37 通过 | 编码/分章、CoreText、EPUB/locator、在线规则、事务导入和故障回滚、旧版快照保留 ID/进度/书签/设置、空行及标题字符完整、稳定封面/缓存、Readium 设置映射 |
| 主 UI 回归 | 同设备，15/15 通过 | 四种 TXT 阅读方式、取消拖动、目录/书签/重启；5 项选择回调后的真实复制/解析/入库/错误反馈；品牌/三 Tab/空状态/双列与列表/搜索、字体主题实时修改、EPUB 封面与字号重排、章标题实际尺寸、设置边界、深色及桌面图标 |
| 原生系统 Files 诊断 | 同设备，3 项跳过 | 保留既有 HUMAN_PENDING，不计入通过数量；历史 FileProvider 交接限制未被品牌改造掩盖 |
| iPhone 15 品牌 UI | iOS 26.2，5/5 通过 | 同一组品牌布局、字体主题、EPUB 及桌面测试在更大屏再次执行 |

主汇总：55 项，52 通过、0 失败、3 跳过；iPhone 15 另 5 项通过、0 失败、0 跳过。第二设备重复执行的 5 项不作为新增独立用例夸大数量。原始汇总为 `test-summary.json`、`brand-iphone15-summary.json`。

回调边界导入测试不冒充完整系统 FileProvider 验收；三项原生 Files 诊断可通过工作流 `import_only=true` 单独运行，该模式不打包 IPA。用户已确认的 Build 24 真机导入反馈与这些 CI 边界分开记录。

![iPhone 15 模拟器界面总览](screenshots/overview.png)

上图与单张原图均为此成功构建对应源码的 Simulator Debug UI 截图，不是真机照片。启动屏图片明确为 DEBUG 布局预览；实际 Release 使用编译后的静态 LaunchScreen，不含该预览入口或人为延时。关键原图见 `screenshots/`，两种设备的完整附件在 run 目录。

## 下载与覆盖安装

交付 ZIP：`releases/delivery/Yuying-1.0.0-build31-unsigned.zip`，内含 QingRead.ipa、校验值、覆盖说明、报告与关键截图。源码归档随交付提交命名另附。私有仓库构建页及 Telegram 交付均可获取产物；IPA 自身 SHA256 如上，ZIP 与源码各自校验值另随包保存。

**使用安装 Build 24 时的有效签名身份、Team 和 Bundle ID 覆盖安装，不要先卸载，不要清除数据或改随机 Bundle ID。** 本包未签名，不能未经有效签名直接安装。详细操作见 [覆盖说明](../INSTALL.md)。

## HUMAN_PENDING：新包真机体验

1. 同签名覆盖后核对旧书数量、旧位置、书签及自定义设置；桌面应为指定新图标和“予盈”。
2. 从之前成功的文件位置再导入 TXT/EPUB，查看结果、书架、正文和去重；iCloud/第三方提供器按实际位置复测。
3. 在常用 iPhone 依次检查滑动、覆盖、卷曲、连续滚动、短拖回弹、跨章、中央显隐工具栏，以及真实屏幕安全区、亮度恢复、壁纸图标效果与长时间阅读发热/跟手感。

这些新包真机项目尚未实测，不能用模拟器通过替代；具体步骤见 [真机复测](DEVICE_RETEST.md)。
