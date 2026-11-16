import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/fvp_media_ready.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fvp/mdk.dart' as mdk;

mdk.MediaInfo _videoInfo() => mdk.MediaInfo()
  ..streams = 1
  ..video = [
    mdk.VideoStreamInfo()
      ..codec.codec = 'h264'
      ..codec.width = 1280
      ..codec.height = 720,
  ];

void main() {
  late StreamController<Object?> changes;

  setUp(() => changes = StreamController<Object?>.broadcast());
  tearDown(() => changes.close());

  test('recovery waits for both the pending seek and paused state', () async {
    final states = StreamController<Object?>.broadcast();
    addTearDown(states.close);
    var status = mdk.MediaStatus(
      mdk.MediaStatus.loaded |
          mdk.MediaStatus.prepared |
          mdk.MediaStatus.seeking,
    );
    var state = mdk.PlaybackState.stopped;
    var completed = false;
    final ready = waitForFvpPreparation(
      readStatus: () => status,
      readState: () => state,
      statusChanges: changes.stream,
      stateChanges: states.stream,
    ).then((_) => completed = true);
    state = mdk.PlaybackState.paused;
    states.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    state = mdk.PlaybackState.stopped;
    status = mdk.MediaStatus(mdk.MediaStatus.loaded | mdk.MediaStatus.prepared);
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    state = mdk.PlaybackState.paused;
    states.add(null);
    await ready;
    expect(changes.hasListener, isFalse);
    expect(states.hasListener, isFalse);
  });

  test('recovery accepts an already paused and prepared player', () async {
    final states = StreamController<Object?>.broadcast();
    addTearDown(states.close);
    await waitForFvpPreparation(
      readStatus: () => mdk.MediaStatus(
        mdk.MediaStatus.loaded | mdk.MediaStatus.prepared,
      ),
      readState: () => mdk.PlaybackState.paused,
      statusChanges: changes.stream,
      stateChanges: states.stream,
    );
    expect(changes.hasListener, isFalse);
    expect(states.hasListener, isFalse);
  });

  test(
    'an unfinished preparation times out and removes both listeners',
    () async {
      final states = StreamController<Object?>.broadcast();
      addTearDown(states.close);
      await expectLater(
        waitForFvpPreparation(
          readStatus: () => mdk.MediaStatus(mdk.MediaStatus.loaded),
          readState: () => mdk.PlaybackState.paused,
          statusChanges: changes.stream,
          stateChanges: states.stream,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(changes.hasListener, isFalse);
      expect(states.hasListener, isFalse);
    },
  );

  test('prepare before loaded waits for the video metadata', () async {
    var info = mdk.MediaInfo();
    var loaded = false;
    var completed = false;
    final ready =
        waitForFvpMediaInfo(
          readMediaInfo: () => info,
          isLoaded: () => loaded,
          changes: changes.stream,
          expectVideo: true,
        ).then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    info = _videoInfo();
    loaded = true;
    changes.add(null);
    expect((await ready).video!.single.codec.width, 1280);
  });

  test('an early audio-only event cannot finish a video open', () async {
    var info = mdk.MediaInfo()..streams = 1;
    var completed = false;
    final ready =
        waitForFvpMediaInfo(
          readMediaInfo: () => info,
          isLoaded: () => true,
          changes: changes.stream,
          expectVideo: true,
        ).then((value) {
          completed = true;
          return value;
        });
    changes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    info = _videoInfo();
    changes.add(null);
    expect((await ready).video, isNotEmpty);
  });

  test(
    'negative external-audio callback still waits for the main video',
    () async {
      var info = mdk.MediaInfo();
      var loaded = false;
      final ready = waitForFvpMediaInfo(
        readMediaInfo: () => info,
        isLoaded: () => loaded,
        changes: changes.stream,
        expectVideo: true,
        prepareResult: -1,
        externalAudio: true,
      );
      info = _videoInfo();
      loaded = true;
      changes.add(null);
      expect((await ready).video, isNotEmpty);
    },
  );

  test('negative single-source preparation still fails immediately', () async {
    await expectLater(
      waitForFvpMediaInfo(
        readMediaInfo: _videoInfo,
        isLoaded: () => true,
        changes: changes.stream,
        expectVideo: true,
        prepareResult: -1,
      ),
      throwsStateError,
    );
    expect(changes.hasListener, isFalse);
  });

  test('failed DASH source times out without reporting video ready', () async {
    await expectLater(
      waitForFvpMediaInfo(
        readMediaInfo: mdk.MediaInfo.new,
        isLoaded: () => false,
        changes: changes.stream,
        expectVideo: true,
        prepareResult: -1,
        externalAudio: true,
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(changes.hasListener, isFalse);
  });

  test('already-loaded video does not require another event', () async {
    final info = _videoInfo();
    expect(
      await waitForFvpMediaInfo(
        readMediaInfo: () => info,
        isLoaded: () => true,
        changes: changes.stream,
        expectVideo: true,
      ),
      same(info),
    );
  });

  test('explicit audio mode accepts loaded audio without a texture', () async {
    final info = mdk.MediaInfo()..streams = 1;
    expect(
      await waitForFvpMediaInfo(
        readMediaInfo: () => info,
        isLoaded: () => true,
        changes: changes.stream,
        expectVideo: false,
      ),
      same(info),
    );
  });

  test(
    'zero-stream media fails rather than reporting playback ready',
    () async {
      await expectLater(
        waitForFvpMediaInfo(
          readMediaInfo: mdk.MediaInfo.new,
          isLoaded: () => true,
          changes: changes.stream,
          expectVideo: false,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(changes.hasListener, isFalse);
    },
  );
}
