# 阅读布局与连续滚动优化

状态：源码已实现，真实 macOS 的[针对性回归第 38 轮](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43398806434)为 **9 通过 / 0 失败 / 0 跳过**。完整设备 Release、三种尺寸回归和同设备前后采样尚待完成，新 IPA 尚未生成。本报告不宣称真实 iPhone 的卡顿已经验收修复。仓库已经实际 Public。

## 布局与工具栏

旧 ReaderHost 即使工具栏透明，也保留 52pt 顶栏、8pt 正文上边距和约 88pt 页脚。新布局默认沉浸，正文使用安全区中的空间，仅保留 28pt 章节/进度底栏；上下工具浮在正文上，显隐不改变分页容器或滚动视口。纯容器预算归还约 120pt，实际每屏增加多少正文行尚待同设备截图测量。

章标题前后段距由 12/24pt 调为 8/16pt，配合 8pt 纸边和系统安全区。正文字号、字重、左右边距、行距、段距及用户既有偏好保持原有语义。没有使用负 padding 或按某台设备写死屏幕坐标。异步进度更新不再关闭用户刚打开的工具栏；用户翻页、目录导航或拖动时隐藏工具。

优化前已验证 Build 31 历史截图：

![优化前阅读截图](../yuying/screenshots/03-reader.png)

完整流程还会导出小屏、iPhone 15、大屏及横屏的沉浸/浮层截图，以及同一 iPhone 15 模拟器上相同原创样本的前后画面。没有把历史截图冒充本次对照。

## 滚动开销、测量发现与修正

修改前的源码路径见 INVESTIGATION.md。MainActor 中存在章节同步读取/解码、整章 CoreText 分页；UITextView 自动高度及相邻章节 reloadData 会重复排版；滚动回调查询 TextKit 字形、遍历章节并定期同步写 library.json。

现在文件读取和解码在后台任务，排版在串行 actor。滚动直接准备约 1600 UTF-16 的有界块，保持组合字符/CRLF、章节顺序及段落缩进。后台完成的 TextKit stack 在交付后仅由主线程绘制，显示视图直接使用同一套已排好的 glyph、固定高度和行锚点。UIKit 表格只创建可见 canvas，保持系统惯性、回弹及减速。

真实回归发现，最初的“后台测量、UITextView 再排版”方案在相同字符/行数下有段末度量差异：5425/1005pt 的预排版分别变成 5357/992pt。调整 leading 和容器高度没有解决，因此改为直接绘制准备好的 TextKit glyph。第 38 轮实际结果为 **5425→5425pt、1005→1005pt**，分别完整绘制 1597/297 UTF-16；位图末尾仍有正文，字符锚点测试通过。保留原 1.1pt 精度，并增加实际绘制检查。

相邻章节用稳定 row ID 差异插入/删除；首次展示前准备目标附近两章，空闲保留约 ±2 章、活动时约 ±3 章。追加内容不设置滚动偏移，仅视口前的插入/裁剪补偿锚点。滚动回调使用缓存行位置二分和章节前缀和，不在每帧读取、整章分页或计算字形。

滚动中最多每 0.5 秒暂存阅读页状态；停止、后台、退出或书签时提交原有 ReadingPosition，重复 flush 不重复写 JSON。退出/后台保存最后有效锚点，不从过渡几何重新计算。正文起点按 contentOffset + 顶部纸边定位 row，避免上一章末行只在 8pt 纸边中可见时错误覆盖下一章位置。连续字号/尺寸重排保留原字符目标，真实翻页/导航/拖动才清除，避免中间页首累积后退。

## 已通过的针对性验证

真实环境为标准 GitHub 托管 macos-15，macOS 15.8.2 / Xcode 26.3 / iOS 26.2 Simulator（iPhone SE 3）。9 项全通过包含：

- 原字体与字符命中；UTF-16、组合字符及 CRLF 完整分块。
- 后台读取/缓存、后台排版不整章分页；进度暂存及幂等提交。
- 固定 row 的实际字形位图、末行、完整字符范围和行锚点。
- 跨章、连续字号调整、滚动模式字号/行距/主题、后台与退出重进的精确章节/字符恢复。
- EPUB 正文、排版、连续滚动及重进；短 TXT 相同快甩/反向/慢拖及退出重进。

DEBUG 采样报告的 JSON 类型已修正并有可序列化断言，退出不会再触发 JSON writer 异常。DEBUG 探针不进入 Release。本地资源、哈希、依赖/许可、Swift 语法、工作流 YAML/shell 检查通过；本地 Linux 不冒充 iOS 类型检查。

## 完整发布与性能对照待完成

