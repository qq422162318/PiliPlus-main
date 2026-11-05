import 'dart:async';
import 'dart:math' show max, min;
import 'dart:ui' as ui;

import 'package:PiliPlus/plugin/pl_player/fvp_media_ready.dart';
import 'package:PiliPlus/plugin/pl_player/player_backend.dart';
import 'package:PiliPlus/services/runtime_log.dart';
import 'package:flutter/foundation.dart';
import 'package:fvp/mdk.dart' as mdk;

/// 原生后端的状态快照。字段全部继承自 [PlayerBackendState]。
class FvpPlayerState extends PlayerBackendState {}

/// 原生后端的事件流集合。行为全部继承自 [PlayerBackendStreams]。
class FvpPlayerStreams extends PlayerBackendStreams {}

/// Windows 播放后端。对外保留旧播放器的 0–100 音量单位。
class FvpPlayer implements PlayerBackend {
  @override
  final state = FvpPlayerState();
  @override
  final stream = FvpPlayerStreams();
  @override
  final videoSize = ValueNotifier<ui.Size?>(null);
  @override
  final textureId = ValueNotifier<int?>(null);

  /// 原生后端支持纹理渲染。
  @override
  bool get supportsTexture => true;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  mdk.Player? _native;
  mdk.Player get raw => _native!;

  List<String> _videoDecoders = const ['MFT:d3d=11', 'D3D11', 'DXVA'];
  final Map<String, String> _properties = {};
  Timer? _positionTimer;
  DateTime? _lastPositionLog;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  bool _opening = false;
  bool _prepared = false;
  String _url = '';
  String? _audioUrl;
  bool _expectVideo = true;
  int _rotation = 0;
  int _bufferMin = 1000;
  int _bufferMax = 10000;
  bool _bufferDrop = false;

  static Future<FvpPlayer> create() async {
    final player = FvpPlayer();
    await player.init();
    return player;
  }

  @override
  Future<void> init({
    List<String> videoDecoders = const ['FFmpeg'],
    Map<String, String> properties = const {},
  }) async {
    _videoDecoders = videoDecoders;
    _properties.addAll(properties);
    // 延迟分配原生播放器，未打开媒体的实例不占用纹理或解码资源。
  }

  void _initializeNative() {
    if (_native != null) return;
    if (RuntimeLog.enabled) {
      mdk.setGlobalOption(
        'd3d11.sync.cpu',
        1,
      );
      mdk.setLogHandler((level, message) {
        final lower = message.toLowerCase();
        if (lower.contains('license') || lower.contains('mdk_key')) return;
        RuntimeLog.warning('MDK $level: $message');
      });
    }
    RuntimeLog.info('Player allocate decoders=$_videoDecoders');
    final player = _native = mdk.Player();
    player.textureId.addListener(_updateTextureId);
    player.setBufferRange(min: _bufferMin, max: _bufferMax, drop: _bufferDrop);
    player
      ..setDecoders(mdk.MediaType.video, _videoDecoders)
      ..setProperty('subtitle', '0')
      ..setActiveTracks(mdk.MediaType.subtitle, const [])
      ..setProperty('demux.buffer.ranges', '0')
      ..setProperty('video.decoder', 'shader_resource=0');
    for (final property in _properties.entries) {
      player.setProperty(property.key, property.value);
    }
    player
      ..volume = state.volume / 100
      ..playbackRate = state.rate;

    _subscriptions.add(
      player.onStateChanged.listen((event) {
        if (_disposed || _opening) return;
        _setPlaying(event.newValue == mdk.PlaybackState.playing);
        if (event.newValue == mdk.PlaybackState.stopped && _prepared) {
          _tickPosition();
          if (player.mediaStatus.test(mdk.MediaStatus.end) ||
              (state.duration > Duration.zero &&
                  state.duration - state.position <=
                      const Duration(seconds: 1))) {
            _setCompleted(true);
          }
        }
      }),
    );
    _subscriptions.add(
      player.onMediaStatus.listen((event) {
        if (_disposed) return;
        final status = event.newValue;
        RuntimeLog.info('Player media status=$status opening=$_opening');
        if (status.test(mdk.MediaStatus.loaded)) _updateMediaInfo();
        if (_opening) return;
        _setBuffering(
          status.test(mdk.MediaStatus.buffering) ||
              status.test(mdk.MediaStatus.stalled),
        );
        if (!_opening && status.test(mdk.MediaStatus.end)) {
          _tickPosition();
          _setPlaying(false);
          _setCompleted(true);
        }
      }),
    );
    _subscriptions.add(
      player.onEvent.listen((event) {
        if (_disposed) return;
        if (event.category == 'decoder.video') {
          RuntimeLog.info(
            'Video decoder: ${event.detail} track=${event.error}',
          );
        }
        if (event.category == 'reader.buffering') {
          // error 字段在此事件中实际是百分比，不是错误码。
          _updateBuffer();
        } else if (event.error < 0) {
          RuntimeLog.warning(
            'Player event ${event.category}: ${event.detail} (${event.error})',
          );
          stream.emitError(
            '${event.category}: ${event.detail} (${event.error})',
          );
        }
      }),
    );
  }

