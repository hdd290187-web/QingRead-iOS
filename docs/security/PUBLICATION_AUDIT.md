# 公开审计：通过，仓库已实际 Public

目标仓库 [hdd290187-web/QingRead-iOS](https://github.com/hdd290187-web/QingRead-iOS)。完整 Git 历史、可访问分支/tag、Actions 日志与产物、Release 附件及素材许可审查后，未发现真实项目/用户凭据或公开阻塞。用户于 2026-11-13 确认历史上传参考图“是我自己生成的”，声明已记录在 design/yuying-reference/README.md 与随 App 的素材说明。

审计通过后，已通过 GitHub 官方 API 将现有仓库改为 Public；认证与未登录官方 API 均核实 private=false / visibility=public。不是仅提交说明或将“可公开”当作已公开。此后标准 macos-15 Actions 已实际运行，Build 43 的 Release 与大屏测试成功，不存在当前计费锁定阻塞。

## 公开前的完整范围

- 全部可访问的 1 个远端分支、4 个 tag、0 个 PR，36 个历史提交；用 git cat-file 检查全部 569 个对象（含不可达）、292 个 blob，未只检查当前工作区。
- 下载和检查 32 次 Actions 的记录/可用日志、31 份未过期 artifact、1 个 Release 的 5 份附件；递归检查 ZIP、IPA、tar.gz 等共 31253 个归档成员。
- 官方 Gitleaks 8.30.1 经发行 SHA256 校验，扫描完整历史、全部 blob、日志及嵌套产物，开启 100% 遮蔽；辅以敏感扩展名、签名文件、网络引用、隐藏/大文件、长正文、图片 EXIF 和许可来源核对。

源码、历史、Actions 日志和 Release 附件未发现真实认证凭据。原 artifact 的 7 个候选均为 UIKit 视图控制器连接 UUID。未发现 p12、mobileprovision、签名私钥、私有地址或隐私 EXIF；测试正文为原创合成内容，没有发布用户书库。

## 公开后的增量复查

至 Build 43 的构建源码 `ee08a791ca570b09481c92d9a07314a6614f657c`，再次扫描全部 **50 个可达历史提交**与 **817 个对象 / 416 个 blob（含不可达）**，源码凭据命中 0。完整运行 33–42、校准 benchmark 和本次 Release 收尾的新增日志与产物均复核；最终 Release artifact 的凭据扫描为 0。最后同步工程和交付文档的提交在推送/归档前再做完整历史与对象扫描，最终源码提交与包哈希由交付 manifest 记录。

失败测试附带的全系统 Simulator 诊断出现 Apple shared-cache 中的静态 SQL/Keychain 字串、HomeUI 方法名、FontParser 内嵌测试材料，以及临时 archive/checksum key。已解析 DSC 映像范围核实系统路径，后续相同系统映像的文件 SHA256 完全一致；不是项目、GitHub、VPS 或 Telegram 凭据。候选值未打印或写入公开报告。原始全系统诊断不进入 Release 附件或 Telegram 包。

运行 42 的 GitHub logs API 返回空 ZIP；该可访问响应已检查，同时复核 artifact 中完整设备构建、主测试、iPhone 15、基线和大屏日志及原始汇总，不把空响应当作有额外未读内容。校准 benchmark 和本次完成包分别保留自己的运行来源。

## 许可、素材与工作流

App 独立源码为 MIT；Readium 及锁定依赖保留各自 LICENSE/NOTICE；Noto Serif SC 保留 SIL OFL、固定字体版本和哈希。没有引用许可不明的参考仓库源码。最新 SVG 图标和自然封面为本项目独立绘制；历史品牌参考图的用户来源声明与明确公开授权已记录，没有将其扩展成额外第三方保证。

保持标准托管 macos-15，未用 larger/self-hosted/第三方收费 Runner；Xcode 26.3 与依赖锁保持。工作流为 main push 或 workflow_dispatch，contents: read；收尾任务额外 actions: read，仅下载本仓库既有证据。checkout 关闭凭据持久化，不从不可信 PR 执行带写权限或秘密的工作流。

没有改写 Git 历史、强制推送、删除仓库或删除历史日志/附件。原始审计资料留在私有 VPS 目录；发布的源码、IPA ZIP、截图/报告和录屏在上传前再次扫描。机器可读范围见 audit-summary.json。
