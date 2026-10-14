# SearcheXtra 2.1.0

[简体中文](#简体中文) · [English](#english)

## 简体中文

重构超级拖拽，完善书签网页图标与鼠标操作体验，Windows 与 macOS 同步支持。

### 新增与优化

- **重构超级拖拽**：文字、链接、图片分别设置上下左右、连续方向和兜底规则；搜索支持浏览器默认引擎、内置服务和自定义网址。
- **丰富拖拽动作**：支持搜索、复制、收藏链接、保存图片和以图搜图；打开动作可选择当前页、前台或后台标签页、无痕标签页及标签插入位置。
- **拖拽内容预览**：文字、链接名称或网址、图片缩略图显示在鼠标指针正上方；指针下方显示小拖拽框，松开或取消后自动消失。
- **拖拽设置与配置迁移**：提供动作提示、轨迹、距离阈值和网站例外；支持导入、导出本应用的配置。入口位于“设置 → 标签页 → 超级拖拽”。

### 修复与改进

- 修复 Windows 原生拖拽中断导致动作不生效的问题；后台搜索立即加载，不再受到后台标签页按需加载设置阻止。修改规则后，已打开的网页同步生效。
- 补齐书签栏、文件夹下拉菜单和书签管理器的右键操作，支持修改书签名称与网址，修复嵌套目录的剪切、粘贴位置。
- 修复书签中键打开行为：始终在新后台标签页打开，保留当前页面；左键继续遵循书签打开方式设置。
- 修复书签网页图标不显示的问题：自动获取并缓存网站声明的图标，未访问过的书签也可加载；书签栏、各级下拉菜单和管理器同步刷新，保留默认开启的图标显示开关。

---

## English

Rebuilds super drag and improves bookmark website icons and mouse interactions on both Windows and macOS.

### New and Improved

- **Rebuilt super drag**: Configure separate rules for text, links, and images using cardinal directions, direction sequences, and fallback rules. Search supports the browser's default engine, built-in services, and custom URL templates.
- **More drag actions**: Search, copy, bookmark links, save images, and perform reverse image searches. Opening actions support the current page, foreground or background tabs, private tabs, and tab insertion positions.
- **Dragged-content previews**: Text, link labels or URLs, and image thumbnails appear directly above the pointer. A small drag box appears below it; both disappear when the drag ends or is canceled.
- **Drag settings and configuration transfer**: Configure action hints, trails, distance thresholds, and site exceptions. Import and export SearcheXtra configurations. Open Settings → Tabs → Super drag.

### Fixes and Improvements

- Fixed interrupted native dragging on Windows that prevented actions from running. Background searches load immediately even with lazy background tabs enabled. Rule changes also apply to pages that are already open.
- Completed context-menu actions across the bookmarks bar, folder dropdowns, and bookmark manager, including editing bookmark names and URLs. Fixed cut-and-paste destinations in nested folders.
- Fixed middle-click bookmark opening: it always opens a new background tab and keeps the current page selected. Left-click continues to follow the bookmark opening preference.
- Fixed missing bookmark website icons. Icons declared by websites are discovered and cached, including for unvisited bookmarks. The bookmarks bar, nested dropdowns, and manager refresh automatically; the icon visibility switch remains enabled by default.
