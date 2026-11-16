import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;

void main() {
  final media = Platform.environment['PILIPLUS_NATIVE_TEST_MEDIA'];
  test(
    'MDK opens and advances a real H.264 stream',
    () async {
      // flutter_tester does not register the Windows plugin that starts callbacks.
      final library = DynamicLibrary.open('fvp.dll');
      final startup = library.lookupFunction<Void Function(), void Function()>(
        'MdkCallbacksStartup',
      );
      final shutdown = library.lookupFunction<Void Function(), void Function()>(
        'MdkCallbacksShutdown',
      );
      startup();
      mdk.Player? player;
      try {
        mdk.setGlobalOption('logLevel', mdk.LogLevel.off);
        player = mdk.Player();
        player.setDecoders(mdk.MediaType.video, [
          'D3D11',
          'MFT:d3d=11',
          'DXVA',
        ]);
        player.setBufferRange(min: 1000, max: 4000);
        player.media = media!;
        player.setActiveTracks(mdk.MediaType.subtitle, []);
        final position = await player.prepare().timeout(
          const Duration(seconds: 30),
        );
        expect(position, greaterThanOrEqualTo(0));
        expect(player.mediaInfo.video, isNotEmpty);
        expect(player.mediaInfo.video!.first.codec.codec, 'h264');
        player.state = mdk.PlaybackState.playing;
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(player.position, greaterThan(position));
      } finally {
        try {
          if (player != null) {
            // Upstream dispose is void-async; stream closure follows texture release.
            final closed = Future.wait([
              player.onStateChanged.drain<void>(),
              player.onMediaStatus.drain<void>(),
              player.onEvent.drain<void>(),
            ]);
            player.dispose();
            await closed.timeout(const Duration(seconds: 5));
          }
        } finally {
          mdk.setLogHandler(null);
          shutdown();
        }
      }
    },
    skip: !Platform.isWindows || media == null,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
