import 'dart:async';

import 'package:fvp/mdk.dart' as mdk;

/// loaded 不代表 prepare 的解码和跳转已结束。
Future<void> waitForFvpPreparation({
  required mdk.MediaStatus Function() readStatus,
  required mdk.PlaybackState Function() readState,
  required Stream<Object?> statusChanges,
  required Stream<Object?> stateChanges,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final ready = Completer<void>();
  void check() {
    if (ready.isCompleted) return;
    final status = readStatus();
    if (status.test(mdk.MediaStatus.loaded) &&
        status.test(mdk.MediaStatus.prepared) &&
        !status.test(mdk.MediaStatus.seeking) &&
        readState() == mdk.PlaybackState.paused) {
      ready.complete();
    }
  }

  final statusSubscription = statusChanges.listen((_) => check());
  final stateSubscription = stateChanges.listen((_) => check());
  try {
    check();
    await ready.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('等待起播准备完成超时', timeout),
    );
  } finally {
    await statusSubscription.cancel();
    await stateSubscription.cancel();
  }
}

/// prepare 回调可能早于 loaded；必须等当前媒体信息可用再创建纹理。
Future<mdk.MediaInfo> waitForFvpMediaInfo({
  required mdk.MediaInfo Function() readMediaInfo,
  required bool Function() isLoaded,
  required Stream<Object?> changes,
  required bool expectVideo,
  int prepareResult = 0,
  bool externalAudio = false,
  Duration timeout = const Duration(seconds: 10),
}) async {
  // 外部音轨的准备/中止回调可能先到，不能代表主视频已失败。
  if (prepareResult < 0 && !(expectVideo && externalAudio)) {
    throw StateError('媒体打开失败 ($prepareResult)');
  }
  final ready = Completer<mdk.MediaInfo>();
  void check() {
    if (ready.isCompleted || !isLoaded()) return;
    final info = readMediaInfo();
    if (info.streams > 0 &&
        (!expectVideo || (info.video?.isNotEmpty ?? false))) {
      ready.complete(info);
    }
  }

  final subscription = changes.listen((_) => check());
  try {
    check();
    return await ready.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        expectVideo ? '等待有效视频轨信息超时' : '等待有效媒体信息超时',
        timeout,
      ),
    );
  } finally {
    await subscription.cancel();
  }
}
