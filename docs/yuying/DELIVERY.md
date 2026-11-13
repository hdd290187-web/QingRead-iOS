# 当前交付状态

仓库已通过审计并实际 Public；最新针对性 macOS 回归为 [第 38 轮](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43398806434)，9 通过 / 0 失败 / 0 跳过。阅读沉浸布局、连续滚动的后台准备与绘制、精确字符恢复及 EPUB 回归已实现并通过该计划。

接下来执行完整 arm64 Release、65 项主计划、iPhone 15 的 10 项场景、同设备三样本基线对照及大屏 2 项布局；完整结果与新 IPA 尚未生成。

- [阅读优化、根因和实际验证边界](../reader-performance/REPORT.md)
- [公开前安全审计](../security/PUBLICATION_AUDIT.md)
- [真机待验证范围](../reader-performance/DEVICE_VALIDATION.md)
- [最新矢量图标源稿](../../design/yuying-vector/README.md)
- [已验证 Build 31 历史报告](history/BUILD31_REPORT.md)

可用旧包仍为 Build 31，它不包含本次阅读优化或后续矢量图标。所有覆盖安装继续保持原签名、Team 和 Bundle ID=com.hdd290187.qingread，不要卸载或清除旧数据。