  void _updateTextureId() {
    if (!_disposed) textureId.value = _native?.textureId.value;
  }

  void _updateMediaInfo() {
    final info = raw.mediaInfo;
    final duration = Duration(milliseconds: max(0, info.duration));
    if (duration != state.duration) {
      state.duration = duration;
      stream.emitDuration(duration);
    }
    final videos = info.video;
    if (videos != null && videos.isNotEmpty) {
      state.width = videos.first.codec.width;
      state.height = videos.first.codec.height;
    }
  }

  void _setPlaying(bool playing) {
    if (state.playing == playing) return;
    state.playing = playing;
    RuntimeLog.info(
      'Player playing=$playing positionMs=${state.position.inMilliseconds}',
    );
    stream.emitPlaying(playing);
    _positionTimer?.cancel();
    _positionTimer = null;
    if (playing) {
      _positionTimer = Timer.periodic(
        // 仅降低进度采样频率，视频帧仍由原生渲染回调驱动。
        const Duration(milliseconds: 500),
        (_) => _tickPosition(),
      );
    }
  }

  void _setCompleted(bool completed) {
    if (state.completed == completed) return;
    state.completed = completed;
    stream.emitCompleted(completed);
  }

  void _setBuffering(bool buffering) {
    if (state.buffering == buffering) return;
    state.buffering = buffering;
    RuntimeLog.info('Player buffering=$buffering');
    stream.emitBuffering(buffering);
  }

  void _tickPosition() {
    if (_disposed || !_prepared || _opening) return;
    final position = Duration(milliseconds: max(0, raw.position));
    if (state.position != position) {
      state.position = position;
      stream.emitPosition(position);
    }
    _updateBuffer();
    if (RuntimeLog.enabled) {
      final now = DateTime.now();
      if (_lastPositionLog == null ||
          now.difference(_lastPositionLog!) >= const Duration(seconds: 5)) {
        _lastPositionLog = now;
        RuntimeLog.info(
          'Player progressMs=${state.position.inMilliseconds} '
          'bufferMs=${state.buffer.inMilliseconds} playing=${state.playing} '
          'video=${state.width}x${state.height} texture=${textureId.value}',
        );
      }
    }
  }

  void _updateBuffer() {
    if (_disposed || !_prepared || _opening) return;
    final buffer =
        state.position + Duration(milliseconds: max(0, raw.buffered()));
    final end = state.duration > Duration.zero && buffer > state.duration
        ? state.duration
        : buffer;
    if (state.buffer != end) {
      state.buffer = end;
      stream.emitBuffer(end);
    }
  }

