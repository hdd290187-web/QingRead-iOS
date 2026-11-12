# 书源兼容范围

支持阅读 3.0 常用 JSON 字段，不宣称 100% Legado 兼容。应用不内置商业站点书源。以下例子只指向保留测试域名，需用户替换成有权访问的站点。

```json
{
  "bookSourceName": "我的授权书库",
  "bookSourceUrl": "https://example.org",
  "searchUrl": "/search?q={{key}}&page={{page}}",
  "ruleSearch": {
    "bookList": ".book",
    "name": "a@text",
    "author": ".author@text",
    "bookUrl": "a@href"
  },
  "ruleBookInfo": { "tocUrl": "a.toc@href" },
  "ruleToc": {
    "chapterList": ".chapters a",
    "chapterName": "text",
    "chapterUrl": "href"
  },
  "ruleContent": { "content": "#content@text" }
}
```

| 能力 | 实现与边界 |
|---|---|
| 导入 | 单对象、数组或 sources 数组；本地 JSON、粘贴、HTTP/HTTPS URL；GitHub blob 自动转 raw |
| 搜索 | GET；{{key}} 为 URL 编码关键字，{{page}} 固定为第一页。未实现加载更多 |
| HTML | SwiftSoup CSS；class.xxx / id.xxx / tag.xxx；@text / @textNodes / @ownText / @html / @href / @src 等常用属性 |
| JSON | $.data.books[*]、简单字段、数组索引、通配；返回数组或 {books:[…]} 的简单接口可不配置规则 |
| 清洗 | ##正则##替换、||备选规则；正文保留段落和换行，移除脚本/样式标签 |
| 目录 | 详情页 tocUrl、章节列表、名称和 URL、去重、isReverse 字面布尔值 |
| 缓存 | 先读 App 私有目录，再请求远程正文；当前章完成后预取下一章；目录菜单可逐章缓存全部。中断时保留已完成章节 |
| 不兼容 | JS、XPath、变量 @put/@get、并联 &&、登录/Cookie/验证码、POST、动态签名、复杂 JSONPath、nextTocUrl/nextContentUrl 网页分页。导入标注并禁用 |
| 站点策略 | 识别 robots.txt 禁止路径、403/429 等错误；请求有间隔、不尝试绕过登录或访问控制。HTTP 明文仅用于用户导入的公开资源，建议 HTTPS；不保存凭据 |

兼容性检查是已知语法的静态检查；未知语法或站点改版仍可能在搜索、目录或正文阶段失败。错误显示给用户，不伪造搜索结果。自动测试使用原创 HTML/JSON 和 URLSession stub，不代表任何外站永久可用。
