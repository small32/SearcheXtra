# FlowMouse-style super drag / FlowMouse 风格超级拖拽

## 中文

实现基于 SearcheXtra 2.0.3，入口为“设置 → 标签页 → 超级拖拽”。

行为参考：[Hmily-LCG/FlowMouse](https://github.com/Hmily-LCG/FlowMouse)，参考提交为 115d219fe48dc79f14a5a97d60b22d87d4468cd8。原仓库采用 GPL-3.0；这里的共享脚本和原生适配是独立实现，没有打包原扩展或复制其界面库。SearcheXtra 的 LICENSE 保持不变。

- 文字、链接、图片分别配置；默认均为向右拖拽，分别搜索文字、打开链接、打开图片。
- 支持 ↑、↓、←、→，以及 ↑→ 等连续方向。* 是未匹配方向的兜底规则；具体“无动作”规则优先于兜底。
- 支持浏览器默认搜索引擎、FlowMouse 内置搜索和图片搜索服务、自定义 %s 搜索网址。
- 打开动作支持当前页、新标签页、前台／后台、左右或首尾位置及原生无痕标签页。后台动作立即加载，不受按需加载设置阻止。
- 链接支持复制网址、文字、文字与网址（可用 Markdown）、收藏到指定文件夹；图片支持打开关联链接、复制网址、保存和以图搜图。
- 支持动作提示、轨迹、距离阈值、域名例外和输入框原生拖放。
- 拖动时，文字、链接名称或网址、图片缩略图显示在鼠标指针正上方，水平居中并保留 10 像素间距；指针下方显示小拖拽框，松开或取消拖拽时消失。内容预览和拖拽框不受动作提示和轨迹开关影响，两端使用相同的预览定位。
- 可导入 FlowMouse 导出的文字、链接、图片拖拽规则及相关开关，并导入／导出 SearcheXtra 的原生配置。鼠标手势、滚轮、摇杆、动作链和原扩展的全局黑名单不在导入范围内。
- 当前图片动作针对 HTTP(S) 图片；data/blob 图片不接管，保留网页原生处理。

Windows 使用 WebView2 的原生页面与 iframe 消息，macOS 使用 WebKit 隔离脚本世界。两端的超级拖拽跟踪真实鼠标按下、移动和松开，不依赖原生 drop 事件，以使用一致的预览位置并绕过 WinUI WebView2 中原生 HTML 拖拽立即中断的问题。普通点击、未配置动作的对象和未启用超级拖拽的网页保留原生行为。已接管的超级拖拽用于浏览器内的动作，不启动系统跨窗口拖放。两端共享同一套方向识别脚本和配置字段，不包含 Tab Mix Plus。

验证：共享脚本回归、Windows 模型检查及真实 WebView2 拖拽测试。macOS XCTest 已加入 CI；Windows 主机不能完成 macOS 编译和实机验收。

## English

The implementation is based on SearcheXtra 2.0.3. Open Settings → Tabs → Super drag.

Behavior reference: [Hmily-LCG/FlowMouse](https://github.com/Hmily-LCG/FlowMouse), commit 115d219fe48dc79f14a5a97d60b22d87d4468cd8. The upstream project uses GPL-3.0. The shared script and native adapters here are independent implementations; the original extension and UI libraries are not bundled. SearcheXtra's LICENSE is unchanged.

Text, links and images have separate rules. Rightward drags default to searching text, opening links and opening images. Cardinal directions, direction sequences, wildcard fallback, per-action search engines, custom URL templates, opening position, foreground/background tabs, private tabs, clipboard actions, bookmark folders, image saving and reverse image search are supported.

Background actions start loading immediately, even with lazy tabs enabled. Optional action hints, trails, distance thresholds, domain exclusions and native editable-field handling are available.

Dragged text, link labels or URLs, and image thumbnails appear directly above the pointer, horizontally centered with a 10-pixel gap. A small drag box follows below the pointer and disappears when the drag is released or canceled. Both platforms use the same preview positioning, independently of the hint and trail switches.

Import reads the text/link/image drag rules and related switches from FlowMouse exports. Mouse, wheel, rocker gestures, command chains and upstream global blacklist entries are outside the import scope. Native configurations can be imported and exported. Image actions currently handle HTTP(S) images; data/blob images retain native page behavior.

Windows uses WebView2 page/frame messages; macOS uses an isolated WebKit content world. Both super-drag adapters follow trusted mouse press, movement and release. This gives consistent preview placement and bypasses WinUI WebView2's interrupted native HTML drag loop. Ordinary clicks, objects without configured actions and disabled sites keep native behavior. Owned super drags perform browser actions rather than starting a system drag to another window. Both share the gesture script and configuration schema. Tab Mix Plus is not included.

Verification includes shared script tests, Windows model checks and actual WebView2 drags. macOS XCTest coverage is registered in CI; native macOS compilation and UI verification require a Mac.