  @override
  Future<void> open(
    String url, {
    String? audioUrl,
    Duration? start,
    bool play = true,
    bool expectVideo = true,
    Map<String, String> properties = const {},
  }) {
    final operation = _pending.then(
      (_) => _open(
        url,
        audioUrl: audioUrl,
        start: start,
        play: play,
        expectVideo: expectVideo,
        properties: properties,
      ),
    );
    // 单次失败不能阻塞后续换集/换画质。
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _open(
    String url, {
    String? audioUrl,
    Duration? start,
    required bool play,
    required bool expectVideo,
    required Map<String, String> properties,
  }) async {
    if (_disposed) throw StateError('播放器已释放');
    RuntimeLog.info(
      'Player open source=${url.startsWith('http') ? 'network' : 'local'} '
      'externalAudio=${audioUrl?.isNotEmpty ?? false} '
      'startMs=${start?.inMilliseconds ?? 0} autoplay=$play expectVideo=$expectVideo',
    );
    _lastPositionLog = null;
    _initializeNative();
    _opening = true;
    _prepared = false;
    _setPlaying(false);
    _setCompleted(false);
    _setBuffering(true);
    videoSize.value = null;
    state.width = state.height = 0;
    state.duration = state.position = state.buffer = Duration.zero;
    _url = url;
    _audioUrl = audioUrl;
    _expectVideo = expectVideo;
    for (final property in properties.entries) {
      setProperty(property.key, property.value);
    }
    try {
      raw.state = mdk.PlaybackState.stopped;
      // Always change the media value so fvp resets its texture-size future.
      if (raw.media == url) raw.media = '';
      raw.media = url;
      raw.setMedia(audioUrl ?? '', mdk.MediaType.audio);
      // Prepare from zero, then seek only after both DASH readers and the
      // video decoder are ready. Seeking the external audio reader during
      // startup can leave the main video clock at zero while the UI reports
      // the requested position.
      final position = await raw.prepare().timeout(const Duration(seconds: 30));
      if (_disposed) return;
      RuntimeLog.info(
        'Player prepare resultMs=$position streams=${raw.mediaInfo.streams} '
        'status=${raw.mediaStatus}',
      );
      final info = await waitForFvpMediaInfo(
        readMediaInfo: () => raw.mediaInfo,
        isLoaded: () => raw.mediaStatus.test(mdk.MediaStatus.loaded),
        changes: raw.onMediaStatus,
        expectVideo: expectVideo,
        prepareResult: position,
        externalAudio: audioUrl?.isNotEmpty ?? false,
      );
      if (_disposed) return;
      _updateMediaInfo();
      final videos = info.video;
      if (videos != null && videos.isNotEmpty) {
        if (videos.any((video) => video.codec.codec != 'h264')) {
          throw UnsupportedError('此 Windows 版本仅启用 AVC/H.264 视频');
        }
        final size = await raw.textureSize.timeout(const Duration(seconds: 10));
        if (size == null) throw StateError('无法获取视频尺寸');
        // 不放大小分辨率视频，较大视频的渲染纹理限制在 1080p 内。
        final scale = min(1.0, min(1920 / size.width, 1080 / size.height));
        final id = await raw
            .updateTexture(
              width: max(1, (size.width * scale).round()),
              height: max(1, (size.height * scale).round()),
            )
            .timeout(const Duration(seconds: 10));
        if (_disposed) return;
        if (id < 0) throw StateError('无法创建 D3D11 视频纹理');
        videoSize.value = size;
        raw.rotate(_rotation);
      } else if (raw.textureId.value != null) {
        await raw.updateTexture(width: -1).timeout(const Duration(seconds: 10));
        if (_disposed) return;
      }
      if (position < 0) {
        RuntimeLog.info(
          'Player recover waiting status=${raw.mediaStatus} state=${raw.state}',
        );
        await waitForFvpPreparation(
          readStatus: () => raw.mediaStatus,
          readState: () => raw.state,
          statusChanges: raw.onMediaStatus,
          stateChanges: raw.onStateChanged,
        );
        if (_disposed) return;
      }
      final startPosition = max(0, start?.inMilliseconds ?? 0);
      if (startPosition > 0) {
        RuntimeLog.info('Player startup seek targetMs=$startPosition');
        final seekResult = await raw
            .seek(position: startPosition)
            .timeout(const Duration(seconds: 15));
        if (_disposed) return;
        RuntimeLog.info('Player startup seek resultMs=$seekResult');
        if (seekResult < 0) {
          throw StateError('起播跳转失败 ($seekResult)');
        }
      }
      // prepare 已完成；等待原跳转结束，不叠加第二次 seek。
      final preparedPosition = startPosition > 0
          ? max(0, raw.position)
          : max(0, position);
      if (startPosition > 0) {
        RuntimeLog.info(
          'Player startup seek completed positionMs=$preparedPosition',
        );
      }
      RuntimeLog.info(
        'Player prepared videoTracks=${videos?.length ?? 0} '
        'video=${state.width}x${state.height} texture=${textureId.value} '
        'durationMs=${state.duration.inMilliseconds} rate=${state.rate} '
        'fps=${videos?.firstOrNull?.codec.frameRate ?? 0}',
      );
      _prepared = true;
      state.position = Duration(milliseconds: preparedPosition);
      stream.emitPosition(state.position);
      _setBuffering(false);
      _opening = false;
      raw.state = play ? mdk.PlaybackState.playing : mdk.PlaybackState.paused;
      _setPlaying(play);
      _updateBuffer();
    } catch (error, stack) {
      RuntimeLog.error('Player open failed', error, stack);
      if (!_disposed) {
        raw.state = mdk.PlaybackState.stopped;
        _setBuffering(false);
      }
      rethrow;
    } finally {
      _opening = false;
    }
  }

  @override
  void setMediaHeader({String? userAgent, String? referer}) {
    setProperty(
      'avio.headers',
      [
        if (referer != null) 'Referer: $referer\r\n',
        if (userAgent != null) 'User-Agent: $userAgent\r\n',
      ].join(),
    );
    if (userAgent != null) setProperty('avio.user_agent', userAgent);
  }

  @override
  void setProperty(String name, String value) {
    _properties[name] = value;
    _native?.setProperty(name, value);
  }

  @override
  String? getProperty(String name) =>
      _native?.getProperty(name) ?? _properties[name];

  @override
  void setBufferRange({int min = 1000, int max = 10000, bool drop = false}) {
    _bufferMin = min;
    _bufferMax = max;
    _bufferDrop = drop;
    _native?.setBufferRange(min: min, max: max, drop: drop);
  }

  @override
  void setRotate(int degree) {
    _rotation = degree;
    _native?.rotate(degree);
  }

  @override
  Future<void> play() async {
    if (_disposed || !_prepared) return;
    _setCompleted(false);
    raw.state = mdk.PlaybackState.playing;
    _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    if (_disposed || _native == null) return;
    _tickPosition();
    raw.state = mdk.PlaybackState.paused;
    _setPlaying(false);
  }

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    if (_disposed || !_prepared) return;
    RuntimeLog.info('Player seek targetMs=${position.inMilliseconds}');
    final result = await raw
        .seek(position: max(0, position.inMilliseconds))
        .timeout(const Duration(seconds: 15));
    if (_disposed) return;
    RuntimeLog.info('Player seek resultMs=$result');
    if (result < 0) throw StateError('跳转失败 ($result)');
    state.position = Duration(milliseconds: result);
    _setCompleted(false);
    stream.emitPosition(state.position);
    _updateBuffer();
  }

