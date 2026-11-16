import 'dart:convert';

import 'package:PiliPlus/plugin/pl_player/js_web_player.dart';
import 'package:flutter/painting.dart' show Alignment, BoxFit;
import 'package:flutter_test/flutter_test.dart';

class _RecordingPlayer extends JsWebPlayer {
  final commands = <String>[];

  @override
  Future<void> evaluateJavascript(String source) async {
    commands.add(source);
  }

  Map<String, dynamic> get lastOpen {
    final source = commands.lastWhere(
      (js) => js.startsWith('window.__dashOpen'),
    );
    final start =
        source.indexOf('window.__dashOpen(') + 'window.__dashOpen('.length;
    return jsonDecode(source.substring(start, source.length - 2))
        as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RecordingPlayer player;

  setUp(() => player = _RecordingPlayer());
  tearDown(() => player.dispose());

  test(
    'toggle before page readiness is preserved when opening the media',
    () async {
      await player.open('https://example.invalid/video');
      await player.playOrPause();
      player.reportPageReady();
      expect(player.lastOpen['autoplay'], isTrue);
    },
  );

  test('toggle to pause remains paused when reloading', () async {
    await player.open('https://example.invalid/video', play: true);
    player.reportPageReady();
    await player.playOrPause();
    await player.reload();
    expect(player.lastOpen['autoplay'], isFalse);
  });

  test(
    'opening another video does not retain the old duration and buffer',
    () async {
      await player.open('https://example.invalid/old');
      player.handleMessage('time', {
        'time': 100,
        'buffer': 110,
        'duration': 120,
      });
      await player.open('https://example.invalid/new');
      expect(player.state.position, Duration.zero);
      expect(player.state.buffer, Duration.zero);
      expect(player.state.duration, Duration.zero);
    },
  );

  test(
    'commands from an old unopened source cannot affect its replacement',
    () async {
      await player.open('https://example.invalid/old');
      await player.pause();
      await player.seek(const Duration(seconds: 70));
      await player.open('https://example.invalid/new', play: true);
      player.reportPageReady();
      expect(player.lastOpen['autoplay'], isTrue);
      expect(player.commands, hasLength(1));
    },
  );

  test('duplicate ended messages emit completion only once', () async {
    final completions = <bool>[];
    final subscription = player.stream.completed.listen(completions.add);
    player.handleMessage('ended', {});
    player.handleMessage('ended', {});
    await Future<void>.delayed(Duration.zero);
    expect(completions, [true]);
    await subscription.cancel();
  });

  test(
    'reload preserves a seek back to zero instead of the initial offset',
    () async {
      await player.open(
        'https://example.invalid/video',
        start: const Duration(seconds: 79),
      );
      player.reportPageReady();
      player.handleMessage('time', {'time': 0, 'buffer': 10, 'duration': 120});
      await player.reload();
      expect(player.lastOpen['start'], 0);
    },
  );

  test('latest layout survives source changes before page readiness', () async {
    player.setVideoLayout(fit: BoxFit.cover, aspectRatio: 4 / 3);
    await player.open('https://example.invalid/old');
    player.setVideoLayout(fit: BoxFit.fill, alignment: Alignment.topLeft);
    await player.open('https://example.invalid/new');
    player.reportPageReady();
    expect(player.lastOpen['layout'], {
      'fit': 'fill',
      'alignmentX': -1.0,
      'alignmentY': -1.0,
      'aspectRatio': null,
    });
    expect(player.commands, hasLength(1));
  });

  test('display changes do not reopen or seek the media', () async {
    await player.open('https://example.invalid/video', play: true);
    player.reportPageReady();
    player.commands.clear();
    player.setVideoLayout(fit: BoxFit.cover, aspectRatio: 16 / 9);
    expect(player.commands, hasLength(1));
    expect(player.commands.single, contains('"type":"layout"'));
    expect(player.commands.single, isNot(contains('__dashOpen')));
    player.setVideoLayout(fit: BoxFit.cover, aspectRatio: 16 / 9);
    expect(player.commands, hasLength(1));
  });

  test(
    'reload retains fitting settings and sanitizes invalid ratios',
    () async {
      player.setVideoLayout(fit: BoxFit.none, aspectRatio: double.nan);
      await player.open('https://example.invalid/video');
      player.reportPageReady();
      await player.reload();
      expect(player.lastOpen['layout']['fit'], 'none');
      expect(player.lastOpen['layout']['aspectRatio'], isNull);
    },
  );

  test('reload resumes from the latest reported playback position', () async {
    await player.open(
      'https://example.invalid/video',
      start: const Duration(seconds: 79),
      play: true,
    );
    player.reportPageReady();
    player.handleMessage('time', {'time': 100, 'buffer': 110, 'duration': 120});
    await player.reload();
    expect(player.lastOpen['start'], 100000);
  });
}
