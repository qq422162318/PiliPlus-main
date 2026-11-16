import 'dart:io';

import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  test('Windows playback keeps danmaku and its interactions disabled', () {
    expect(Pref.enableShowDanmaku, isFalse);
    expect(Pref.enableShowLiveDanmaku, isFalse);
    expect(Pref.enableTapDm, isFalse);
    expect(Pref.showDmChart, isFalse);
  });

  test('legacy enabled settings cannot reactivate danmaku', () async {
    final tempDir = await Directory.systemTemp.createTemp('piliplus-dm-test-');
    addTearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });
    Hive.init(tempDir.path);
    GStorage.setting = await Hive.openBox('setting');
    await GStorage.setting.putAll({
      SettingBoxKey.enableShowDanmaku: true,
      SettingBoxKey.enableShowLiveDanmaku: true,
      SettingBoxKey.enableTapDm: true,
      SettingBoxKey.showDmChart: true,
    });

    expect(Pref.enableShowDanmaku, isFalse);
    expect(Pref.enableShowLiveDanmaku, isFalse);
    expect(Pref.enableTapDm, isFalse);
    expect(Pref.showDmChart, isFalse);
  });
}
