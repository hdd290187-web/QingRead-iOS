# 阅简 QingRead

阅简是个人使用的原生中文 iPhone 小说阅读器。界面只保留书架、找书、设置三处入口；书籍、进度、书签、排版设置和已缓存正文保存在本机。

## 能力

- 文件 App 和系统分享入口导入 UTF-8、UTF-16、GB18030/GBK TXT 与 EPUB。
- TXT 以 CoreText 实际可见字符范围分页，支持左右点击、轻扫、滑动、覆盖、仿真卷曲和连续滚动；章节分文件保存，并预加载相邻章节。
- EPUB 使用 Readium Swift Toolkit 3.11.1，在 UIKit `EPUBNavigatorViewController` 中处理目录、图片、分页、滚动和 locator 进度。复杂模式在 EPUB 中降级为滑动，界面会提示。
- 书源导入支持简单 JSON/CSS/基础 JSONPath/正则；搜索、目录、逐章正文和磁盘缓存均可用。JavaScript、XPath、登录、动态签名和网页分页规则会在导入时标注为不兼容，不宣称完整 Legado 兼容。
- 本地书架搜索、书签、阅读进度、主题、字体、字号、行距、段距、缩进、边距和屏幕亮度设置持久化。

## 构建

Linux 只负责代码、静态检查和 GitHub Actions 触发；本机没有 Xcode。GitHub Actions 在 `macos-15` 的 `/Applications/Xcode_26.3.app` 上通过 XcodeGen 生成工程，先运行 Simulator XCTest，再运行 `generic/platform=iOS` 的 Release device build，签名关闭后打包 unsigned arm64 IPA。工作流会上传环境信息、真实编译日志、测试 xcresult、IPA 和 SHA256。

```bash
brew install xcodegen
xcodegen generate
xcodebuild -resolvePackageDependencies -project QingRead.xcodeproj -scheme QingRead
```

未签名 IPA 不能直接安装到普通 iPhone，需要有效的 Apple 开发者签名和描述文件。真机上的翻页跟手、屏幕亮度和不同尺寸安全区域仍需人工验收。
