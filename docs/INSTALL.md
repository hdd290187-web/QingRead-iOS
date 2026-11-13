# 予盈：构建、下载和覆盖安装

最新版本与校验值见 [本次交付报告](yuying/DELIVERY.md)。内部工程仍名为 QingRead；最低 iOS 17.0，支持 iPhone 竖屏/横屏，无需 VPS 服务、云账号或服务器 API。

## 从 Build 24 升级

本包是 **未签名的 iOS arm64 IPA**。使用你安装 Build 24 时的有效签名身份、Team、描述文件和工具覆盖安装，应用标识继续保持 `com.hdd290187.qingread`。不要先卸载旧 App，不要启用清除数据，不要让重签工具改成新的随机 Bundle ID。签名身份或应用标识变化会影响系统是否允许覆盖，不能通过卸载来解决并同时声称保留数据。

解压交付 ZIP，取出 QingRead.ipa，按原有流程签名并安装。桌面名称改为“予盈”，书库、书签、阅读进度和自定义设置沿用。IPA 没有 Apple 签名，不能不经签名直接安装。

如使用 Mac / Xcode，打开 QingRead.xcodeproj 选择 QingRead scheme，使用原有 Team 和 Bundle ID 启用有效签名；不要为了运行而更改现有应用标识。个人签名的有效期及设备授权依所用工具和 Apple 实际规则处理。项目不提供证书私钥或账号材料。

## 导入和阅读

书架右上角 `+` → 系统文件 → 选择 TXT / EPUB → 打开 → 查看导入结果。文件 App 的“用予盈打开/分享”入口依赖签名后系统文件类型注册。发现页沿用在线搜索；“我的 → 书源管理”可导入 JSON 文件、粘贴 JSON 或使用 HTTPS URL。

阅读页中央轻触显示/隐藏工具栏，顶部 Aa 或底部“排版”进入阅读设置。滑动、覆盖、卷曲、连续滚动互斥；EPUB 的覆盖与卷曲使用滑动替代。更多排版与亮度保留原有段距、边距、缩进、字重、单手点击和亮度控制。

未设置自定义亮度时沿用系统亮度；退出阅读后恢复进入阅读器之前的亮度。保留原始书籍备份；卸载 App 会删除本机数据。[升级后真机复测步骤](yuying/DEVICE_RETEST.md) 包含旧书位置、导入、四种翻页手感、安全区和真实壁纸效果。

## 重新构建与 VPS 拉取

推送 main 或执行 `gh workflow run build-ios.yml --repo hdd290187-web/QingRead-iOS`。工作流固定 macos-15 / Xcode 26.3 / XcodeGen 2.46.0 并验证生成器 SHA256；依赖按 Package.resolved 锁定 Readium 3.11.1 / SwiftSoup 2.13.5。

```bash
cd /opt/projects/QingRead-iOS
./scripts/fetch-ipa.sh <成功的 Actions run ID>
python3 scripts/verify-brand-ipa.py <成功的 Actions run ID>
```

下载脚本等待运行成功并验证 SHA256/ZIP，归档 releases/QingRead-版本-build编号-run编号.ipa，最新副本为 releases/latest/QingRead.ipa。完整日志、xcresult、截图、环境和生成工程保留在 releases/run编号/。macOS 本地可先运行 XcodeGen 2.46.0 的 `xcodegen generate` 再构建；不能以模拟器成功代替 iPhone device Release 编译。
