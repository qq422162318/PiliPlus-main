import 'package:PiliPlus/common/skeleton/skeleton.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading placeholder does not schedule animation frames', (
    tester,
  ) async {
    const child = SizedBox(width: 120, height: 40);
    await tester.pumpWidget(const Skeleton(child: child));

    expect(find.byWidget(child), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
