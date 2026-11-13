# 仓库公开前审计：未通过公开条件，保持 Private

审计目标：hdd290187-web/QingRead-iOS。当前 API 返回 Private，当前账号有 ADMIN 权限；没有执行公开操作。遵守最新用户说明中的“无法确认是否安全时视为未通过”，不能把未发现凭据当作全部审计通过。

## 扫描范围与方法

以 d75d7b6 为开始基线，获取了全部可访问的远端分支、tag 与 PR 列表：1 个远端分支、4 个 tag、0 个 PR。审查了 36 个历史提交；同时用 git cat-file 检查本地所有对象，包含不可达对象，共 569 个对象、292 个 blob，未只检查当前工作区。

Gitleaks 8.30.1 从官方发布下载并验证 SHA256。运行全历史、全 blob、Actions 日志、嵌套产物与发布附件扫描，报告开启 100% 秘密遮蔽。不调用凭据验证接口，不上传候选秘密。

已下载并检查 32 次 Actions 记录/日志、31 份未过期 artifact、1 个 Release 的 5 份附件；递归检查 ZIP、IPA、tar.gz，检查了 31253 个成员。也核对了隐藏/大文件、签名文件扩展名、私钥标记、图片 EXIF、网络地址、作者信息和长文本。原始审计资料保存在 VPS 的私有审计目录，不进入 Git 或交付归档。

## 凭据与隐私结果

- 全 Git 历史、全 blob、Actions 日志及 Release 附件的凭据扫描均为 0 命中。
- artifact 扫描的 7 个 generic-api-key 候选逐条核对，均为 Apple UIKit 创建视图控制器时的连接 UUID，分布在两份历史模拟器日志中；不是用户/GitHub/Telegram/API 认证凭据。没有打印或公开候选值。
- 未发现 p12、mobileprovision、私钥等敏感文件候选；未发现私有 IPv4 候选或图片 GPS/作者等隐私 EXIF。历史提交作者使用 noreply 身份。
- 额外网络引用核对为公开的第三方许可证/Readium CSS 引用及 URL 输入占位符。长文本为原创测试资料、XCTest 层级/错误记录和已有说明；未发现真实用户小说正文。日志中的 CoreSimulator 路径与 UUID 属于托管测试环境，未当作用户真机信息。

## 许可核对与唯一待确认条件

App 独立源码为 MIT；Readium、SwiftSoup 及锁定传递依赖保留各自许可证和 NOTICE；Noto Serif SC 保持原字体与 SIL OFL，固定源版本和哈希保留。未引入此前列为许可不明的参考仓库源码。最新 SVG 路径及自然封面代码为本项目独立绘制。

**尚无法确认历史用户上传参考图和旧 PNG 的公开再分发权。** 这些文件同时存在于 Git 历史与现有私有 Release 源码归档中，不能通过只在 main 删除文件就排除公开风险。范围包括 design/yuying-reference 的品牌拼图、局部参考图与旧 app-icon-1024.png。原有记录仅说明私人 App 的使用，未附明确的公共再分发许可；这不是已经认定侵权，而是公开前的许可事实尚不充分。已请求用户确认来源和授权。

在确认前保持 Private，不强制推送改写历史、不删除历史日志/附件、不删除仓库，也不擅自声称图片可公开。用户若确认拥有相应权利，可补入许可说明后复核；若不能确认，应另行讨论经授权的历史及 Release 清理方案。

## CI 与公开操作准备

保持标准 GitHub 托管 macos-15，未使用 larger/self-hosted/第三方付费 Runner；Xcode 26.3 和依赖版本保持。工作流仅 push main / workflow_dispatch，contents: read，不从不可信 PR 执行带写权限或秘密的工作流；checkout 已关闭凭据持久化。

满足许可条件并复核最新提交后，现有管理员权限可执行用户授权的 Public 修改并查询 API 验证，再触发一次完整工作流。目前不执行该条件动作。公开标准 Runner 不保证解除账户锁定；最近 Build 32 的 GitHub 注释仍是付款/支出上限阻塞。

脱敏机器可读结论见 audit-summary.json。后续新增代码提交还会再次进行全历史凭据扫描，但图片许可未确认前，结论仍为 NOT_APPROVED_FOR_PUBLICATION。
