import 'dart:io' show Platform;

abstract final class PlatformUtils {
  @pragma('vm:platform-const')
  static final bool isDesktop = Platform.isWindows;

  static const bool isMobile = false;
  static const bool isDarwin = false;

  static void requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('PiliPlus supports Windows only.');
    }
  }
}
