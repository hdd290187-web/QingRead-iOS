# 构建、下载和安装

源码：私有仓库 `hdd290187-web/QingRead-iOS`。最低 iOS 17.0，支持 iPhone 竖屏/横屏；无需 VPS 服务、云账号或服务器 API。

## 重新构建

推送 main 或执行 `gh workflow run build-ios.yml --repo hdd290187-web/QingRead-iOS`。工作流固定 macos-15 / Xcode 26.3 / XcodeGen 2.46.0，并验证生成器 SHA256。Readium 3.11.1 / SwiftSoup 2.13.5 及传递依赖按 Package.resolved 锁定。

macOS 本地可运行 `xcodegen generate` 后打开 QingRead.xcodeproj，选择 QingRead scheme。需要重新生成时先安装 XcodeGen 2.46.0。测试目标是 XCTest 与 XCUITest；Release device build 必须为 `generic/platform=iOS`，不以 simulator 结果代替。

## VPS 拉取

在已登录 gh 的 VPS 上：

```bash
cd /opt/projects/QingRead-iOS
./scripts/fetch-ipa.sh <成功的 Actions run ID>
```

脚本等待该次运行成功，下载 artifact，验证 SHA256 和 ZIP 完整性，再保存为 releases/QingRead-版本-build编号-run编号.ipa；latest/QingRead.ipa 为最新副本。完整日志、测试结果、环境和生成工程保留在 releases/run编号/。重复运行不会覆盖不同内容的归档。

## HUMAN_PENDING：重签与安装

unsigned IPA 无法直接安装到普通 iPhone。这是尚未由 Apple 签名的 arm64 应用包。需要用户自己的有效 Apple 开发者账号/证书/描述文件和目标设备授权，或使用受信任的重签工具。

- 方式一：在 Mac 用 Xcode 打开生成工程，Signing & Capabilities 中选择自己的 Team、设置唯一 Bundle Identifier，并在 Build Settings 将 CODE_SIGNING_ALLOWED 改为 YES（或删去 project.yml 中的禁用签名项并重新生成工程），连接 iPhone 后 Run。按设备提示开启开发者模式并信任开发者。个人免费签名可能短期失效，按工具/Apple 实际限制处理。
- 方式二：使用 Sideloadly、AltStore 等你信任的工具，以自己的 Apple ID 为 QingRead.ipa 重签并安装。按该工具流程配对/刷新。不要把 Apple ID、Token、证书私钥提交到本仓库。
- 如使用证书签名：证书私钥与 profile 必须匹配、profile 包含设备 UDID、Bundle ID 和有效期；重签后验证包和所有嵌入组件。项目不提供或伪造签名材料。

导入：文件 App 选择 TXT/EPUB → 分享 → 阅简（或“用阅简打开”）；也可在书架点击加号。系统文档打开入口依赖重签后 iOS 对文件类型的注册，需真机验证。书源在设置 → 书源管理中导入 JSON 文件、粘贴 JSON 或 HTTPS URL。

未设置自定义亮度时保留系统亮度；退出阅读后恢复进入阅读器之前的亮度。应用卸载会删除本机数据，请保留书籍原文件。

## 已验证产物

1.0.0 / build 9，成功 run 43212305708，App 源码提交 a11e90b5a7e1c9b34feb797bccd0fabd0e5ed27e。

SHA256：23a09654ba48923c845a7903d074c2b7c3837a8fb410506e84d8e5fadf019bbc。完整测试报告见 TEST_REPORT.md。
