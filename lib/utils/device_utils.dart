import 'package:flutter/widgets.dart' show WidgetsBinding, Size;
import 'package:nativeapi/nativeapi.dart' as nativeapi show Size;
import 'package:win32/win32.dart' as kernel32;

abstract final class DeviceUtils {
  static bool get isTablet => size.shortestSide >= 600;

  static Size get size {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  static const String platformName = 'desktop';

  static void exitApp() {
    // Terminate the process to avoid the WebView2 shutdown hang.
    final hProcess = kernel32.GetCurrentProcess();
    kernel32.TerminateProcess(hProcess, 0);
  }

  static const desktopMinSize = nativeapi.Size(width: 400, height: 720);
}
