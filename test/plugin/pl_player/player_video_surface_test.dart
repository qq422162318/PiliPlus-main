import 'package:PiliPlus/plugin/pl_player/js_web_player.dart';
import 'package:PiliPlus/plugin/pl_player/js_web_video.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/video_surface.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _webViewKey = ValueKey('stub-webview');

class _StubWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _StubWebViewWidget(params);
}

class _StubWebViewWidget extends PlatformInAppWebViewWidget {
  _StubWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand(key: _webViewKey);

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JsWebPlayer player;

  setUp(() {
    InAppWebViewPlatform.instance = _StubWebViewPlatform();
    player = JsWebPlayer();
  });
  tearDown(() => player.dispose());

  Widget surface(Size viewport, {VideoFitType fit = VideoFitType.contain}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: viewport,
            child: PlayerVideoSurface(backend: player, videoFit: fit),
          ),
        ),
      );

  for (final dpr in [1.0, 1.25, 1.5, 2.0]) {
    testWidgets('WebView uses the full viewport at ${dpr}x DPI', (
      tester,
    ) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(3840 * dpr, 2160 * dpr);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final size in [
        const Size(854, 480),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        await tester.pumpWidget(surface(size));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byKey(_webViewKey)), size);
      }
    });
  }

  testWidgets('WebView is not rasterized inside a FittedBox', (tester) async {
    await tester.pumpWidget(surface(const Size(800, 450)));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byType(JsWebVideo),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
  });

  testWidgets('metadata and display changes retain the full-size WebView', (
    tester,
  ) async {
    const size = Size(800, 450);
    await tester.pumpWidget(surface(size));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(JsWebVideo));
    player.handleMessage('meta', {'width': 1080, 'height': 1920});
    await tester.pumpWidget(surface(size, fit: VideoFitType.cover));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(JsWebVideo)), same(state));
    expect(tester.getSize(find.byKey(_webViewKey)), size);
  });
}
