import 'package:PiliPlus/plugin/pl_player/fvp_adapter.dart';
import 'package:material_ui/material_ui.dart';

/// The video surface only; playback controls and danmaku live in PLVideoPlayer.
class FvpVideo extends StatelessWidget {
  const FvpVideo({
    super.key,
    required this.controller,
    this.fill = Colors.black,
    this.aspectRatio,
  });

  final FvpPlayer controller;
  final Color fill;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Size?>(
      valueListenable: controller.videoSize,
      builder: (context, size, _) {
        final validSize = size != null && size.width > 0 && size.height > 0;
        final height = validSize ? size.height : 9.0;
        final ratio = aspectRatio;
        final width = ratio != null && ratio.isFinite && ratio > 0
            ? height * ratio
            : validSize
            ? size.width
            : 16.0;
        return SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: fill,
            child: ValueListenableBuilder<int?>(
              valueListenable: controller.textureId,
              builder: (context, textureId, _) =>
                  textureId != null && textureId >= 0
                  ? Texture(textureId: textureId)
                  : const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}
