# 予盈 1.0.0 Build 43：实际交付

日期：2026-11-13 UTC。阅读沉浸布局与 TXT 连续滚动修改已编译为真实 unsigned arm64 IPA，完成三尺寸四模式的模拟器回归及同设备性能对照。仓库已实际 [Public](https://github.com/hdd290187-web/QingRead-iOS)。

- **安装包**：[GitHub Release](https://github.com/hdd290187-web/QingRead-iOS/releases/tag/v1.0.0-build43)；本地 `releases/QingRead-1.0.0-build43-run43425216709.ipa`。
- **实际构建**：[run 43425216709](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43425216709)，success，App 提交 `ee08a791ca570b09481c92d9a07314a6614f657c`。
- **版本**：1.0.0 / Build 43；Bundle ID `com.hdd290187.qingread`；最低 iOS 17.0；arm64；unsigned。
- **IPA SHA256**：`c27da8248b7f20920b84e4a38de83a7d7c0cce5647aad52320d61468241c722e`，23,437,264 bytes。
- **环境**：标准 macos-15；macOS 15.8.2、Xcode 26.3 / 17C529、SDK 26.2，未用付费 larger/self-hosted Runner。Actions 已实际运行，无当前计费阻塞。
- **主回归**：62 通过 / 0 失败 / 3 项既有 Files 跳过（65）；iPhone 15 10/0/0；iPhone 17 Pro Max 2/0/0；校准优化后/同设备基线各 3/0/0。设备重复用例不作为新增独立测试数。

完整运行 42 在主计划与 iPhone 15 成功后于大屏阶段触及 90 分钟上限，整轮 cancelled 且没有 IPA。收尾运行严格验证原始绿色阶段证据与发布代码等价，再在新 Runner 上构建 Build 43 和通过大屏测试；本次只交付这份实际新包。源码归档另记录交付文档提交，不混同 App 构建提交。

相同 iPhone 15、相同内容/字号，正文高度 609.67→731pt（+121.33pt），首屏排版行 16→21（含标题与空行）。TXT 读取/解码、字形预排版移到后台，固定高度原生列表保留惯性/回弹，进度节流并在停滚/后台/退出落盘。短篇/长篇内存增加，超长单章内存下降；全部数值和测量边界见 [阅读与性能报告](../reader-performance/REPORT.md)。

![前后同场景对照](../reader-performance/screenshots/before-after-iphone15.png)

交付附件包括 unsigned IPA ZIP、源码 tar.gz、主要汇总/测量 JSON、原始场景截图与索引、前后及大屏录屏、SHA256 清单。图标使用 [最新可编辑 SVG](../../design/yuying-vector/README.md)，PNG SHA256 `cc8858c7cf96d4355859ac6d2d88343f94a1135efda57c3e3027c633ddc62e8e`；保持字体/依赖/许可锁。原始私有审计和全系统模拟器诊断不进入包。

Bundle ID、书库目录、ID 与持久化格式保持；导入和存储 7 个关键文件与原基线逐字节一致。**使用原有有效签名身份、Team 和 Bundle ID 覆盖安装；不要卸载或清除旧书库。** unsigned IPA 仍需有效签名和设备授权。[公开审计](../security/PUBLICATION_AUDIT.md)已通过。

真实 iPhone 的滚动帧时间/触感/发热和同签名升级后的旧小说、进度、书签保留为 **HUMAN_PENDING**，不能由模拟器替代。见 [真机步骤](../reader-performance/DEVICE_VALIDATION.md)。
