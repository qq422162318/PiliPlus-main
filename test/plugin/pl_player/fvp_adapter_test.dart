import 'package:PiliPlus/plugin/pl_player/fvp_adapter.dart';
import 'package:PiliPlus/plugin/pl_player/fvp_video.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuration does not allocate a native player', () async {
    final player = await FvpPlayer.create();
    addTearDown(player.dispose);

    player
      ..setMediaHeader(userAgent: 'test', referer: 'https://www.bilibili.com')
      ..setBufferRange(min: 1000, max: 4000)
      ..setRotate(90);
    await player.setRate(1.25);
    await player.setVolume(75);

    expect(player.state.volume, 75);
    expect(player.state.rate, 1.25);
    expect(player.getProperty('avio.headers'), contains('Referer:'));
    expect(player.videoSize.value, isNull);
    expect(player.textureId.value, isNull);
  });

  test('volume uses the 0–100 application units and clamps boosts', () async {
    final player = await FvpPlayer.create();
    addTearDown(player.dispose);

    await player.setVolume(100);
    expect(player.state.volume, 100);
    await player.setVolume(-10);
    expect(player.state.volume, 0);
    await player.setVolume(300);
    expect(player.state.volume, 200);
  });

  test(
    'unopened player disposes its streams and can be disposed twice',
    () async {
      final player = await FvpPlayer.create();
      final completion = Future.wait([
        player.stream.playing.drain<void>(),
        player.stream.completed.drain<void>(),
        player.stream.position.drain<void>(),
        player.stream.duration.drain<void>(),
        player.stream.buffer.drain<void>(),
        player.stream.buffering.drain<void>(),
        player.stream.error.drain<void>(),
      ]);

      await player.dispose();
      await completion;
      await player.dispose();
      await expectLater(player.open('unused'), throwsStateError);
    },
  );

  testWidgets('native video uses filtered sampling when scaled', (
    tester,
  ) async {
    final player = await FvpPlayer.create();
    player.videoSize.value = const Size(1920, 1080);
    player.textureId.value = 7;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: FittedBox(child: FvpVideo(controller: player)),
      ),
    );
    expect(
      tester.widget<Texture>(find.byType(Texture)).filterQuality,
      FilterQuality.medium,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await player.dispose();
  });

  testWidgets('video surface is safe before opening media', (tester) async {
    final player = await FvpPlayer.create();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: FvpVideo(controller: player)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Texture), findsNothing);
    expect(find.byType(ColoredBox), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await player.dispose();
  });
}
