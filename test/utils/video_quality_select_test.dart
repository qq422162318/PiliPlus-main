import 'package:PiliPlus/models/common/video/base_quality.dart';
import 'package:PiliPlus/models/common/video/video_decode_type.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:PiliPlus/utils/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

PlayUrlModel _playUrl(List<VideoQuality> videoIds) => PlayUrlModel.fromJson({
  'dash': {
    'duration': 0,
    'video': [
      for (final id in videoIds)
        {
          'id': id.code,
          'codecs': VideoDecodeFormatType.AVC.codes.first,
        },
    ],
  },
  'accept_quality': [
    for (final id in videoIds) id.code,
  ],
  'support_formats': [
    for (final id in videoIds)
      {
        'quality': id.code,
        'codecs': VideoDecodeFormatType.AVC.codes,
      },
  ],
});

void main() {
  test('find target quality', () {
    final playUrl = _playUrl(VideoQuality.values);
    final dash = playUrl.dash!;
    final preferQa = VideoQuality.high1080.code;
    final (
      int targetQuality,
      FormatItem targetFormat,
      VideoDecodeFormatType targetDecode,
      VideoItem targetVideo,
    ) = VideoUtils.findTargetVideo(
      dash.video!,
      preferQa,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AVC],
    );
    expect(targetQuality, preferQa);
  });

  test('find closest quality', () {
    final playUrl = _playUrl(
      VideoQuality.values.toList()..remove(VideoQuality.high1080plus),
    );
    final dash = playUrl.dash!;
    final preferQa = VideoQuality.high1080plus.code;
    final (
      int targetQuality,
      FormatItem targetFormat,
      VideoDecodeFormatType targetDecode,
      VideoItem targetVideo,
    ) = VideoUtils.findTargetVideo(
      dash.video!,
      preferQa,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AVC],
    );
    expect(targetQuality, VideoQuality.superResolution.code);
  });

  test('find closest quality', () {
    final playUrl = _playUrl([
      VideoQuality.dolbyVision,
      VideoQuality.high1080,
      VideoQuality.clear480,
    ]);
    final dash = playUrl.dash!;
    final preferQa = VideoQuality.speed240.code;
    final (
      int targetQuality,
      FormatItem targetFormat,
      VideoDecodeFormatType targetDecode,
      VideoItem targetVideo,
    ) = VideoUtils.findTargetVideo(
      dash.video!,
      preferQa,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AVC],
    );
    expect(targetQuality, VideoQuality.clear480.code);
  });

  test('720p preference does not select a higher 60fps quality', () {
    final playUrl = _playUrl([
      VideoQuality.high108060,
      VideoQuality.high1080,
      VideoQuality.high72060,
      VideoQuality.high720,
      VideoQuality.clear480,
    ]);
    final (quality, _, decode, _) = VideoUtils.findTargetVideo(
      playUrl.dash!.video!,
      VideoQuality.high720.code,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AVC],
    );
    expect(quality, VideoQuality.high720.code);
    expect(decode, VideoDecodeFormatType.AVC);
  });

  test('720p preference falls back to 480p when ordinary 720p is absent', () {
    final playUrl = _playUrl([
      VideoQuality.high108060,
      VideoQuality.high72060,
      VideoQuality.clear480,
    ]);
    final (quality, _, _, _) = VideoUtils.findTargetVideo(
      playUrl.dash!.video!,
      VideoQuality.high720.code,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AVC],
    );
    expect(quality, VideoQuality.clear480.code);
  });

  test('unsupported higher qualities cannot displace an AVC stream', () {
    final playUrl = _playUrl([
      VideoQuality.high1080,
      VideoQuality.clear480,
    ]);
    playUrl.dash!.video!.first.codecs = 'av01.0.08M.08';

    final (quality, _, decode, video) = VideoUtils.findTargetVideo(
      playUrl.dash!.video!,
      VideoQuality.high1080.code,
      playUrl.acceptQuality,
      playUrl.supportFormats!,
      [.AV1, .HEVC],
    );

    expect(quality, VideoQuality.clear480.code);
    expect(decode, VideoDecodeFormatType.AVC);
    expect(video.codecs, startsWith('avc1'));
  });

  test('rejects a response without AVC instead of falling back', () {
    final playUrl = _playUrl([VideoQuality.high1080]);
    playUrl.dash!.video!.first.codecs = 'hev1.1.6.L120.90';

    expect(
      () => VideoUtils.findTargetVideo(
        playUrl.dash!.video!,
        VideoQuality.high1080.code,
        playUrl.acceptQuality,
        playUrl.supportFormats!,
        [.AVC],
      ),
      throwsUnsupportedError,
    );
  });
}
