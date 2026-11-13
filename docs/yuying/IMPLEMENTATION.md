# 予盈：本次改造范围与兼容约束

基线：2026-11-13 检查本地 main 与 origin/main 均为 29ac5da，工作区原有源码干净。已创建本地备份分支 backup/before-yuying-20261113，并归档 releases/backups/QingRead-before-yuying-29ac5da.tar.gz。用户在本次上传说明中确认 Build 24 的 TXT 导入已在真实 iPhone 正常使用；此前的 CI 原生 Files 限制仍保留其独立记录。

实施文件与影响：

| 文件/区域 | 改动与需要回归的影响 |
| --- | --- |
| Design/Theme.swift、品牌资产、LaunchScreen.storyboard、Info.plist | 统一色彩、宋体标题、原生导航和系统静态启动屏；桌面名称改为予盈。图标原始 PNG 必须逐字节匹配用户提供版本。 |
| Views/RootView.swift、BookCoverView.swift、Services/BookCoverCache.swift | 默认双列、真实 EPUB 封面、稳定本地自然风格封面、搜索及排序菜单；复用同一个 DocumentImportController 与 BookDocumentPicker，保留所有反馈入口。 |
| Views/ReaderView.swift、SettingsView.swift、Services/Paginator.swift | 工具栏和纸张排版，标题通过 attributed string 设置样式而不插入或删除字符；设置即时传递到现有阅读引擎，保持 UTF-16 位置语义。 |
| Models/BookModels.swift | 调整纸张色及新安装默认值，新增浅灰主题；不删除或改名旧枚举值，不更改 Book / Snapshot 字段和持久化键。 |
| Views/DiscoverView.swift | 显示名称及配色调整，在线功能沿用原实现。 |
| Tests / UITests / Actions | 保留导入及四种翻页回归，增加品牌、封面、排版与升级兼容验证，保存截图并检查小屏幕及 iPhone 15 系列。 |

保持 Bundle ID com.hdd290187.qingread、Application Support/QingRead、书籍/章节 ID、原始文件、library.json 结构、进度、书签和设置键不变。封面仅写可清理的 Caches 目录，不触碰书库。无用户小说上传，无外部图片依赖。

导入修复的 BookDocumentPicker、DocumentImportController、DocumentStager、ImportFeedbackView、LibraryStore、LocalBookImporter、ImportDiagnostics 不作逻辑重构（仅将两处错误建议中的旧品牌替换为予盈）。NativeReader 的滑动/覆盖/卷曲/连续滚动控制器保持现有翻页实现。

验证结果与产物信息在本次构建完成后补充；本文件不是通过报告。
