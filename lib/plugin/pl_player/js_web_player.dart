import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/plugin/pl_player/player_backend.dart';
import 'package:PiliPlus/services/runtime_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// WebView backend hosting DASH.js.
///
/// The page is served by [JsWebVideo] through the WebView's request
/// interception, so it keeps a `bilibili.com` origin. That origin is what
/// makes the browser attach Bilibili's own `Referer` to media segment
/// requests, which is what Bilibili's CDN requires.
///
/// DASH.js is bundled as an asset ([dashJsAsset]) rather than fetched from a
/// CDN, so playback does not depend on a third party being reachable.
class JsWebPlayer implements PlayerBackend {
  /// Virtual page URL. Only used as the interception key, never navigated to.
  static const playerPageUrl =
      '${HttpString.baseUrl}/blackboard/html5player.html';

  /// Bundled dash.js (v5.2.1 UMD build, `dash.mediaplayer.min.js`).
  ///
  /// 只带 MediaPlayer / MSE / 事件 / 设置这部分，不含 DRM 与 metrics
  /// reporting。完整 `dash.all.min.js` 会多出 70KB 库代码和对应的解析/常驻
  /// 内存，而这个页面用不到 DRM 与上报。
  static const dashJsAsset = 'assets/js/dash.mediaplayer.min.js';

  /// hls.js，用于直播流。B 站直播接口给的 `http_hls` 实际是 fmp4 分片，
  /// 网页端只能靠 hls.js 走 MSE 解（原生 `<video>` 既不支持 FLV 也不支持 HLS）。
  static const hlsJsAsset = 'assets/js/hls.min.js';

  /// Origin Bilibili's CDN expects for segment requests.
  static const referer = HttpString.baseUrl;

  final _state = _BackendState();
  final _streams = _BackendStreams();

  @override
  final ValueNotifier<ui.Size?> videoSize = ValueNotifier(null);

  @override
  final ValueNotifier<int?> textureId = ValueNotifier(null);

  @override
  bool get supportsTexture => false;

  @override
  PlayerBackendState get state => _state;

  @override
  PlayerBackendStreams get stream => _streams;

  InAppWebViewController? _webViewController;
  bool _disposed = false;
  bool _pageReady = false;
  String _url = '';
  String? _audioUrl;
  bool _pendingPlay = false;
  String _userAgent = '';
  double _volume = 1;
  double _rate = 1;
  Duration? _start;
  double? _duration;
  Map<String, dynamic>? _videoTrack;
  Map<String, dynamic>? _audioTrack;
  final List<String> _queued = [];

  String get userAgent => _userAgent;

  void reportPageReady() {
    if (_disposed) {
      return;
    }
    _pageReady = true;
    RuntimeLog.info('DASH.js player page ready');
    // open 必须先于队列到达页面：队列里那条 play 是在页面还没就绪时发的，
    // 如果先 flush，它会打在一个还没有 videoPlayer 的页面上，静默丢掉，
    // 用户就会遇到“点一次播放没反应，必须再点一次”。
    _applyOpen();
    _flushQueued();
  }

  /// 页面还没就绪时把命令攒起来，等 [reportPageReady] 后按顺序补发。
  void _send(String js) {
    final brief = js.length > 96 ? '${js.substring(0, 96)}…' : js;
    if (!_pageReady) {
      _queued.add(js);
      RuntimeLog.info('DASH.js queued $brief');
      return;
    }
    RuntimeLog.info('DASH.js send $brief');
    unawaited(evaluateJavascript(js));
  }

  void _flushQueued() {
    if (_queued.isEmpty) return;
    final pending = List<String>.of(_queued);
    _queued.clear();
    RuntimeLog.info('DASH.js flushing queued commands count=${pending.length}');
    for (final js in pending) {
      unawaited(evaluateJavascript(js));
    }
  }

  /// 由 [JsWebVideo] 注入，执行页面脚本。
  Future<void> evaluateJavascript(String source) async {
    final webViewController = _webViewController;
    if (webViewController == null) {
      RuntimeLog.error(
        'DASH.js evaluate dropped',
        StateError('WebView controller not attached'),
      );
      return;
    }
    try {
      await webViewController.evaluateJavascript(source: source);
    } catch (error) {
      RuntimeLog.error('DASH.js evaluate failed', error);
    }
  }

  /// 由 [JsWebVideo] 在 `onWebViewCreated` 里注入。
  void attachWebView(InAppWebViewController controller) {
    _webViewController = controller;
    RuntimeLog.info('DASH.js WebView attached');
  }

  void _applyOpen() {
    if (!_pageReady || _url.isEmpty) return;
    final json = jsonEncode({
      'video': _url,
      'audio': _audioUrl,
      'start': _start?.inMilliseconds ?? 0,
      'autoplay': _pendingPlay,
      'volume': _volume,
      'rate': _rate,
      'duration': _duration,
      'videoTrack': _videoTrack,
      'audioTrack': _audioTrack,
    });
    _send('window.__dashOpen && window.__dashOpen($json);');
    RuntimeLog.info(
      'DASH.js open sent videoHost=${Uri.tryParse(_url)?.host ?? 'invalid'} '
      'externalAudio=${_audioUrl?.isNotEmpty ?? false} '
      'videoSegmentBase=${_hasSegmentBase(_videoTrack)} '
      'audioSegmentBase=${_hasSegmentBase(_audioTrack)}',
    );
  }

