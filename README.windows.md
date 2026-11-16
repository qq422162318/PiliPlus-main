# Windows 构建与排查指南

[项目首页](README.md) | [English](README.en.md)

本分支仅维护 Windows x64。当前默认播放链路是 **Flutter → WebView2 → DASH.js / HLS.js**，不是历史上的 `fvp` / libmdk 播放链路。以下命令以 PowerShell 为例，不依赖某台机器的 SSH 地址或外部构建脚本。

## 1. 运行发布包

从 [Releases](https://github.com/qq422162318/PiliPlus-main/releases/latest) 下载便携 ZIP，完整解压后运行 `piliplus.exe`。

运行要求：

- Windows x64，以及适用于该系统的 Microsoft Visual C++ 运行库。
- [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)。`WebView2Loader.dll` 不等于完整 Runtime。
- 可访问哔哩哔哩 API 与媒体 CDN 的网络。
- 程序目录可写，才能在 EXE 旁生成 `log.txt`。

程序包结构如下，具体 DLL 列表以该版本发布包为准：

```text
PiliPlus/
├─ piliplus.exe
├─ flutter_windows.dll
├─ WebView2Loader.dll
├─ 其他依赖 DLL
└─ data/
   ├─ app.so
   ├─ icudtl.dat
   └─ flutter_assets/
```

不要只复制 EXE，也不要混用不同版本的 DLL、`app.so` 和资源。更新前退出 PiliPlus 并备份原目录。账号与配置保存在应用支持目录，而不是发布 ZIP 内；免安装包不代表用户数据完全随程序目录移动。

## 2. 编译依赖

| 依赖 | 要求 |
| --- | --- |
| Flutter | **3.47.8**，对应 Dart **3.13.7** |
| Visual Studio / Build Tools | 2022，包含“使用 C++ 的桌面开发”所需组件 |
| C++ 工具链 | MSVC x64/x86、CMake 工具、Windows SDK |
| Git | 获取源码、Git 依赖、应用补丁与生成版本信息 |
| NuGet | WebView2 等 Windows 插件的原生依赖恢复；`nuget.exe` 必须在 PATH 中 |
| 网络 | 依赖解析访问 pub.dev、GitHub；原生依赖可能访问 NuGet 与其他上游下载服务 |

Flutter SDK 不替代 MSVC 或 Windows SDK。建议使用独立 Flutter SDK 和 Pub 缓存：本项目需要修改 Flutter 与 `material_ui`，不要将打过补丁的环境无条件共享给其他项目。

## 3. 获取源码与设置环境

下面的 G 盘路径只是示例，可以换成自己的目录。不要覆盖已有源码或工具目录。

```powershell
git clone --branch v2.1.6.10 --single-branch https://github.com/qq422162318/PiliPlus-main.git
Set-Location PiliPlus-main

$ToolsRoot = 'G:\Downloads\buildtools'
$env:FLUTTER_ROOT = Join-Path $ToolsRoot 'flutter3478\flutter'
$env:PUB_CACHE = Join-Path $ToolsRoot 'flutter-pub-cache'
$env:NUGET_PACKAGES = Join-Path $ToolsRoot 'nuget-packages'
$env:NUGET_HTTP_CACHE_PATH = Join-Path $ToolsRoot 'nuget-http-cache'
# 将自己的 NuGet 目录加入 PATH；下面示例使用 6.14.0。
$env:PATH = (Join-Path $ToolsRoot 'nuget-6.14.0') + ';' + $env:PATH
$Flutter = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'

& $Flutter --version
& $Flutter doctor -v
Get-Command nuget.exe
```

`pubspec.yaml` 和 `.fvmrc` 指定 Flutter 版本。不要为解决依赖问题直接升级 Flutter 或全部依赖；先复现锁定版本下的错误。

## 4. 解析依赖、应用补丁、编译

在项目根目录依次运行：

```powershell
& $Flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw '依赖解析失败' }

& .\lib\scripts\patch.ps1 windows -FlutterRoot $env:FLUTTER_ROOT

& $Flutter analyze --no-pub --no-fatal-infos
if ($LASTEXITCODE -ne 0) { throw '静态检查失败' }

& .\lib\scripts\build.ps1
if ($LASTEXITCODE -ne 0) { throw '构建版本信息生成失败' }

& $Flutter build windows --release --no-pub --dart-define-from-file=pili_release.json
if ($LASTEXITCODE -ne 0) { throw 'Windows Release 编译失败' }
```

### 补丁会修改什么

`lib/scripts/patch.ps1` 对 Flutter SDK、解析得到的 `material_ui` 和 `flutter_inappwebview_windows` 应用仓库内的补丁。WebView 补丁将视频纹理采样改为 `FilterQuality.medium`，避免非整数缩放或手势放大时使用最近邻产生像素块。脚本先检查整组补丁、备份原文件，再修改；重复运行会识别已应用状态。默认备份目录为 `$env:TEMP\piliplus-windows-patches`，可通过 `-BackupRoot` 指定其他位置。

若报版本不匹配或补丁部分应用，先检查 SDK、包版本与备份，不要直接删除缓存或重置 SDK。

### 版本信息如何生成

`lib/scripts/build.ps1` 生成被 Git 忽略的 `pili_release.json`，写入版本名、构建号、提交哈希与构建时间。

- 版本名和构建号统一取自 `pubspec.yaml` 的声明；`v2.1.6.10` 对应 `2.1.6+10`。脚本不再按 Git 提交数改写版本号，也不会修改 `pubspec.yaml`，浅克隆不会改变版本号。
- Git 工作树：读取当前提交哈希作为源码标识。
- 不含 `.git` 的源码目录：提交哈希记为 `local`。

正式发布应先提交源码，并以该提交构建和创建标签。不要把生成的 `pili_release.json`、包缓存或完整编译产物直接提交进源码仓库。

## 5. 打包与校验

编译输出：

```text
build\windows\x64\runner\Release
```

将整个 Release 目录打包，而不是只打包 EXE。先确保输出名称不存在，再运行：

```powershell
$Release = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
$Zip = Join-Path (Get-Location) 'PiliPlus-windows-local.zip'
if (Test-Path $Zip) { throw '目标 ZIP 已存在，请换一个名称' }
Compress-Archive -Path "$Release\*" -DestinationPath $Zip
Get-FileHash -LiteralPath $Zip -Algorithm SHA256
```

建议随发布包提供构建版本、源码提交、测试结果和 SHA-256 校验文件。正式发布前下载上传后的资产并比较哈希。发布标签应指向实际编译的源码；不要把旧二进制仅改 ZIP 文件名作为新版本发布。

当前发布渠道为 [GitHub Releases](https://github.com/qq422162318/PiliPlus-main/releases)。工作流触发方式以仓库的 `.github/workflows` 和 GitHub 实际状态为准，不能假定推送标签一定会自动构建发布。

## 6. 测试与验证边界

`v2.1.6.10` 起发布源码包含完整的 `test` 目录，可运行：

```powershell
& $Flutter test --no-pub
```

用 Node.js 运行嵌入式页面测试：

```powershell
node --test .\test\plugin\pl_player\dash_shell_test.cjs
```

版本信息脚本的回归测试验证源码 ZIP、Git 工作树和浅克隆均保留声明版本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\scripts\build_version_test.ps1
```

测试目录已纳入 `v2.1.6.10` 源码；旧标签可能没有完整测试。测试与 Windows 构建应串行执行，避免原生构建锁争用。

`v2.1.6.9` 本地发布验证：14 项嵌入式页面测试通过；58 项 Flutter 测试通过、1 项跳过；Windows Release 编译成功；ZIP 中 72 个文件与编译输出逐个校验，发布资产下载校验一致。真实原生媒体测试因未提供 `PILIPLUS_NATIVE_TEST_MEDIA` 样片而跳过。

`v2.1.6.10` 修复版本地验证：19 项嵌入式页面测试通过；73 项 Flutter 测试通过、1 项原生真实样片测试因未提供 `PILIPLUS_NATIVE_TEST_MEDIA` 跳过。布局回归覆盖不同视口与 100%/125%/150%/200% DPI；运行时日志显示实际视口取代固定 `640×360`，用户确认画面播放正常。

**自动测试不证明所有最终画面、声音、音画同步、全屏/缩放或桌面图标点击场景均正常。** 全屏、跨屏 DPI、HLS/直播、4K/HDR 等仍需对应运行时验证；不能以音频正常或 `currentTime` 推进证明视频画面正常。

## 7. 日志规则

`log.txt` 写在 `piliplus.exe` 同目录，不依赖旧的 JSON 日志设置开关。

- 按本机本地日期过滤，保留当天记录及其堆栈续行。
- 同一天重启追加会话；跨午夜后的首次写入清除前一天内容。程序空闲时不会专门启动午夜清理任务。
- 不再轮转到 `.previous`，旧轮转文件在启动写日志时删除。
- 约 5 MB 上限；达到上限后清空当前文件再写入，所以当天早先记录也可能被清除。
- 常见 URL、认证头和凭据会脱敏，但仍应在分享前人工检查。
- 不可写目录会停止日志记录，不会自动迁移日志路径或让日志错误中断播放。

报告问题前先复制当天日志。不要上传账号数据库、Cookie 或令牌。

## 8. 排查常见问题

### 依赖解析或 API 请求报 HTTP 501

若错误为 `Proxy failed to establish tunnel` 或 `Unsupported method ('CONNECT')`，先检查代理是否支持 HTTPS CONNECT。

```powershell
Get-ChildItem Env: | Where-Object { $_.Name -match 'proxy' }
```

通过开发终端启动的程序会继承该终端的环境变量。某些仅转发特定 API 的本地服务不是通用 HTTPS 代理。只在确认变量错误时，才为本次子进程清理它们：

```powershell
# 仅影响当前 PowerShell 及之后启动的子进程，不改系统设置。
Remove-Item Env:HTTPS_PROXY, Env:HTTP_PROXY, Env:ALL_PROXY -ErrorAction SilentlyContinue
```

需要代理时改用自己的有效地址，并检查 `NO_PROXY` 是否意外设为 `*`。不要把开发工具的认证令牌或专用代理配置写进项目。

### `NUGET-NOTFOUND` / MSB3073 / 9009

确认 `Get-Command nuget.exe` 能找到工具，并且 Visual Studio / Build Tools 的 C++ 组件完整。下载 NuGet 后验证来源与 Microsoft 签名。不要仅安装 Build Tools 就认为 NuGet 已存在。

### 只有声音、没有画面，或 WebView 遮挡桌面

确认 WebView2 Runtime 已安装。记录问题发生时的窗口尺寸、显示缩放比例、全屏/缩放状态及版本，配合当天日志排查原生 WebView 窗口边界。先退出其他实例；不要只看播放时间和音频就断言画面恢复。

### 1080p 也有明显像素块

JS 后端必须直接使用播放器的实际布局尺寸，不能将 WebView 放在 `FittedBox` 内：无界约束会使其退回 `640×360` 渲染，然后再被放大到窗口/全屏，损失源视频细节。当前布局在页面内完成适配、裁剪与比例调整，并由插件使用显示器 DPI 渲染。日志中的 `render viewport=... dpr=... targetPixels=... source=...` 可区分渲染尺寸与解码分辨率。

未保存过画质时桌面默认选择 1080p；已有偏好不被覆盖。账号或视频没有该档位时仍按实际可播放的 AVC 轨回退，不能凭空提升源视频细节。画质菜单的手动选择保存到桌面播放器读取的同一配置项（包括有线网络），临时播放器配置不持久化。查看 `Video quality selected` 日志可确认实际轨道、分辨率、码率和编码。

### 旧版 fvp / mpv 设置没有效果

当前默认后端是 JS。旧的原生解码器、缓冲、旋转或截图接口并不全部实现；旧文档里的 D3D11/MFT/DXVA 选择、纹理限制或 MDK 性能数据不能直接套用到这个后端。