  @override
  Future<void> setRate(double rate) async {
    RuntimeLog.info('Player rate=$rate');
    state.rate = rate;
    if (_native != null) raw.playbackRate = rate;
  }

  @override
  Future<void> setVolume(double volume) async {
    state.volume = volume.clamp(0, 200).toDouble();
    if (_native != null) raw.volume = state.volume / 100;
  }

  @override
  Future<ui.Image?> screenshot() async {
    final size = videoSize.value;
    if (_disposed || !_prepared || size == null) return null;
    final width = size.width.round();
    final height = size.height.round();
    final bytes = await raw
        .snapshot(width: width, height: height)
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (bytes == null || bytes.isEmpty || _disposed) return null;
    final result = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      result.complete,
      rowBytes: bytes.length ~/ height,
    );
    return result.future;
  }

  @override
  Future<void> reload() => _url.isEmpty
      ? Future.value()
      : open(
          _url,
          audioUrl: _audioUrl,
          start: raw.isLive ? null : state.position,
          play: state.playing,
          expectVideo: _expectVideo,
        );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    RuntimeLog.info('Player dispose');
    _disposed = true;
    _positionTimer?.cancel();
    await _pending;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _native?.textureId.removeListener(_updateTextureId);
    textureId.value = null;
    // fvp 内部会先释放 Flutter 纹理，再销毁 MDK 实例。
    _native?.dispose();
    await stream.dispose();
    videoSize.dispose();
    textureId.dispose();
  }
}
