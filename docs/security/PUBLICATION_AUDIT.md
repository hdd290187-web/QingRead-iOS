# 仓库公开前审计：通过，适合公开

审计目标：hdd290187-web/QingRead-iOS。完整历史、Actions 日志/附件与 Release 审查未发现真实凭据或隐私阻塞。用户于 2026-11-13 确认历史品牌参考图为其自行生成，结合本次明确公开授权，唯一待确认的素材来源条件已解决。结论为 APPROVED_FOR_PUBLICATION；实际可见性另以 GitHub API 操作后核实为准。

## 扫描范围与方法

以 d75d7b6 为开始基线，获取了全部可访问的远端分支、tag 与 PR 列表：1 个远端分支、4 个 tag、0 个 PR。审查了 36 个历史提交；同时用 git cat-file 检查本地所有对象，包含不可达对象，共 569 个对象、292 个 blob，未只检查当前工作区。

Gitleaks 8.30.1 从官方发布下载并验证 SHA256。运行全历史、全 blob、Actions 日志、嵌套产物与发布附件扫描，报告开启 100% 秘密遮蔽。不调用凭据验证接口，不上传候选秘密。

已下载并检查 32 次 Actions 记录/日志、31 份未过期 artifact、1 个 Release 的 5 份附件；递归检查 ZIP、IPA、tar.gz，检查了 31253 个成员。也核对了隐藏/大文件、签名文件扩展名、私钥标记、图片 EXIF、网络地址、作者信息和长文本。原始审计资料保存在 VPS 的私有审计目录，不进入 Git 或交付归档。

## 凭据与隐私结果

- 全 Git 历史、全 blob、Actions 日志及 Release 附件的凭据扫描均为 0 命中。
- artifact 扫描的 7 个 generic-api-key 候选逐条核对，均为 Apple UIKit 创建视图控制器时的连接 UUID，分布在两份历史模拟器日志中；不是用户/GitHub/Telegram/API 认证凭据。没有打印或公开候选值。
- 未发现 p12、mobileprovision、私钥等敏感文件候选；未发现私有 IPv4 候选或图片 GPS/作者等隐私 EXIF。历史提交作者使用 noreply 身份。
- 额外网络引用核对为公开的第三方许可证/Readium CSS 引用及 URL 输入占位符。长文本为原创测试资料、XCTest 层级/错误记录和已有说明；未发现真实用户小说正文。日志中的 CoreSimulator 路径与 UUID 属于托管测试环境，未当作用户真机信息。

## 许可与素材来源

App 独立源码为 MIT；Readium、SwiftSoup 及锁定传递依赖保留各自许可证和 NOTICE；Noto Serif SC 保持原字体与 SIL OFL，固定源版本和哈希保留。未引入此前列为许可不明的参考仓库源码。最新 SVG 路径及自然封面代码为本项目独立绘制。

用户在被询问历史上传参考图及旧 PNG 的来源时回复“是我自己生成的”。该声明记录在 design/yuying-reference/README.md 及随 App 的素材说明中。结合用户本次明确要求审计通过后公开现有仓库，design/yuying-reference 的品牌拼图、局部参考图、旧 app-icon-1024.png，以及含有它们的历史 Git / Release 源码归档已具备本次公开依据。没有把用户声明扩展为额外的第三方保证。

不需要重写历史、删除日志/附件或清理仓库；未执行这些操作。原始候选秘密、私有审计资料和凭据不进入公开源码或交付归档。

## CI 与公开操作准备

保持标准 GitHub 托管 macos-15，未使用 larger/self-hosted/第三方付费 Runner；Xcode 26.3 和依赖版本保持。工作流仅 push main / workflow_dispatch，contents: read，不从不可信 PR 执行带写权限或秘密的工作流；checkout 已关闭凭据持久化。

素材来源条件已解决，当前管理员权限可执行用户已授权的 Public 修改。2026-11-13 再次获取分支、tag、PR、Actions runs/artifacts 及 Release 清单：仍为 1 / 4 / 0 / 32 / 31 / 1（5 个附件），与已下载审查范围一致，没有新增未审查的远端附件。

候选实现及交付元数据提交后再次扫描完整 Git 历史（38 个提交），Gitleaks 为 0 命中；公开说明提交后再扫描一次。机器可读结论见 audit-summary.json。

随后查询 API 核实实际 Public，并且只触发一次完整标准 macos-15 工作流。公开标准 Runner 不保证解除账户锁定；之前 Build 32 的 GitHub 注释是付款/支出上限阻塞，新运行结果必须单独确认。
