import 'package:connectivity_plus/connectivity_plus.dart';

abstract final class ConnectivityUtils {
  static Future<bool> get isWiFi async {
    try {
      return (await Connectivity().checkConnectivity()).contains(
        ConnectivityResult.wifi,
      );
    } catch (_) {
      return true;
    }
  }
}
