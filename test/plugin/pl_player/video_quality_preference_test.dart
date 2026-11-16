import 'dart:io';

import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// Test-only stub for the existing wakelock dependency; no native window is opened.
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

class _StubWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
}

class _VideoController extends VideoDetailController {
  int updates = 0;

  @override
  void updatePlayer() => updates++;
}

PlayUrlModel _streams({bool has1080p = true}) => PlayUrlModel.fromJson({
  'dash': {
    'video': [
      {'id': VideoQuality.high720.code, 'codecs': 'avc1.640028'},
      if (has1080p) {'id': VideoQuality.high1080.code, 'codecs': 'avc1.640028'},
    ],
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final originalWakelock = wakelockPlusPlatformInstance;

  setUpAll(() async {
    wakelockPlusPlatformInstance = _StubWakelock();
    directory = await Directory.systemTemp.createTemp('piliplus-quality-test-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.setting.put(SettingBoxKey.tempPlayerConf, false);
  });
  tearDown(() async {
    while (PlPlayerController.instance != null) {
      PlPlayerController.instance!.dispose();
    }
    await Future<void>.delayed(Duration.zero);
  });
  tearDownAll(() async {
    wakelockPlusPlatformInstance = originalWakelock;
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('desktop defaults to 1080p only when no preference is saved', () async {
    expect(Pref.defaultVideoQa, VideoQuality.high1080.code);
    await GStorage.setting.put(
      SettingBoxKey.defaultVideoQa,
      VideoQuality.high720.code,
    );
    expect(
      PlPlayerController.getInstance().cacheVideoQa,
      VideoQuality.high720.code,
    );
  });

  test(
    'manual desktop quality uses the preference playback restores',
    () async {
      await GStorage.setting.put(
        SettingBoxKey.defaultVideoQaCellular,
        VideoQuality.clear480.code,
      );
      final player = PlPlayerController.getInstance();
      await player.rememberVideoQuality(VideoQuality.high1080.code);
      expect(player.cacheVideoQa, VideoQuality.high1080.code);
      player.dispose();
      expect(
        PlPlayerController.getInstance().cacheVideoQa,
        VideoQuality.high1080.code,
      );
      expect(
        GStorage.setting.get(SettingBoxKey.defaultVideoQaCellular),
        VideoQuality.clear480.code,
      );
    },
  );

  test('a removed quality cannot replace the actual playback label', () {
    final controller = _VideoController()..data = _streams();
    controller.currentVideoQa.value = VideoQuality.high720;
    controller.data = _streams(has1080p: false);
    expect(controller.selectVideoQuality(VideoQuality.high1080), isFalse);
    expect(controller.currentVideoQa.value, VideoQuality.high720);
    expect(controller.updates, 0);
  });

  test(
    'a supported quality updates the actual label and playback together',
    () {
      final controller = _VideoController()..data = _streams();
      controller.currentVideoQa.value = VideoQuality.high720;
      expect(controller.selectVideoQuality(VideoQuality.high1080), isTrue);
      expect(controller.currentVideoQa.value, VideoQuality.high1080);
      expect(
        controller.plPlayerController.cacheVideoQa,
        VideoQuality.high1080.code,
      );
      expect(controller.updates, 1);
    },
  );

  test(
    'temporary quality changes do not overwrite the saved preference',
    () async {
      await GStorage.setting.put(
        SettingBoxKey.defaultVideoQa,
        VideoQuality.high720.code,
      );
      await GStorage.setting.put(SettingBoxKey.tempPlayerConf, true);
      final player = PlPlayerController.getInstance();
      await player.rememberVideoQuality(VideoQuality.high1080.code);
      expect(player.cacheVideoQa, VideoQuality.high1080.code);
      player.dispose();
      expect(
        PlPlayerController.getInstance().cacheVideoQa,
        VideoQuality.high720.code,
      );
    },
  );
}
