# SearcheXtra 2.0.3

[简体中文](#简体中文) · [English](#english)

## 简体中文

完善 macOS 与 Windows 的书签管理，修复隐私模式、扩展、网站权限及数据导入问题，并优化运行效率。

### 新增与优化

- 两端新增书签管理器，支持导入、导出、搜索、排序、全选及批量删除，支持拖动调整顺序和移动书签、文件夹。
- 完善书签栏右键菜单，支持添加、重命名、剪切、复制、粘贴及批量打开书签。
- 书签栏支持网站图标和文件夹图标显示开关；紧凑模式同时作用于下拉菜单，文件夹菜单默认向下展开。
- 减少重复界面刷新和脚本注册，优化书签图标更新及扩展同步，精简重复代码。

### 修复

- 修复关闭最后一个无痕标签页、批量打开书签及标签组操作中的隐私模式问题。
- 修复 Windows 网站权限弹窗被其他窗口遮挡时错误保存拒绝状态，以及无痕网站权限显示不准确的问题。
- 修复扩展启用、停用和移除时的状态同步；改善 macOS 无痕扩展切换及原生消息通信。
- 修复 Windows 历史记录导入丢失访问记录、Firefox 书签导入包含内部目录，以及 CSV 密码导入破坏特殊字符的问题。
- 修复 Windows 标签页字母图标和书签网站图标更新不及时的问题。
- 修复 macOS 广告拦截开关未正确处理暂停网站和非当前工作区标签页的问题。
- 修复安装路径包含单引号时的安装验证问题，以及 macOS 中文界面中的相机图标问题。
- 修正 macOS 更新检查，使用 SearcheXtra 自身的 GitHub Release，并完善发布构建和回归测试。

### 平台说明

- Windows 无痕标签页暂不支持运行扩展，相关开关已禁用并提供说明；无痕新标签页使用空白页。
- macOS 保留无痕扩展支持。

---

## English

Improves bookmark management on macOS and Windows, fixes issues with private browsing, extensions, site permissions, and data imports, and reduces redundant processing.

### New and Improved

- Added a bookmark manager on both platforms with import, export, search, sorting, select all, bulk deletion, and drag-and-drop reordering and folder moves.
- Expanded bookmark bar context menus with add, rename, cut, copy, paste, and bulk-open actions.
- Added controls for website and folder icons. Compact mode also applies to dropdown menus, and folder menus open downward by default.
- Reduced redundant UI refreshes and script registration, improved bookmark icon updates and extension synchronization, and simplified duplicate code.

### Fixes

- Fixed private browsing behavior when closing the last private tab, opening multiple bookmarks, and managing tab groups.
- Fixed Windows permission prompts incorrectly saving a denial when another dialog was open, and inaccurate permission states in private browsing.
- Fixed extension state synchronization during enable, disable, and removal operations; improved private extension switching and native messaging on macOS.
- Fixed lost history entries during Windows imports, internal Firefox folders appearing in bookmark imports, and special characters being altered in CSV password imports.
- Fixed delayed updates to Windows tab initials and bookmark website icons.
- Fixed macOS content-blocking changes incorrectly handling paused websites and tabs in other workspaces.
- Fixed installer verification for paths containing apostrophes and the camera icon in the Chinese macOS interface.
- Updated macOS update checks to use SearcheXtra’s own GitHub Releases, and improved release builds and regression coverage.

### Platform Notes

- Windows private tabs currently cannot run extensions. The setting is disabled with an explanation, and private new tabs use a blank page.
- Private extension support remains available on macOS.
