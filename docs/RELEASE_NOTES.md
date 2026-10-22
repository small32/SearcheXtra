# SearcheXtra 2.2.3

[简体中文](#简体中文) · [English](#english)

## 简体中文

合并 Search 上游至 `57912ad` 的 16 个新提交，保留超级拖拽、标签内地址编辑、中英双语及 MV2/MV3 用户脚本兼容。

- **扩展与无痕标签页**：在扩展详情中逐个授权访问无痕标签页，默认关闭；用户脚本遵循同一权限。首次授权前已打开的无痕标签页需要关闭后重开。撤销权限后，已在运行的脚本会在页面重新加载后停止。
- **Stylus 兼容**：修复扩展页面依赖 worker 提供动态脚本时弹窗空白的问题。
- **搜索建议**：新增搜索引擎输入建议，默认关闭，直接显示在标签内地址输入框下；无痕标签、网址、文件路径和敏感内容不会发送。支持中文、请求取消和超时处理。
- **固定标签页预览**：新增默认关闭的“固定标签页保留在原网站”选项，跨站链接在预览面板中打开，站内链接照常浏览。
- **媒体与采集**：暂停视频后归还系统媒体键；关闭标签页时停止其摄像头和麦克风采集，不影响其他标签页。
- **密码与安全密钥**：密码建议列表只读取账户信息，选中后才读取密码；用户名支持选择复制；避免在搜索框和标题框中提供密码建议，并兼容缺少用户句柄的安全密钥。
- **窗口与导航**：新增 ⇧⌘W 关闭窗口、标签区域鼠标前进/后退键切换空间；修复跨目录本地 HTML 链接、标签拖动、休眠页面布局和快速切换地址输入时的焦点问题。

仅提供 macOS ARM64（Apple 芯片）和 Intel x86_64 两个独立安装包，不构建 Universal 或 Windows 版。应用需要 macOS 14 或更新版本，扩展功能需要 macOS 15.4 或更新版本。

## English

Merges 16 Search upstream commits through `57912ad`, retaining super drag, embedded tab address editing, English and Simplified Chinese, and MV2/MV3 user-script compatibility.

- **Extensions in private tabs:** Grant access separately in each extension’s details, off by default. User scripts follow the same permission. Reopen private tabs created before the first grant. After revocation, scripts already running stop when the page reloads.
- **Stylus compatibility:** Fixes blank extension popups when a page expects its worker to supply a dynamic script.
- **Search suggestions:** Adds optional engine suggestions below the embedded address field. Off by default; private tabs, addresses, file paths and sensitive input are never sent. Supports Chinese input, cancellation and timeouts.
- **Pinned-tab peeks:** Adds an optional “Pins stay on their site” setting. Cross-site links open in a preview panel while links within the site continue normally.
- **Media and capture:** Paused videos release system media keys. Closing a tab stops its camera and microphone capture while other tabs continue.
- **Passwords and security keys:** Suggestion lists read account metadata first and fetch the password only when selected. Usernames can be selected and copied. Search and title fields no longer receive password suggestions, and security keys may omit the user handle.
- **Windows and navigation:** Adds ⇧⌘W to close a window and mouse back/forward buttons over tabs to change spaces. Fixes local HTML links across folders, tab dragging, waking-page layout and address-field focus during rapid switching.

Separate macOS ARM64 (Apple silicon) and Intel x86_64 packages only; no Universal or Windows build. Requires macOS 14 or later; extensions require macOS 15.4 or later.
