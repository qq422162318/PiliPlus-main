import 'package:PiliPlus/plugin/pl_player/fvp_adapter.dart';
import 'package:PiliPlus/plugin/pl_player/fvp_video.dart';
import 'package:PiliPlus/plugin/pl_player/js_web_player.dart';
import 'package:PiliPlus/plugin/pl_player/js_web_video.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/player_backend.dart';
import 'package:material_ui/material_ui.dart';

/// Backend-specific video layout, independent of playback controls and gestures.
class PlayerVideoSurface extends StatelessWidget {
  const PlayerVideoSurface({
    super.key,
    required this.backend,
    required this.videoFit,
    this.fill = Colors.black,
    this.alignment = Alignment.center,
    this.flipX = false,
    this.flipY = false,
  });

  final PlayerBackend backend;
  final VideoFitType videoFit;
  final Color fill;
  final Alignment alignment;
  final bool flipX;
  final bool flipY;

  @override
  Widget build(BuildContext context) {
    return Transform.flip(
      flipX: flipX,
      flipY: flipY,
      child: switch (backend) {
        // A WebView is a raster surface, not an intrinsically sized video.
        // FittedBox gives its child unbounded constraints, causing the old
        // 640x360 fallback to be enlarged with nearest-neighbour sampling.
        // Keep the full viewport (and native DPI); fit the video in the page.
        final JsWebPlayer js => JsWebVideo(
          controller: js,
          fill: fill,
          fit: videoFit.boxFit,
          alignment: alignment,
          aspectRatio: videoFit.aspectRatio,
        ),
        final FvpPlayer fvp => FittedBox(
          fit: videoFit.boxFit,
          alignment: alignment,
          child: FvpVideo(
            controller: fvp,
            fill: fill,
            aspectRatio: videoFit.aspectRatio,
          ),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
