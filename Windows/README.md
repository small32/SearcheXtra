# SearcheXtra for Windows

Windows 版使用 C# / .NET 8、WinUI 3 和 WebView2，与 macOS 的 Swift 源码独立维护。标签页位于 Windows 标题栏，新建加号紧邻末尾标签；设置与扩展入口常驻右侧，并随浅色 / 深色主题更新图标。窗口保留 Windows 原生标题栏按钮：最小化、最大化 / 还原、关闭位于右上角；按住左键拖动、双击最大化及系统窗口菜单由 Windows 处理。

## 系统与运行

- **仅支持 Windows 10 1809（build 17763）及更新版本，包含 Windows 11。**
- **仅支持 x86_64 / x64 系统。** 不提供 x86 或 ARM64 构建；启动时检查系统架构。
- 推荐运行 `SearcheXtra-2.0.3-win-x64-setup.exe` 安装。安装器检测 .NET 8 x64、Windows App SDK 1.8 x64 和 WebView2；缺失时从微软下载并安装，已有兼容版本会跳过。补装 .NET 时需要管理员权限和网络。
- ZIP 为依赖系统运行库的便携包，需先安装上述运行库；解压整个目录后运行 `SearcheXtra.exe`。
- 应用目录不携带 .NET 或 Windows App SDK 运行库，只保留必要的托管接口、部署引导库与应用依赖。共享运行库不会随卸载应用而删除。
- 此本地构建未作代码签名。

## 已实现

| 功能 | Windows 实现 |
|---|---|
| 地址与搜索 | HTTP(S) 导航、Bing / Google / DuckDuckGo / 百度；仅查询本机历史提供补全 |
| 标签页 | 顶部 / 侧边标签栏、固定标签、标签分组、拖动排序、关闭与恢复、标签搜索 |
| 性能 | 恢复标签及后台书签按需创建 WebView2；共享环境；复用已加载实例；闲置挂起与恢复 |
| 书签 | 紧凑书签栏；默认 / 后台 / 前台打开方式；多级文件夹；搜索、删除、HTML 导入导出 |
| 分屏 | 两页并排、拖动分隔线、独立操作焦点、恢复分屏与宽度、分离分屏 |
| 多窗口与空间 | 独立标签集合、空间切换、移动标签、多窗口会话恢复 |
| 隐私 | InPrivate 配置；无痕导航不写历史或会话；本机数据存储 |
| 密码 | 当前 Windows 用户 DPAPI 加密的本地账号库；手动保存、删除及匹配来源后填写；WebView2 原生自动保存 |
| 下载 | 指定目录、进度、暂停、继续、取消、定位文件 |
| 阅读模式 | 提取 article / main，移除常见导航与表单，适配浅色 / 深色 |
| 画中画 | 主文档视频移到 Windows 置顶小窗，复用原 WebView2，不重新加载视频 |
| 隐藏元素 | 点击选择元素、按网站保存 CSS 选择器、后续文档加载时注入；可清除网站规则 |
| 广告与跟踪 | 内置常见跟踪 / 广告域名列表，在请求阶段阻止；可在设置关闭 |
| 扩展 | Chrome 商店下载与 CRX3 签名校验；MV2 / MV3 原生加载；CRX2 / CRX3 / ZIP 和目录导入；后台脚本、弹出页、选项、新标签页覆盖、固定、启停与卸载 |
| 其他 | 中英文、外观、起始页面、打印、开发者工具、全屏、版本下载入口 |

后台挂起前检查播放中的媒体、已修改的输入框和经网页媒体接口开始的采集。挂起保留页面状态；当前实现不自动销毁闲置页面，以避免丢失网页内存状态。

Windows 无痕标签页暂不支持扩展，设置中的对应开关不可用；新建无痕标签页保持空白。

Private Windows tabs currently do not support extensions. The corresponding setting is unavailable, and new private tabs remain blank.

## 与 macOS 版的差异

- 扩展使用 WebView2 原生 Chromium API；macOS 的 WebKit Chrome API 补丁不适用于 Windows。扩展调用的具体 API 仍需逐扩展验证。
- 阅读模式是基于文档结构的提取，不保证每个网站都能正确识别文章。
- 画中画适用于主文档视频；跨来源 iframe 播放器与 DRM 网站需单独验证。
- 已移植 macOS 的跟踪域名表与逐网站开关。网页 CSS 广告规则与 WebKit 的拦截行为仍有差异。
- 通行密钥使用 WebView2 / Windows Hello；密码使用 Windows DPAPI。Apple 钥匙串和 AppleScript 是 macOS 专属功能。脚本控制在 Windows 使用当前用户命名管道。
- 不提供后台自动更新；“查看最新版本”打开仓库 Release 页面。
- 快捷键按 Windows 习惯使用 Ctrl，支持编辑；关键词和 Tab 网站搜索已接通。Chrome / Edge / Brave / Firefox 的本机配置目录可导入书签和历史，密码通过 CSV 导入。

## MV2 扩展

