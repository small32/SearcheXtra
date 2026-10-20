# MV3 用户脚本 / MV3 user scripts

## 简体中文

用户脚本需要 macOS 15.4 或更新版本。声明必需或可选 `userScripts` 权限的 MV3 扩展，在“设置 → 扩展 → 扩展管理 → 详情”中提供“允许用户脚本”开关，默认关闭。更改后会重新加载扩展；请刷新已打开的网页。

浏览器通过 WebKit 提供持久化脚本注册、独立内容世界、扩展消息通信，以及按标签页、框架或文档执行脚本。脚本受扩展的网站访问权限约束；网页不能通过此接口直接取得扩展存储、标签页或本机消息权限。MV2 扩展保留原有加载方式和清单版本。

自定义执行环境支持默认策略和 ScriptCat 使用的脚本策略；其他自定义 CSP 会明确报错。此兼容层针对用户脚本 API，不代表支持所有 Chrome 扩展 API。

## English

User scripts require macOS 15.4 or later. MV3 extensions declaring required or optional `userScripts` have an “Allow user scripts” switch under Settings → Extensions → Manage extensions → Details. It defaults to off. Changing it reloads the extension; refresh open webpages afterward.

The WebKit implementation provides persistent script registrations, separate content worlds, extension messaging, and execution targeting tabs, frames, or documents. Scripts remain subject to the extension's website permissions. The interface does not directly expose extension storage, tabs, or native messaging to websites. MV2 extensions retain their existing loading path and manifest version.

Custom execution worlds support the default policy and ScriptCat's script policy; other custom CSPs are rejected explicitly. This compatibility layer implements user-script APIs and does not imply support for every Chrome extension API.
