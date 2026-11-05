import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// 播放器后端抽象。
///
/// 现有实现：
///   - `FvpPlayer`（`fvp_adapter.dart`）：libmdk / fvp 原生后端，纹理渲染。
///   - `JsWebPlayer`（`js_web_player.dart`）：WebView + JS 播放器后端，整块 WebView 渲染。
///
/// [PlPlayerController] 只通过本接口使用播放器，因此切换后端不需要改动控制器逻辑。
/// 所有实现必须遵守 `FvpPlayerState` / `FvpPlayerStreams` 的语义（音量 0–100、
/// position/buffer 为 Duration、playing 表示真正在播放等），
/// 否则控制器的心跳、重试和进度逻辑会失真。
abstract class PlayerBackend {
  /// 当前状态快照。读取不应有副作用。
  PlayerBackendState get state;

  /// 事件流。
  PlayerBackendStreams get stream;

  /// 视频尺寸。为 null 表示尚未确定。
  ValueNotifier<ui.Size?> get videoSize;

  /// 纹理 id（仅原生后端支持）。WebView 后端恒为 null。
  ValueNotifier<int?> get textureId;

  /// 是否支持纹理渲染。`FvpVideo` 只对接返回 true 的后端。
  bool get supportsTexture;

  Future<void> init({
    List<String> videoDecoders = const ['FFmpeg'],
    Map<String, String> properties = const {},
  });

  Future<void> open(
    String url, {
    String? audioUrl,
    Duration? start,
    bool play = false,
    bool expectVideo = true,
    Map<String, String> properties = const {},
  });

  void setMediaHeader({String? userAgent, String? referer});

  void setProperty(String name, String value);

  String? getProperty(String name);

  void setBufferRange({int min = 1000, int max = 10000, bool drop = false});

  void setRotate(int degree);

  Future<void> play();

  Future<void> pause();

  Future<void> playOrPause();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setVolume(double volume);

  Future<ui.Image?> screenshot();

  Future<void> reload();

  Future<void> dispose();
}

/// 后端状态快照。字段可读写，便于各后端直接更新自身状态。
abstract class PlayerBackendState {
  bool playing = false;
  bool completed = false;
  bool buffering = false;
  Duration duration = Duration.zero;
  Duration position = Duration.zero;
  Duration buffer = Duration.zero;
  double rate = 1;
  double volume = 100;
  int width = 0;
  int height = 0;
}

/// 后端事件流集合。
///
/// 各后端通过继承本类获得 [emitXxx] 分发方法，不必自己管理 controller 生命周期，
/// 也避免 `implements` 导致私有成员不可见的问题。
abstract class PlayerBackendStreams {
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _error = StreamController<String>.broadcast();

  Stream<bool> get playing => _playing.stream;
  Stream<bool> get completed => _completed.stream;
  Stream<Duration> get position => _position.stream;
  Stream<Duration> get duration => _duration.stream;
  Stream<Duration> get buffer => _buffer.stream;
  Stream<bool> get buffering => _buffering.stream;
  Stream<String> get error => _error.stream;

  void emitPlaying(bool value) => _playing.add(value);
  void emitCompleted(bool value) => _completed.add(value);
  void emitPosition(Duration value) => _position.add(value);
  void emitDuration(Duration value) => _duration.add(value);
  void emitBuffer(Duration value) => _buffer.add(value);
  void emitBuffering(bool value) => _buffering.add(value);
  void emitError(String value) => _error.add(value);

  Future<void> dispose() => Future.wait([
    _playing.close(),
    _completed.close(),
    _position.close(),
    _duration.close(),
    _buffer.close(),
    _buffering.close(),
    _error.close(),
  ]);
}