设置 → 扩展提供“选择目录”和“导入 CRX / ZIP”入口。清单保持 MV2，不自动改写为 MV3。支持旧 `browser_action`、常驻后台脚本 / 后台页，以及原生 `webRequestBlocking`。CRX2 使用该旧格式的 RSA/SHA-1 签名校验，CRX3 使用 RSA/ECDSA/SHA-256；验证成功后保留签名公钥对应的原始扩展 ID。ZIP 可含一个顶层扩展目录。

已在 **WebView2 Runtime 154** 验证 MV2 常驻后台、消息、存储、内容脚本、弹出页和实际请求拦截；另以官方 uBlock Origin 1.75.0 Chromium MV2 包验证安装、后台初始化、控制面板及真实请求过滤。扩展列表标注 MV2 / MV3；Runtime 拒绝 MV2 时安装会报告版本和错误。

[Chrome 商店已于 2026-08-31 移除剩余 MV2 扩展](https://developer.chrome.com/docs/extensions/develop/migrate/mv2-deprecation-timeline)，旧扩展需从开发者取得 CRX / ZIP 或已有目录。[微软已公布 Edge 的 MV2 退场计划](https://blogs.windows.com/msedgedev/2026/08/07/moving-the-microsoft-edge-extensions-ecosystem-forward-with-manifest-version-3/)；这次实测不能保证后续 Evergreen Runtime 永久支持 MV2。

运行真实 MV2 测试（仅使用隔离临时配置）：

```powershell
$env:SEARCHEXTRA_TEST_MV2_PACKAGE = 'C:\path\to\uBlock0_1.75.0.chromium.zip'
./Windows/test-ui.ps1 -Executable 'C:\path\to\SearcheXtra.exe'
Remove-Item Env:SEARCHEXTRA_TEST_MV2_PACKAGE
```

## 快捷键

| 操作 | 快捷键 |
|---|---|
| 地址栏 / 新标签 / 关闭标签 | Ctrl+L / Ctrl+T / Ctrl+W |
| 新窗口 / 无痕标签 | Ctrl+N / Ctrl+Shift+N |
| 恢复关闭的标签 | Ctrl+Shift+T |
| 切换标签 | Ctrl+Tab / Ctrl+Shift+Tab |
| 标签搜索 / 添加书签 | Ctrl+K / Ctrl+D |
| 后退 / 前进 / 刷新 | Alt+← / Alt+→ / Ctrl+R |
| 查找 / 历史 / 下载 | Ctrl+F / Ctrl+H / Ctrl+J |
| 全屏 | F11 |

书签中键点击打开后台标签，Shift+中键打开前台标签，Ctrl+点击打开后台标签。

## 构建

需要 Windows x64、.NET 8 SDK 与 Inno Setup 6.7+（或通过 `-InnoSetupCompiler` 指定 ISCC.exe）。项目通过 NuGet 引入 WinUI 和 Windows SDK 引用，建议安装 Visual Studio 的 Windows 应用开发工具与 Windows SDK。

```powershell
./Windows/build.ps1
# 或指定 dotnet.exe
./Windows/build.ps1 -DotNet 'C:\path\to\dotnet.exe'
# 包含真实 WebView2 集成测试（需要 WebView2 Runtime）
./Windows/build.ps1 -RunUiTests
```

构建先运行模型测试，再发布依赖共享运行库的 x64 目录，并生成安装 EXE、ZIP / SHA-256：

```text
Windows/artifacts/win-x64/SearcheXtra.exe
Windows/artifacts/SearcheXtra-2.0.3-win-x64.zip
Windows/artifacts/SearcheXtra-2.0.3-win-x64-setup.exe
Windows/artifacts/SHA256SUMS.txt
```

`.github/workflows/windows.yml` 在 GitHub Actions 上执行相同流程并上传构建附件；Release 流程同时构建 macOS ARM64 与 Windows x64，并在两端构建成功后统一发布安装包和校验文件。

## 测试和数据

普通数据位于 `%LOCALAPPDATA%\SearcheXtra\`；WebView2 数据位于其 `WebView2` 子目录。密码库使用当前用户 DPAPI 加密，不可直接迁移给其他 Windows 用户。

模型测试：`dotnet run --project Windows/Tests/Tests.csproj -c Release`。

真实 WebView2 集成测试：设置 `SEARCHEXTRA_DATA_DIR` 为独立测试目录，`SEARCHEXTRA_SMOKE_TEST` 为 JSON 报告路径，再启动应用。测试使用本机临时 HTTP 服务器，检查导航、三种书签打开方式、按需加载、状态保留、分屏、挂起与无痕隔离，完成后自动关闭。不要把该环境变量用于普通浏览。

Win10 最低版本及不同 Runtime 的兼容性仍需对应机器验证；本机成功构建和运行不等于已经完成所有支持系统的验收。

macOS 与 Windows 均已移除 AI 功能、模型下载及推理进程。Windows 只引用所需的 WinUI / Runtime 组件，不再引入未使用的 AI、ML、Widgets 和 DWrite SDK 组件。版本号统一读取仓库根目录的 `VERSION`。
