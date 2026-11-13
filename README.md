# 予盈 · QingRead

予盈是个人使用的原生中文 iPhone 小说阅读器。赠予盈盈的阅读时光。App 的三个入口为 **书架、发现、我的**；书籍、进度、书签、排版设置和已缓存正文保存在本机。

当前源码已按最新说明完成可编辑 SVG 图标及原生页面。候选 Build 32 被 GitHub Actions 的账户计费/支出上限阻止，任务尚未开始；新矢量图标还没有编入 IPA。已实际通过 macOS 构建与回归的是 **Build 31（先前提供的 PNG 图标）**：主回归 52 通过、0 失败、3 项 Files 诊断跳过，iPhone 15 品牌回归另 5 项通过。详见 [交付状态](docs/yuying/DELIVERY.md)。

## 界面与能力

- 按最新说明绘制独立的矢量图标，保留可编辑 SVG 源稿，导出 1024×1024 无 alpha 的 RGB PNG，由 iOS 提供图标遮罩。统一墨黑、香槟米、暖白主题，宋体标题，原生启动屏，没有人为延时。
- 默认双列书架，EPUB 原封面优先；无封面的 TXT 使用本地稳定生成的自然图案，内存/磁盘缩略图缓存有上限。搜索、排序、列表切换、长按删除和已读进度保留。
- 文件 App 和系统文档入口导入 UTF-8、UTF-16、GB18030/GBK TXT 与 EPUB，保留协调复制、事务存储、内容去重和可复制的失败诊断。
- TXT 以 CoreText 实际字符范围分页，支持左右点击、滑动、覆盖、仿真卷曲和连续滚动；按章保存并预加载相邻章节。工具栏显隐不改变正文容器尺寸。
- EPUB 使用 Readium Swift Toolkit 3.11.1，保留目录、图片、分页、滚动和 locator 进度；覆盖/卷曲模式继续使用滑动替代。
- 阅读设置提供字体、字号、行距、背景和互斥的翻页选择，页面内即时预览；段距、边距、缩进、字重、亮度和点击区等高级选项完整保留。
- 发现页沿用在线书源能力：简单 JSON/CSS/基础 JSONPath/正则，搜索、目录、逐章正文及磁盘缓存。JavaScript、XPath、登录、动态签名和网页分页规则仍明确标注不兼容。

## 数据与升级

Bundle ID 固定为 `com.hdd290187.qingread`；内部工程名 QingRead、Application Support/QingRead、书籍和章节 ID、library.json 结构及原有设置键保持兼容。新主题不覆盖已有用户的字体、排版或翻页偏好。封面仅写 Caches，不修改书籍。

**使用原有签名方式覆盖 Build 24，不要先卸载，不要更换 Bundle ID 或选择清除数据。** IPA 未签名，仍需有效签名及设备授权。详见 [安装说明](docs/INSTALL.md) 与 [本次真机复测](docs/yuying/DEVICE_RETEST.md)。

## 构建与验证

Linux 只负责代码、资源检查和 GitHub Actions 触发，本机没有 Xcode。Actions 固定 macos-15 / Xcode 26.3 / XcodeGen 2.46.0；先构建 `generic/platform=iOS` 的 unsigned arm64 Release，再执行模拟器 XCTest，并在小屏 iPhone 与 iPhone 15 上检查品牌页面。

```bash
python3 scripts/validate-repository.py
# 以下需要 Mac / Xcode
xcodegen generate
xcodebuild -resolvePackageDependencies -project QingRead.xcodeproj -scheme QingRead
```

工作流保存编译日志、环境、xcresult、截图、生成工程、IPA 和 SHA256。标准测试保留三项明确跳过的原生 Files 诊断；五项从选择回调边界开始的导入 UI 回归独立运行，不混淆系统提供器验收。可手动以 `import_only=true` 运行真实 Files 诊断，该模式不打包 IPA。

- [予盈改造与兼容约束](docs/yuying/IMPLEMENTATION.md)
- [予盈素材来源（随 App 分发）](QingRead/Resources/Notices/yuying-assets.txt)
- [Build 24 历史导入调查与证据](docs/import-repair/BUILD24_REPORT.md)
- [Build 9 历史测试报告](docs/TEST_REPORT.md)
- [书源兼容范围](docs/SOURCE_COMPATIBILITY.md)
- [许可证与参考审计](docs/REFERENCE_AUDIT.md)
