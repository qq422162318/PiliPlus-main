# PiliPlus · Windows JS 播放器版

中文 | [English](README.en.md) | [Windows 构建说明](README.windows.md)

基于 Flutter 的第三方哔哩哔哩桌面客户端，fork 自 [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)。本分支仅维护 **Windows x64**，视频播放统一使用 **Microsoft Edge WebView2 + DASH.js / HLS.js**。

> 本项目不是哔哩哔哩官方客户端。调整播放架构的目标是改善桌面使用体验，但不保证所有设备、视频和网络条件下的性能。构建和自动化测试通过，也不代表画面、音画同步或桌面窗口行为已全部验证。

## 下载与运行

从 [GitHub Releases](https://github.com/qq422162318/PiliPlus-main/releases/latest) 下载 Windows x64 便携 ZIP。

1. 确认系统已安装 [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)。
2. 将 ZIP 完整解压到可写的独立目录。
3. 运行 `piliplus.exe`。**必须保留全部 DLL 和 `data` 文件夹，不能只复制 EXE。**

更新前请退出正在运行的 PiliPlus，并备份原目录。建议先在独立目录试用新版，不要将不同版本的 DLL 和资源混用。账号和设置不包含在发布 ZIP 中；“便携包”指免安装的程序包，不表示用户数据一定保存在程序旁。

## 本分支的主要变化

| 项目 | 当前实现 |
| --- | --- |
| 点播 | DASH.js 将音视频轨合成 MPD，通过单个 HTML5 `<video>` 播放 |
| 直播 | HLS.js 处理 HLS / fMP4 流 |
| 渲染与解码 | 使用 WebView2 的浏览器媒体管线 |
| 视频编码选择 | 优先且仅选择 AVC / H.264；没有可用 AVC 轨时不回退到 HEVC / AV1 |
| 默认画质 | 未保存偏好时选择普通 720P；保留已有偏好和手动画质选择 |
| 弹幕 | 视频及直播弹幕固定关闭，相关绘制、分段请求与直播弹幕连接禁用 |
| 日志 | 程序旁的 `log.txt`，只保留本机当天记录 |

保留上游客户端的推荐、搜索、视频与分 P、番剧、直播、收藏、历史记录等页面。具体接口是否可用，仍受哔哩哔哩账号权限、地区、风控与服务端变化影响。

`fvp` / libmdk 的历史适配代码和依赖仍在仓库及部分构建产物中，但**不是当前默认视频播放后端**。不能把旧版原生解码器、纹理尺寸或 1–4 秒缓冲设置当作当前 JS 后端的行为。

## 日志

日志位置：

```text
程序目录/
├─ piliplus.exe
├─ log.txt
└─ data/
```

- 同一天重启保留当天已有记录。
- 启动时过滤其他日期；跨午夜后首次写入清除上一天的内容。
- 不再保留 `log.txt.previous`；启动时会删除旧轮转文件。
- 文件达到约 5 MB 后清空再继续写入，不提供全天无限存档。
- 记录启动、播放状态、跳转和异常；常见 URL、认证头及凭据会脱敏。分享前仍请自行检查。

日志目录不可写时不会因此中断播放，但也不会自动改写到其他位置。报告问题前请复制日志，避免跨日或大小限制使相关记录被清除。

## 常见问题与已知限制

### 网络异常：`Proxy failed to establish tunnel` / HTTP 501

通常是程序继承的代理不支持 HTTPS CONNECT，而不是视频解码错误。检查 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY` 和应用代理设置。若只从某个开发终端启动时失败，可尝试从资源管理器运行，或在单独启动进程中移除错误代理。不要随意禁用本来需要的系统代理。

### 只有声音、没有画面，或桌面图标被遮挡

WebView2 的原生窗口与 Flutter 的布局、缩放、全屏切换之间仍需实际验证。`v2.1.6.9` 已调整播放区域尺寸，但**最终画面和点击边界尚未完成人工验证**，不能仅凭播放进度推进判断画面正常。

遇到问题请提供：程序版本、Windows / WebView2 版本、窗口尺寸、显示缩放比例、是否全屏，以及当天日志。先退出其他实例，避免重复窗口和共享用户数据目录干扰排查。

### 上游功能不完全对应本分支

当前 JS 后端不提供播放器截图接口；旧原生后端的解码器属性、旋转和缓冲范围接口没有全部映射到 JS。不要据此认为截图、所有硬解开关、裁剪缩放或音频模式均已验证可用。

## 从源码构建

需要 **Flutter 3.47.8（Dart 3.13.7）**、Visual Studio 2022 / Build Tools 的桌面 C++ 组件、Windows SDK、Git 和 NuGet。仓库自带 Flutter / `material_ui` 补丁，必须在解析依赖后应用。

完整步骤、版本信息生成、打包与代理排查见 [README.windows.md](README.windows.md)。

## 发布验证

`v2.1.6.9` 的本地验证结果：

- Windows x64 Release 构建成功。
- 14 项嵌入式播放器 JavaScript 回归测试通过。
- 58 项 Flutter 测试通过，1 项真实原生媒体测试因未提供样片而跳过。
- 便携包内 72 个文件逐个校验；发布资产下载后 SHA-256 与本地一致。

以上不构成所有在线视频、音画同步或硬件性能的保证。发布页附有 `BUILD-INFO.txt` 和 `SHA256SUMS.txt`。

## 反馈与贡献

在 [Issues](https://github.com/qq422162318/PiliPlus-main/issues) 提交可复现的问题。请勿上传 Cookie、访问令牌、完整签名媒体 URL 或账号数据库。

欢迎提交针对 Windows 播放、布局和可靠性的改进；请明确复现步骤与验证范围，不用“构建成功”代替实际播放验证。

## 许可与致谢

本项目遵循 [GNU GPL v3](LICENSE)。第三方依赖遵循各自的许可证。使用本项目时请遵守适用法律与平台条款；本项目不提供会员破解或绕过内容权限的功能。

感谢以下项目及其贡献者：

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[PiliPala](https://github.com/guozhigq/pilipala)、[PiliPalaX](https://github.com/orz12/PiliPalaX)
- [Flutter](https://github.com/flutter/flutter)
- [DASH.js](https://github.com/Dash-Industry-Forum/dash.js)、[HLS.js](https://github.com/video-dev/hls.js)
- [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview)
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [Dio](https://pub.dev/packages/dio) 及其他依赖项目
