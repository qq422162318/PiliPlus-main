import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:PiliPlus/plugin/pl_player/player_backend.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  StreamSubscription<bool>? _subscription;
  PlayerBackend? player;

  void _attach(PlayerBackend? currentPlayer) {
    if (identical(currentPlayer, player)) return;
    _subscription?.cancel();
    player = currentPlayer;
    if (currentPlayer == null) {
      _subscription = null;
      return;
    }
    controller.value = currentPlayer.state.playing ? 1 : 0;
    _subscription = currentPlayer.stream.playing.listen((playing) {
      if (playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // 控制条可能在后端建好之前就挂载（等 WebView 起来那几秒）。这时先空着，
    // 等 didUpdateWidget / 后端就绪后再订阅，否则图标永远停在“播放”。
    _attach(widget.plPlayerController.videoPlayerController);
  }

  @override
  void didUpdateWidget(covariant PlayOrPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach(widget.plPlayerController.videoPlayerController);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.plPlayerController.onDoubleTapCenter,
        child: Center(
          child: AnimatedIcon(
            semanticLabel: player?.state.playing == true ? '暂停' : '播放',
            progress: controller,
            icon: AnimatedIcons.play_pause,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
