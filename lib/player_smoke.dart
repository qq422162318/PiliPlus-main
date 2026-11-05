import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PiliPlus/main.dart' as application;
import 'package:PiliPlus/pages/video/view.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:PiliPlus/plugin/pl_player/fvp_adapter.dart';
import 'package:PiliPlus/plugin/pl_player/fvp_video.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dart:ui' as ui;

import 'package:fvp/mdk.dart' as mdk;

Future<void> main() async {
  if (Platform.environment['PLAYER_SMOKE_APP'] == '1') {
    final file = File('${Directory.systemTemp.path}/piliplus-app-view.log');
    void recordApp(String message) => file.writeAsStringSync(
      '${DateTime.now()} $message\n',
      mode: FileMode.append,
    );
    var routed = false;
    var requestedPlay = false;
    var captures = 0;
    Future<void> capture(RenderRepaintBoundary boundary, int index) async {
      try {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes != null) {
          final path =
              '${Directory.systemTemp.path}/piliplus-video-frame-$index.png';
          await File(path).writeAsBytes(bytes.buffer.asUint8List());
          recordApp('VIDEO CAPTURE $path');
        }
      } catch (error) {
        recordApp('VIDEO CAPTURE ERROR $error');
      }
    }

    runZonedGuarded(application.main, (error, stack) {
      recordApp('APP ERROR $error\n$stack');
    });
    FlutterError.onError = (details) {
      recordApp('FLUTTER ERROR ${details.exception}\n${details.stack}');
    };
    Timer.periodic(const Duration(seconds: 2), (_) {
      if (!routed && Get.key.currentState != null) {
        routed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          recordApp('NAVIGATE to video');
          PageUtils.toVideoPage(
            bvid: Platform.environment['PLAYER_SMOKE_BVID'] ?? 'BV1GJ411x7h7',
            cid:
                int.tryParse(Platform.environment['PLAYER_SMOKE_CID'] ?? '') ??
                137649199,
          );
        });
        WidgetsBinding.instance.scheduleFrame();
      }
      var textures = 0;
      var videos = 0;
      var players = 0;
      final lines = <String>[];
      void visit(Element element) {
        final widget = element.widget;
        if (widget is Texture) textures++;
        if (widget is VideoDetailPageV && element is StatefulElement) {
          final dynamic page = element.state;
          final dynamic controller = page.videoDetailController;
          lines.add(
            'VideoPage autoPlay=${controller.autoPlay} videoState=${controller.videoState.value} querying=${controller.isQuerying} hasVideo=${controller.videoUrl != null} hasAudio=${controller.audioUrl != null} status=${controller.plPlayerController.dataStatus.value}',
          );
          if (!requestedPlay &&
              controller.videoUrl != null &&
              !controller.isQuerying) {
            requestedPlay = true;
            for (final kind in ['video', 'audio']) {
              final String? source = kind == 'video'
                  ? controller.videoUrl
                  : controller.audioUrl;
              final uri = Uri.tryParse(source ?? '');
              recordApp(
                'SOURCE $kind scheme=${uri?.scheme} host=${uri?.host} '
                'length=${source?.length ?? 0} '
                'cdn=${controller.firstVideo?.codecs}',
              );
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              recordApp('CLICK play via page.handlePlay');
              page.handlePlay();
            });
            WidgetsBinding.instance.scheduleFrame();
          }
        }
        if (widget is Text && widget.data != null && lines.length < 35) {
          lines.add('TEXT ${widget.data}');
        }
        if (widget is FvpVideo) {
          videos++;
          if (widget.controller.state.position.inSeconds >= 3 && captures < 3) {
            RenderRepaintBoundary? boundary;
            element.visitAncestorElements((ancestor) {
              final render = ancestor.findRenderObject();
              if (render is RenderRepaintBoundary) {
                boundary = render;
                return false;
              }
              return true;
            });
            if (boundary != null && !boundary!.debugNeedsPaint) {
              captures++;
              unawaited(capture(boundary!, captures));
            }
          }
          lines.add(
            'FvpVideo size=${element.size} videoSize=${widget.controller.videoSize.value} texture=${widget.controller.textureId.value}',
          );
        }
        if (widget is PLVideoPlayer) {
          players++;
          final controller = widget.plPlayerController;
          final player = controller.videoPlayerController;
          lines.add(
            'PLVideoPlayer onlyAudio=${controller.onlyPlayAudio.value} status=${controller.dataStatus.value} size=${element.size} texture=${player?.textureId.value} video=${player?.videoSize.value} playing=${player?.state.playing} position=${player?.state.position}',
          );
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      file.writeAsStringSync(
        '${DateTime.now()} players=$players videos=$videos textures=$textures\n${lines.join('\n')}\n',
        mode: FileMode.append,
      );
    });
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final log = File('${Directory.systemTemp.path}/piliplus-player-smoke.log');
  log.writeAsStringSync('');
  void record(String message) {
    final line = '${DateTime.now().toIso8601String()} $message';
    log.writeAsStringSync('$line\n', mode: FileMode.append);
    debugPrint(line);
  }

  mdk.setGlobalOption('logLevel', mdk.LogLevel.debug);
  mdk.setLogHandler((level, message) {
    // Keep signed media URLs and verbose native dumps out of diagnostic output.
    final lower = message.toLowerCase();
    if (message.contains('://') ||
        lower.contains('license') ||
        lower.contains('mdk_key')) {
      return;
    }
    log.writeAsStringSync(
      '${DateTime.now().toIso8601String()} MDK $level: $message\n',
      mode: FileMode.append,
    );
  });
  final player = FvpPlayer();
  final decoder = Platform.environment['PLAYER_SMOKE_DECODER'];
  await player.init(
    videoDecoders: decoder == null
        ? const ['D3D11', 'MFT:d3d=11', 'DXVA']
        : [decoder],
  );
  final videoKey = GlobalKey();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: videoKey,
          child: SizedBox.expand(
            child: FittedBox(child: FvpVideo(controller: player)),
          ),
        ),
      ),
    ),
  );
  Future<void> saveImage(ui.Image image, String name) async {
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        await File('${Directory.systemTemp.path}/$name.png')
            .writeAsBytes(bytes.buffer.asUint8List());
      }
    } finally {
      image.dispose();
    }
  }

  try {
    const localMedia = String.fromEnvironment('PLAYER_SMOKE_MEDIA');
    var media = Platform.environment['PLAYER_SMOKE_MEDIA'] ?? localMedia;
    String? audio;
    final fixturePath = Platform.environment['PLAYER_SMOKE_FIXTURE'];
    if (fixturePath != null) {
      final fixture = jsonDecode(
        File(fixturePath).readAsStringSync().replaceFirst('﻿', ''),
      ) as Map<String, dynamic>;
      media = fixture['video'] as String;
      if (Platform.environment['PLAYER_SMOKE_VIDEO_ONLY'] != '1') {
        audio = fixture['audio'] as String?;
      }
      record('DASH codec=${fixture['codec']} audio=${audio != null}');
      player.setMediaHeader(
        userAgent: 'Mozilla/5.0',
        referer: 'https://www.bilibili.com/',
      );
    }
    if (Platform.environment['PLAYER_SMOKE_SHADER_RESOURCE'] == '0') {
      player.setProperty('video.decoder', 'shader_resource=0');
    }
    final startMs =
        int.tryParse(Platform.environment['PLAYER_SMOKE_START_MS'] ?? '') ?? 0;
    final steadyClock =
        Platform.environment['PLAYER_SMOKE_STEADY_CLOCK'] == '1';
    if (steadyClock) player.setProperty('avsync.audio', 'false');
    record(
      'Opening fixture; externalAudio=${audio != null} '
      'startMs=$startMs steadyClock=$steadyClock',
    );
    await player.open(
      media,
      audioUrl: audio,
      start: Duration(milliseconds: startMs),
      play: false,
    );
    record(
      'OPEN OK size=${player.videoSize.value} texture=${player.textureId.value} '
      'videos=${player.raw.mediaInfo.video?.length}',
    );
    await player.play();
    final positionSubscription = player.stream.position.listen((position) {
      record('PROGRESS positionMs=${position.inMilliseconds}');
    });
    final label = Platform.environment['PLAYER_SMOKE_LABEL'] ?? 'baseline';
    final captureInterval =
        int.tryParse(
          Platform.environment['PLAYER_SMOKE_CAPTURE_SECONDS'] ?? '',
        ) ??
        3;
    try {
      for (var i = 1; i <= 3; i++) {
        await Future<void>.delayed(Duration(seconds: captureInterval));
        await WidgetsBinding.instance.endOfFrame;
        final render = videoKey.currentContext?.findRenderObject();
        if (render is RenderRepaintBoundary) {
          await saveImage(
            await render.toImage(pixelRatio: 1),
            'piliplus-$label-flutter-$i',
          );
        }
        final nativeImage = await player.screenshot();
        if (nativeImage != null) {
          await saveImage(nativeImage, 'piliplus-$label-native-$i');
        }
        record(
          'CAPTURE $label/$i position=${player.state.position} '
          'playing=${player.state.playing}',
        );
      }
    } finally {
      await positionSubscription.cancel();
    }
  } catch (error, stack) {
    record('OPEN FAILED: $error\n$stack');
  }
}
