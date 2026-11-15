# PiliPlus · Windows JS Player Edition

[中文](README.md) | English | [Windows build guide (Chinese)](README.windows.md)

A third-party Bilibili desktop client built with Flutter, forked from [bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus). This fork maintains **Windows x64 only** and uses **Microsoft Edge WebView2 with DASH.js / HLS.js** for video playback.

> This is not an official Bilibili client. Improving desktop playback is a goal, not a performance guarantee. A successful build or automated test run does not establish that video rendering, audio/video synchronization, and desktop window behavior work in every scenario.

## Download and run

Download the Windows x64 portable ZIP from [GitHub Releases](https://github.com/qq422162318/PiliPlus-main/releases/latest).

1. Install [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) if it is unavailable.
2. Extract the entire ZIP into a separate writable directory.
3. Run `piliplus.exe`. **Keep every DLL and the `data` directory; do not copy the executable alone.**

Exit PiliPlus and back up its directory before updating. Test a new version separately before replacing an existing installation, and do not mix DLLs or assets from different versions. Release ZIPs do not include accounts or settings. “Portable” means the application does not require an installer; it does not mean all user data is stored beside the executable.

## Changes in this fork

| Area | Current implementation |
| --- | --- |
| On-demand video | DASH.js combines video and audio tracks in an MPD and plays them through one HTML5 `<video>` element |
| Live streams | HLS.js handles HLS / fMP4 streams |
| Rendering and decoding | WebView2's browser media pipeline |
| Video codec selection | AVC / H.264 only; no fallback to HEVC or AV1 when AVC is unavailable |
| Default quality | Ordinary 720P when no preference is stored; saved preferences and manual selection are retained |
| Danmaku | Disabled for video and live playback, including rendering, video segment requests, and live danmaku connections |
| Logging | `log.txt` beside the executable, retaining the current local calendar day only |

Upstream pages for recommendations, search, videos and parts, series, live streams, favorites, and history remain. API availability still depends on account permissions, region, platform restrictions, and server-side changes.

Historical `fvp` / libmdk adapters and dependencies remain in the source and some build artifacts, but **they are not the default video playback backend**. Their decoder configuration, texture limits, and 1–4 second buffer settings do not describe the current JS backend.

## Logs

`log.txt` is written beside `piliplus.exe`:

- Restarts on the same day preserve existing records from that day.
- Startup filters out other dates. The first write after midnight clears the previous day's records.
- `log.txt.previous` is no longer retained; an old rotation file is deleted on startup.
- At approximately 5 MB, the current log is cleared before writing continues. This is not an unlimited daily archive.
- Common URLs, authentication headers, and credentials are redacted. Inspect logs yourself before sharing them.

An unwritable program directory does not stop playback, but logging does not automatically move elsewhere. Save relevant logs before a date change or size limit removes them.

## Troubleshooting and limitations

**HTTP 501 / `Proxy failed to establish tunnel`:** the inherited proxy may not support HTTPS CONNECT. Check `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and application proxy settings. If failure occurs only when launching from a development terminal, try launching from File Explorer or removing the incorrect proxy for that launch process. Do not disable a required system proxy indiscriminately.

**Audio without video or windows covering desktop icons:** WebView2's native window layout, resizing, and fullscreen behavior require runtime verification. Version `v2.1.6.9` changes the player layout, but final rendering and click boundaries have **not been manually verified**. Advancing playback timestamps alone do not prove that video is visible.

Report the application version, Windows and WebView2 versions, window size, display scale, fullscreen state, and relevant daily log. Exit other instances before testing.

The JS backend currently has no player screenshot implementation. Legacy native decoder properties, rotation, and buffer-range APIs are not fully mapped to JS. Screenshot support, all hardware-decoding toggles, crop/zoom modes, and audio-only playback must not be assumed to work simply because the upstream UI exposes them.

## Build from source

Required: **Flutter 3.47.8 / Dart 3.13.7**, Visual Studio 2022 or Build Tools with desktop C++ components, Windows SDK, Git, and NuGet. Apply the bundled Flutter and `material_ui` patches after resolving dependencies.

See [README.windows.md](README.windows.md) for build commands, version metadata, packaging, and proxy troubleshooting. It uses configurable example paths rather than requiring a particular drive layout.

## Release validation

Local validation for `v2.1.6.9`:

- Windows x64 Release build succeeded.
- 14 embedded-player JavaScript regression tests passed.
- 58 Flutter tests passed; one real native-media test was skipped because no sample was supplied.
- All 72 files in the portable ZIP were verified against the build output. Uploaded release assets were downloaded and verified with SHA-256.

These results do not guarantee every online stream, audio/video sync, or hardware performance. The release includes `BUILD-INFO.txt` and `SHA256SUMS.txt`.

## Feedback and contributions

Use [Issues](https://github.com/qq422162318/PiliPlus-main/issues) for reproducible reports. Do not publish cookies, access tokens, signed media URLs, or account databases.

Contributions focused on Windows playback, layout, and reliability are welcome. State reproduction steps and validation limits; build success is not a substitute for playback testing.

## License and acknowledgements

Licensed under [GNU GPL v3](LICENSE). Third-party dependencies have their own licenses. Comply with applicable laws and platform terms. This project does not provide membership cracking or bypass content permissions.

Thanks to [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus), [PiliPala](https://github.com/guozhigq/pilipala), [PiliPalaX](https://github.com/orz12/PiliPalaX), [Flutter](https://github.com/flutter/flutter), [DASH.js](https://github.com/Dash-Industry-Forum/dash.js), [HLS.js](https://github.com/video-dev/hls.js), [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview), [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect), [Dio](https://pub.dev/packages/dio), and other dependency projects and contributors.
