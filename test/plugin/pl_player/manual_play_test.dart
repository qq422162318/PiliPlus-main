import 'dart:io';

import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/view.dart';
import 'package:PiliPlus/plugin/pl_player/models/data_status.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

class _VideoController extends VideoDetailController {
  int initializations = 0;

  @override
  Future<void> playerInit({
    bool? autoplay,
    bool autoFullScreenFlag = false,
  }) async {
    expect(autoplay, isTrue);
    expect(autoFullScreenFlag, isTrue);
    initializations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-play-test-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    await GStorage.setting.put(SettingBoxKey.preInitPlayer, true);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> check({
    required bool videoReady,
    required int currentCid,
    required DataStatus status,
  }) async {
    final controller = _VideoController()
      ..cid = 2.obs
      ..isFileSource = false
      ..videoUrl = 'https://example.invalid/video'
      ..audioUrl = 'https://example.invalid/audio';
    controller.videoState.value = videoReady;
    controller.plPlayerController
      ..cid = currentCid
      ..dataStatus.value = status;
    Get.routing.args = {'heroTag': 'manual-play-test'};
    final dynamic page = const VideoDetailPageV().createState();
    page.videoDetailController = controller;
    try {
      await page.handlePlay();
      expect(controller.initializations, 1);
    } finally {
      controller.plPlayerController
        ..removeStatusLister(page.playerListener)
        ..removePositionListener(page.positionListener);
    }
  }

  test('skipped preinitialization cannot play the previous media', () async {
    await check(videoReady: false, currentCid: 1, status: DataStatus.loaded);
  });

  test(
    'a ready page cannot reuse another episode in the shared player',
    () async {
      await check(videoReady: true, currentCid: 1, status: DataStatus.loaded);
    },
  );

  test('failed preinitialization retries the current media', () async {
    await check(videoReady: true, currentCid: 2, status: DataStatus.error);
  });

  test('loaded status without a player still initializes the media', () async {
    await check(videoReady: true, currentCid: 2, status: DataStatus.loaded);
  });
}
