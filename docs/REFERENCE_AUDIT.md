# 参考审计与路线选择

审计日期：2026-11-12。只读参考仓库位于项目外 `/opt/projects/references/`，未作为 Git 子模块或 App 源码提交。固定 SHA 见 `reference-lock.json`。逐项阅读 README、许可证或许可证缺失状态、下列实际源码；没有根据 README 的宣称推断真机效果。

| 仓库 / 固定 commit | 功能与实际架构 | 质量判断 / 复用方式 | 许可证 | 风险与决定 |
|---|---|---|---|---|
| lllyys/vreader `b996ab4d828a180ae4b23d0b07d045b3d318c34f` | SwiftUI、SwiftData；TXT TextKit + chunk；Readium EPUB；在线规则、AI、PDF、备份等模块 | 阅读了 TXTChapterIndexStore、VReaderLocator、ReaderTapZoneRouter、LegadoCompatibility 与架构说明；测试覆盖面大，但服务与格式种类很多。参考章节缓存、位置封装、避免上层手势吞事件的思路 | README 宣称 MIT，但此固定快照未发现项目级 LICENSE 文件（仅字体许可）；不直接复制代码 | 精简成本高，存在功能耦合和许可证文本缺失。未采用其整仓或源码 |
| KevinLeeeee323/SwiftBookApp `bb0840032091bea10ef146cd079876da064ea976` | SwiftUI + WKWebView；手动 ZIP/OPF 解析、EPUB CSS columns、目录和设置 | 阅读 ReaderView、ZipReader、EPUBParser、ReadingSettings、BookManager；结构轻量，README 明确 MVP 和环境；手写 ZIP/正则 XML 对 EPUB 边缘情况风险高。采用轻量原生 UI 的架构路线，自写统一模型和 TXT 核心 | MIT，KevinLeeeee323 2026 | 不复制其解析器、HTML/JS、字体文件、音量键私有行为；EPUB 用 Readium 代替手写解析 |
| kmworks/kmreader `6223c9b774e97dfc8d415d2eddf887a9f20bfee0` | 多平台 Komga 客户端；ReaderSession、EPUB WebPub、离线及多种手势/分页模块 | 阅读 EpubReaderViewModel、EpubReaderView、WebPubPaginationLayout、ReaderPositionAnchor；模块成熟但服务端、漫画和多平台范围过大。参考页位与方向分离，不引入 Komga | MIT，everpcpc 2025 | 没有引入项目代码或 Komga 网络依赖 |
| KeloYuan/open-reading `1827b8e5cd2581cafe7fd57addf722913bf3e20a` | Flutter/Dart + Rust，Foliate；渐进分页、后台 isolate 与页手势 | 阅读 EnhancedPaginator、分页缓存和 page_transitions；参考有限窗口、先准备邻页、字符锚点，不移植 Dart/Rust | README 宣称 MIT，但固定快照无项目级 LICENSE；附带第三方 JS 有单独许可 | 未复制任何跨平台文件。不同字体系统的估算分页不能直接作为 iOS 精确分页 |
| readium/swift-toolkit `3.11.1` / `9a8c094b72245fd27043c9d298005e5c78b32a01` | 稳定 Swift EPUB 引擎；Publication/Streamer、UIKit Navigator、CSS、图片、TOC、locator | 阅读 Package.swift、PublicationOpener、AssetRetriever、EPUBNavigatorViewController、EPUBPreferences、示例 EPUBViewController 和集成指南。使用精确 SPM 版本，不用 develop/4.0 alpha | BSD-3-Clause；传递依赖另列 NOTICE | 稳定版要求 iOS 15+、Xcode 16.4+，实际 CI Xcode 26.3 / iOS SDK 26.2，App iOS 17+。EPUB 卷曲/覆盖不由该引擎提供，明确降级滑动；DRM 未实现 |
| Mac-XK/KRead `8bacce2a7ccfe2c7e01208397216e5b4e6a228ee` | 当前公开树只有 README、规范和 JSON 示例，没有完整 Swift 工程 | 阅读 README、KRead 书源规范和标准 JSON 模板，作为字段和不兼容语法的说明参考 | 没有明确项目代码许可证 | 不复制代码、不内置其网站书源或版权文本，不把公开说明当作可复用完整 App |

唯一主工程是 `QingRead`：采用 SwiftBook 的轻量原生架构路线重新实现，未分叉或拼接参考仓库。统一 `Book / Chapter / ReadingPosition` 与 `ReadingEngine`，TXT/在线正文共用 CoreText + UIKit 引擎，EPUB 为同一菜单/持久化接口下的 Readium 格式适配器。

TXT 滑动和卷曲由 UIPageViewController 承担；覆盖为可取消的 UIKit child view pan；连续滚动使用受限相邻章节窗口，CoreText 生成实际可见范围，不按估算字数强拆。进度按 UTF-16 字符偏移保存，EPUB 保存 Readium locator JSON。未实现网站、后端、AI、付费、广告、账号或云同步。

只直接依赖 Readium 3.11.1 和 SwiftSoup 2.13.5。云端解析的传递版本锁进 `Package.resolved`；实际随包依赖的完整许可在 App 资源 `Resources/Notices` 中保留。没有引用参考仓库中的无授权模块。
