# SearcheXtra 2.2.2

[简体中文](#简体中文) · [English](#english)

## 简体中文

仅维护 macOS 版本，移除 Windows 应用、构建与专用测试。保留 MV3 用户脚本及现有浏览器功能，并减少重复处理和资源占用。

### 新增与优化

- 新增弹窗拦截提示和按站点允许，保留无痕隔离；修复自动播放设置、扩展弹窗宽度、浮动视频画面及 Twitch 聊天恢复，改善侧栏高亮动画。
- 超级拖拽期间隐藏文本选择底色，松开或取消后恢复，保留所选文字。

- **MV3 用户脚本**：扩展详情页提供默认关闭的“允许用户脚本”开关，支持脚本注册、独立执行环境、扩展消息通信和按标签页、框架及文档执行脚本。开启后请刷新网页。
- **ScriptCat 兼容性**：补充用户脚本运行所需的兼容接口，验证原版 ScriptCat 1.4.0 的 GM 存储、跨域请求、扩展重载和权限切换，并支持与 MV2 扩展同时运行。
- **WebKit 与 MV2 支持**：继续使用 macOS 内置 WebKit，MV2 扩展保持原有加载方式。
- **降低重复处理与资源占用**：书签菜单改为展开时创建，优化批量书签操作；减少侧边栏调整时的界面重建、扩展包扫描和重复脚本注入。关闭标签页、窗口与扩展弹窗时，及时释放监听、定时器和隐藏网页视图；限制历史记录与图标缓存的内存占用。

### 修复与改进

- 修复 macOS 切换用户脚本权限后，已打开网页的脚本通信可能失效的问题。切换时保留当前页面和输入，下一次刷新重建运行环境并保留浏览历史。
- 修复标签页恢复时的旧异步回调覆盖新导航或重新创建已关闭页面的问题。
- 修复下载代理设置过晚导致下载取消的问题。
- 改善历史记录、站点搜索和隐藏元素配置的保存与清空时序，避免旧异步结果恢复已清空的数据。
- 修正 macOS 密码认证不可用或中断时的判断，并修复无效拖拽配置、扩展原生消息和图标捕获等边界问题。
- 修复关闭自动滚动后动画仍继续运行、拖拽框架记录未及时清理，以及扩展弹窗异步尺寸更新作用于旧窗口的问题。

### 本次更新

- **macOS 上游同步**：整合 Search 至 `b2048a0` 的适用更新，修复关闭窗口后的资源释放、视频与全屏、网址解析、拦截器域名匹配，以及浏览器导入和分步登录兼容问题。
- **macOS 扩展体验**：加入扩展侧边栏、静默登录、后台端口恢复、周期更新，以及多个新标签页扩展之间的选择；保留现有 MV2/MV3 用户脚本实现。
- **macOS 标签与界面**：加入标签多选及复制网址、新标签位置、休眠时机、闲置自动关闭、网站保活、共享固定页、网页深色、120Hz 电源策略和整页 PDF 导出，新增设置提供中英双语。
- **保留已有操作习惯**：网址继续在标签页内部编辑；书签左键遵循设置、中键后台打开；保留超级拖拽，不恢复 AI 或浮动地址输入框。
- 构建和发布仅生成 macOS ARM64 和 Intel x86_64 两个独立安装包。

### 平台说明

- macOS：应用支持 macOS 14 及以上；扩展功能需要 macOS 15.4 及以上，分别提供 Apple 芯片 ARM64 和 Intel x86_64 安装包，不提供 Universal 包。
- 用户脚本兼容层不代表支持所有 Chrome 扩展 API，具体支持范围见 [用户脚本说明](https://github.com/small32/SearcheXtra/blob/main/docs/USER_SCRIPTS.md)。

---

## English

Maintains macOS only, removing the Windows application, build, and dedicated tests. Retains MV3 user scripts and existing browser features while reducing redundant work and resource use.

### New and improved

- Adds blocked-popup controls and per-site allowance with private-tab isolation. Fixes autoplay settings, extension popup width, floating-video framing and Twitch chat restoration, and improves sidebar highlight motion.
- Hides the text-selection background during super drag and restores it on release or cancellation, preserving the selected text.

- **MV3 user scripts:** Extension details offer an “Allow user scripts” switch, off by default. Supports script registration, separate execution worlds, extension messaging, and execution targeting tabs, frames, and documents. Refresh webpages after enabling access.
- **ScriptCat compatibility:** Adds compatibility APIs needed by user scripts. Tested the original ScriptCat 1.4.0 package with GM storage, cross-origin requests, extension reloads, permission changes, and simultaneous MV2 extensions.
- **WebKit and MV2 support:** Uses the system WebKit engine. MV2 extensions retain their existing loading path.
- **Less redundant work and lower resource use:** Bookmark menus are created when opened, and bulk bookmark operations are more efficient. Reduces interface rebuilding during sidebar resizing, extension package scans, and repeated script injection. Closing tabs, windows, and extension popups releases listeners, timers, and hidden web views. History and icon caches now use bounded memory.

### Fixes

- Fixed user-script communication in existing macOS webpages after permission changes. Changing permission leaves the current page and input untouched; the next refresh rebuilds its runtime while preserving browsing history.
- Fixed stale tab-restoration callbacks overriding newer navigation or recreating closed pages.
- Fixed downloads being cancelled when their delegate was assigned too late.
- Improved saving and clearing history, site-search settings, and hidden-element rules so stale asynchronous results cannot restore cleared data.
- Corrected macOS password authentication handling when system authentication is unavailable or interrupted. Fixed invalid drag configurations, extension native-message handling, and favicon capture edge cases.
- Fixed automatic scrolling continuing after being disabled, stale drag-frame records, and asynchronous extension-popup sizing affecting an outdated window.

### Changes in this rebuild

- **macOS upstream updates:** Ports applicable Search changes through `b2048a0`, including closed-window resource release, video/fullscreen behavior, URL parsing, blocker domain matching, browser imports, and multi-step sign-ins.
- **macOS extensions:** Adds side panels, quiet authentication, worker-port recovery, periodic updates, and selection between extension new-tab pages while preserving the existing MV2/MV3 user-script implementation.
- **macOS tabs and appearance:** Adds tab selection and URL copying, new-tab placement, sleep timing, optional automatic closing, per-site keep-awake choices, shared pins, webpage darkening, power-aware 120Hz, and full-page PDF export. New settings have English and Simplified Chinese text.
- **Existing interactions retained:** Addresses remain embedded in tabs; bookmark left-click follows preferences and middle-click opens in the background. Super drag remains available; AI and floating address fields remain excluded.
- Builds and releases now produce separate macOS ARM64 and Intel x86_64 packages.

### Platform notes

- macOS: macOS 14 or later; extensions require macOS 15.4 or later. Separate Apple silicon ARM64 and Intel x86_64 packages are supplied; no Universal package is built.
- The user-script compatibility layer does not implement every Chrome extension API. See the [user-script support details](https://github.com/small32/SearcheXtra/blob/main/docs/USER_SCRIPTS.md).
