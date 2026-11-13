# 阅读布局与连续滚动：修改前证据

基线为 d75d7b6（Build 31 的已验证阅读源码，加上后续矢量图标资产）。本地工作区干净，已建立 backup/before-reader-performance-20261113 和源码归档。Bundle ID、数据路径与存储格式保持不变。

源码中可直接确认的执行路径：

1. ReaderHost 的 VStack 始终包含 52pt header、8pt 正文上边距和约 88pt footer，opacity=0 只隐藏工具，不释放尺寸。标题段落本身再加 12pt 前距和 24pt 后距；分页容器另减 16pt。因此存在多层累计留白，适合用固定的小纸张边距、轻量进度底栏和浮层工具解决。
2. ReaderSession 为 MainActor；loadText 首先调用同步 text(at:)，最终在 LibraryStore.chapterText 中执行 Data(contentsOf:) 和 UTF-8 解码。NativeReader 的 Task 同样继承 MainActor，紧接着整章构建 attributed string 和 CoreText 全部分页；async 关键字没有把这些操作放到后台。
3. 连续滚动复用分页 ranges 作为 cell；每个 UITextView 使用自动行高并在主线程排版。补入相邻章节时重新切出全部 attributed substrings、reloadData、layoutIfNeeded、scrollToRow，再设 contentOffset；旧 cell 也会重复布局。
4. 每次 scrollViewDidScroll 都让 TextKit ensureLayout 并查询字形，再对全部章节 reduce 计算进度。每秒调用 session.report → library.update → persist，同步编码/原子写入整个 library.json，并通过 Published 通知书架。
5. 每次 CoreTextCanvas.draw 都从整章 attributed string 重新创建 framesetter；既有后台预加载也没有隔离这些 CPU 工作。

这些是可确认的主线程路径和重复工作，尚不是某台真实 iPhone 的时间采样。新增 DEBUG signpost、工作计数和 CADisplayLink 活动滚动采样用于相同原创内容的优化前后对照；不采集小说正文、书名或路径。若无法获得可运行的 macOS/真机环境，采样数值必须明确记为未执行，不能由源码推测帧率。

最小必要修改方向：保留 UITableView 的自然滚动和原有四种模式；后台读取/预排版，固定高度的有界文本块；追加/删除差异更新；滚动过程中只保存内存锚点，停滚/后台/退出才落盘；避免主题和工具栏变更重建表格。引擎命令、书籍/章节/书签字符偏移和文件导入事务保持原有语义。