  void handleMessage(String channel, dynamic args) {
    if (_disposed) {
      return;
    }
    final payload = args is String ? args : jsonEncode(args);
    if (channel == 'error') {
      RuntimeLog.error('DASH.js playback error', payload);
      _streams.emitError(payload);
      return;
    }
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;
      data = decoded;
    } catch (_) {
      return;
    }
    switch (channel) {
      case 'ready':
        reportPageReady();
      case 'meta':
        final w = (data['width'] as num?)?.toInt() ?? 0;
        final h = (data['height'] as num?)?.toInt() ?? 0;
        final d = (data['duration'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) {
          _state.width = w;
          _state.height = h;
          videoSize.value = ui.Size(w.toDouble(), h.toDouble());
        }
        if (d > 0) {
          _state.duration = Duration(milliseconds: (d * 1000).round());
          _streams.emitDuration(_state.duration);
        }
      case 'state':
        final playing = data['playing'] == true;
        final buffering = data['buffering'] == true;
        if (playing != _state.playing) {
          _state.playing = playing;
          _streams.emitPlaying(playing);
        }
        if (buffering != _state.buffering) {
          _state.buffering = buffering;
          _streams.emitBuffering(buffering);
        }
      case 'time':
        _state.position = Duration(
          milliseconds: (((data['time'] as num?)?.toDouble() ?? 0) * 1000)
              .round(),
        );
        _state.buffer = Duration(
          milliseconds: (((data['buffer'] as num?)?.toDouble() ?? 0) * 1000)
              .round(),
        );
        if (_state.duration == Duration.zero && data['duration'] is num) {
          _state.duration = Duration(
            milliseconds: ((data['duration'] as num).toDouble() * 1000).round(),
          );
          _streams.emitDuration(_state.duration);
        }
        _streams.emitPosition(_state.position);
        _streams.emitBuffer(_state.buffer);
      case 'ended':
        _state.completed = true;
        _streams.emitCompleted(true);
    }
  }

  @override
  Future<void> init({
    List<String> videoDecoders = const ['FFmpeg'],
    Map<String, String> properties = const {},
  }) async {}

  @override
  Future<void> open(
    String url, {
    String? audioUrl,
    Duration? start,
    bool play = false,
    bool expectVideo = true,
    Map<String, String> properties = const {},
  }) async {
    _url = url;
    _audioUrl = audioUrl;
    _pendingPlay = play;
    _start = start;
    _videoTrack = _decodeTrack(properties['videoTrack']);
    _audioTrack = _decodeTrack(properties['audioTrack']);
    _duration = double.tryParse(properties['duration'] ?? '');
    _state.completed = false;
    _applyOpen();
  }

  /// 接口同时发 `SegmentBase/Initialization/indexRange` 与
  /// `segment_base/initialization/index_range` 两套键，两个范围都得在才算完整。
  bool _hasSegmentBase(Map<String, dynamic>? track) {
    if (track == null) return false;
    final segment = track['segmentBase'] ?? track['SegmentBase'];
    if (segment is! Map) return false;
    final init =
        segment['Initialization'] ??
        segment['initialization'] ??
        segment['InitializationRange'];
    final index =
        segment['indexRange'] ??
        segment['IndexRange'] ??
        segment['index_range'];
    final initRange = init is Map ? (init['range'] ?? init) : init;
    final indexRange = index is Map ? (index['range'] ?? index) : index;
    return '$initRange'.isNotEmpty && '$indexRange'.isNotEmpty;
  }

  Map<String, dynamic>? _decodeTrack(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (error) {
      RuntimeLog.error('DASH.js track metadata decode failed', error);
      return null;
    }
  }

  @override
  void setMediaHeader({String? userAgent, String? referer}) {
    _userAgent = userAgent ?? '';
  }

  @override
  void setProperty(String name, String value) {}

  @override
  String? getProperty(String name) => null;

  @override
  void setBufferRange({int min = 1000, int max = 10000, bool drop = false}) {}

  @override
  void setRotate(int degree) {}

  @override
  Future<void> play() async {
    _state.completed = false;
    _pendingPlay = true;
    _send('window.__dashCommand && window.__dashCommand({type:"play"});');
  }

  @override
  Future<void> pause() async {
    _pendingPlay = false;
    _send('window.__dashCommand && window.__dashCommand({type:"pause"});');
  }

  @override
  Future<void> playOrPause() async =>
      _send('window.__dashCommand && window.__dashCommand({type:"toggle"});');

  @override
  Future<void> seek(Duration position) async => _send(
    'window.__dashCommand && window.__dashCommand({type:"seek", time:${position.inMilliseconds / 1000}});',
  );

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
    _state.rate = rate;
    _send(
      'window.__dashCommand && window.__dashCommand({type:"rate", rate:$rate});',
    );
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume / 100;
    _state.volume = volume;
    _send(
      'window.__dashCommand && window.__dashCommand({type:"volume", volume:$_volume});',
    );
  }

  @override
  Future<ui.Image?> screenshot() async => null;

  @override
  Future<void> reload() async {
    if (_url.isNotEmpty) _applyOpen();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _pageReady = false;
    _webViewController = null;
    _queued.clear();
    await _streams.dispose();
    videoSize.dispose();
    textureId.dispose();
  }
}

class _BackendState extends PlayerBackendState {}

class _BackendStreams extends PlayerBackendStreams {}