默认流程仍使用标准 macos-15，保留设备 arm64 Release、全部 XCTest 和打包。reader_diagnostics 默认关闭，仅用于已发现失败项的 9 项验证且从不打包 IPA。完整流程计划主测试 65 项（预计 62 通过及既有 3 项 Files 诊断跳过），iPhone 15 为 10 项，固定 d75d7b6 基线 3 项、大屏 2 项；这些数字尚不是本轮完整通过结果。

同一 iPhone 15 模拟器分别测试 short / long / monolith 原创样本，执行相同 12 次快甩、4 次反向及慢拖，导出前后录屏、活动滚动帧时间、预算超时数量、主线程固定操作耗时和 resident memory。before/after 目前仍未完成，不填写推测的 FPS 或内存数值。模拟器共享资源与触摸自动化会影响帧时间，真实 iPhone 的 Time Profiler / Hangs / Core Animation 验证仍为 HUMAN_PENDING。

为容纳实测编译耗时、三种设备和基线的完整顺序验证，任务上限由 60 调为 90 分钟；使用同一标准 Runner，正常结束立即退出，不循环触发任务。

## 数据、公开与交付

Bundle ID、Application Support/QingRead、书籍/章节 ID、library.json、书签与设置键不变。LibraryStore、文件选择/协调暂存、导入事务、解析及错误反馈七个关键文件与 d75d7b6 一致。新增布局/前缀/内存锚点均为临时数据。没有上传或清空用户书库。

[公开审计](../security/PUBLICATION_AUDIT.md)已通过；用户确认历史图为自行生成，来源声明已记录，认证与未登录 API 均验证仓库为 [Public](https://github.com/hdd290187-web/QingRead-iOS)。之后源码提交均再次全历史遮蔽扫描，没有真实凭据。

完整构建与校验后才能生成本次 IPA。旧 Build 31 不含本次阅读优化或后续矢量图标，不能重新标为新包。同签名覆盖安装、旧书库/进度/书签和真机滚动仍需按 DEVICE_VALIDATION.md 验收；不要先卸载旧 App。

## 完整第 39 轮实际结果

[Build 39](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43401100910) 的 arm64 Release 编译通过；完整主计划为 61 通过 / 1 失败 / 3 跳过（65 项），42 个单元用例及所有阅读、EPUB、布局、三样本滚动压力用例均通过。唯一失败是首次启动原生 Files 时 Cancel 控件超过原来的 15 秒等待，随后在同一用例中实际出现并正常取消。保留原取消行为断言，将已证实的系统冷启动等待扩为 60 秒；没有把该用例跳过或当作成功。独立的 FileProvider 日志观察进程也增加对 simctl 冷启动超时的继续采集处理。后续 iPhone 15、基线和大屏阶段因主组失败尚未执行，需在修正后的完整 Build 40 中验证；没有新 IPA。

## 完整第 40 轮实际结果

[Build 40](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43404759462) 的真实 arm64 Release 和完整 XCTest 已通过：62 通过 / 0 失败 / 3 项既有 Files 跳过（65 项）。上轮的 Files 冷启动取消用例已通过。后续性能导出失败，错误为 CoreSimulator “Unable to lookup in current state: Shutdown”：Xcode 在测试结束后自动关闭了目标模拟器，容器仍在，但 get_app_container 要求 Booted。修正仅在导出脚本中重新启动同一目标并等待 bootstatus，不更改模拟器数据、阅读实现或测试断言。其后 iPhone 15、基线、大屏和打包尚未执行，不能把该轮整体标为成功；完整 Build 41 将验证导出修正并继续后续流程。

## 第 41 轮的测试启动与截图采集修正

[Build 41](https://github.com/hdd290187-web/QingRead-iOS/actions/runs/43408768485) Release 编译与 42 项单元用例通过；最初 3 个 UI 用例在 app.launch 处因 XCTest “Timed out while acquiring background assertion”失败，后续导入及阅读场景均通过。下一轮在测试前显式启动并等待同一模拟器的 bootstatus，XCTest 只对失败项最多再执行一次，原始失败和重试留在日志/xcresult，所有断言保留。每次新的合成性能测试尝试只清理该 fixture/variant 的测试报告，避免沿用失败尝试的采样；不操作真实用户书库。

人工检查完整第 40 轮截图发现 app.screenshot 横屏裁剪异常，虽然逻辑视口的旋转/边界断言通过，PNG 有黑边和内容截断，不能作为合格的横屏图。采集改为 XCUIScreen.main.screenshot，并等到实际视口尺寸/内容稳定后再截取；下一轮需要人工查看新图和全屏录屏。没有将旧的异常截图作为正式优化后证据。
