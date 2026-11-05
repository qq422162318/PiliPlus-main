import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/rendering.dart' show Rect;

abstract final class ShareUtils {
  // Windows sharing does not require a popover anchor.
  static Future<Rect?> get sharePositionOrigin => Future.value(null);

  static Future<void> shareText(String text) => Utils.copyText(text);
}
