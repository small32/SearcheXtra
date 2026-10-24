SearcheXtra 2.2.3：同步上游 16 个提交，新增逐扩展无痕权限、默认关闭的搜索建议与固定页跨站预览，修复扩展启动竞态、Stylus、媒体键、密码、安全密钥、本地文件及标签焦点问题。 SearcheXtra 2.2.3: Merge 16 upstream commits, adding per-extension private access and optional search suggestions and pinned-tab peeks, with fixes for extension startup, Stylus, media keys, passwords, passkeys, local files and tab focus. 分别提供 macOS ARM64 和 Intel x86_64 安装包。 Separate macOS ARM64 and Intel x86_64 packages.

SearcheXtra 2.2.2：移除 Windows 支持，后续仅维护 macOS，精简构建、测试和平台适配代码。 SearcheXtra 2.2.2: Remove Windows support and maintain macOS only, simplifying build, test, and platform-adapter code. 同步上游 6 项更新，新增弹窗拦截提示，修复视频与扩展弹窗，并在超级拖拽期间隐藏文本选择底色。 Six upstream updates add blocked-popup controls, fix video and extension popup behavior, and hide the text-selection background during super drag. 分别提供 ARM64 和 Intel x86_64 安装包。 Separate ARM64 and Intel x86_64 packages.

SearcheXtra 2.2.0 本次重建继续提供 Windows 与 macOS 安装包。macOS 同步上游稳定性、扩展侧边栏、标签管理及网页外观更新；Windows 改善标题栏扩展悬浮面板；保留 MV2/MV3 用户脚本、超级拖拽和书签操作。 SearcheXtra 2.2.0 is rebuilt for Windows and macOS. macOS gains upstream stability, extension side panels, tab management, and webpage appearance updates; Windows improves toolbar extension flyouts. MV2/MV3 user scripts, super drag, and bookmark interactions are retained.

SearcheXtra 2.1.1 修复了部分BUG。 SearcheXtra 2.1.1 fixes some bugs.

SearcheXtra 2.1.0 重构超级拖拽，支持文字、链接和图片的方向规则与鼠标指针预览，并修复书签网页图标、右键操作和中键后台打开。 SearcheXtra 2.1.0 rebuilds super drag with direction rules and pointer previews for text, links, and images, and fixes bookmark icons, context actions, and middle-click background opening.

SearcheXtra 2.0.5 为 Windows 和 macOS 新增超级拖拽，支持自定义规则、网站例外和配置导入导出，完善书签菜单切换，并修复书签图标显示与中键后台打开。 SearcheXtra 2.0.5 adds Super Drag on Windows and macOS with custom rules, website exclusions, and configuration import/export, improves bookmark menu switching, and fixes bookmark icons and middle-click background opening.

SearcheXtra 2.0.3 完善 macOS 与 Windows 的书签管理，支持拖动排序、批量操作和图标设置，并修复隐私模式、扩展、网站权限及数据导入问题。 SearcheXtra 2.0.3 improves bookmark management on macOS and Windows with drag-and-drop, bulk actions, and icon controls, and fixes private browsing, extensions, site permissions, and data imports.

SearcheXtra 2.0.2 为 macOS 和 Windows 提供卡片式扩展管理，支持搜索和开关控制扩展。Windows 同时支持将扩展图标固定到标题栏，修复 Chrome 扩展商店安装报错，简化权限确认界面，移除重复安装按钮，并修复扩展弹窗内容显示不全的问题。

# SearcheXtra 1.0.0

SearcheXtra 是基于 Office Commun 开发的 Search 修改。

提供以下功能：

## 中英文界面

- 提供英文和简体中文，覆盖菜单、设置项及说明、弹窗和操作提示。
- 在“设置 → 通用 → 界面语言”中选择“跟随系统”“English”或“简体中文”，重新启动后生效。
- 默认跟随系统语言；不支持的系统语言使用英文。

## 自定义起始页面

- 在“设置 → 通用 → 起始页面”中保存网址，新窗口会打开该页面；新建标签页默认保持空白。
- 点击“使用空白页”可恢复默认，设置立即生效。
- 恢复会话时保留原有页面；无痕标签页仍使用空白页。

---

Several windows, and a lot to discover. ⌘N opens another window with tabs of its own, a tab dragged out of the row becomes one, and pinned tabs are the same in every window. ⌃Tab shows your recent tabs as pictures, and your own keyboard shortcuts are in Settings › Shortcuts. Bringing things over works from Firefox, Zen, Helium, Comet, Opera and Arc — its spaces and pinned tabs included — or from an exported file, and remembers what came from where. New, each off until you turn it on, here or in the card after the update: tab groups, the sidebar on the right, videos that wait for a click, and a downloads button that stays. Also: bookmark folders you arrange yourself, site shortcuts like yt cats, a double-click that takes a pin back home, and downloads whose progress shows on the Dock. Scrolling costs half what it did, 1Password, Bitwarden, iCloud Passwords and Figma get their fixes, and a second careful private report brings another round of security hardening.

Security, and the mouse wheel. Search 1.0.3 closes the holes found in this week's reviews — an extension could read files outside its own folder, and a page or an ad could open another app without asking — and copying a saved password now asks for Touch ID. A mouse wheel scrolls smoothly again on x.com and pages like it, Bitwarden signs in to a self-hosted server, and extension popups hear what changes while they are open. Also: History opens at once, music keeps playing when you switch spaces, a link from Mail brings Search to the front, a full-screen video no longer goes black, pop-ups need a click, and the tab bar folded away with ⌘S comes back on a ground of its own. Your extensions may each ask once more for their permissions at their next update.

Passkeys, password managers and Google. A site's passkey button now brings up the Mac's own passkey sheet — Touch ID, your iPhone, a security key — and 1Password, Bitwarden and Proton Pass get their fixes. Pages no longer see anything of Search that Safari doesn't show them, the mark Google took for a robot; a saved password is offered only on its own site; and Search can be the Mac's default browser. New, each off until you turn it on in Settings: a bookmarks bar, a peek at a link with a shift-click, the video that follows you to another app, pages at 120 Hz, and where a link goes. Also new: mute a tab, share a page, copy a link as Markdown, the mouse's back and forward buttons, and spaces in the bar across the top. Faster to open, new tabs in about 10 ms, and many fixes. If passkeys still fail after the update, restart your Mac once.

The first update, made of a day of your replies and pull requests. Search opens again on macOS 14, and signing in to Google no longer reloads the page over and over with iCloud Passwords installed. New, each off until you turn it on in Settings: Spaces, a sidebar that hides until the pointer reaches the edge, and the search engine of your choice. Also new: ⌘S folds the sidebar away, a middle-click closes a tab, a tab can be renamed, and the Web Inspector is in the View menu. Fixed among others: ⌘1–⌘9 on every keyboard layout, Tab between the fields of a form, dragging tabs, a double-click along the top to fill the screen, and the Mac's beep while typing.

The first version. A browser for the Mac with nothing in the way: tabs in a row or down the side, pinned tabs that keep their place, and one field for addresses and searches. Ads are blocked before they load; passwords and passkeys stay in your keychain; anything on a page can be hidden; articles open in a reading mode and videos float. Chrome extensions install from the Chrome Web Store on macOS 15.4 or later — its button says Add to Search. Tabs you haven't looked at for half an hour sleep and give their memory back. It runs on the engine already in macOS and weighs 2.9 MB.
