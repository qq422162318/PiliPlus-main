import 'dart:io' show File;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/extension/file_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/path_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

abstract final class ImageUtils {
  static bool silentDownImg = Pref.silentDownImg;

  // 图片分享
  static Future<void> onShareImg(String url) async {
    try {
      SmartDialog.showLoading();
      final res = await CacheManager.manager.getSingleFile(
        url.http2https,
      );
      SmartDialog.dismiss();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(res.path)],
          sharePositionOrigin: await ShareUtils.sharePositionOrigin,
        ),
      );
    } catch (e) {
      SmartDialog.showToast(e.toString());
    }
  }

  static Future<bool> downloadLivePhoto({
    required String url,
    required String liveUrl,
    required int width,
    required int height,
  }) async {
    try {
      if (!silentDownImg) SmartDialog.showLoading(msg: '正在下载');

      String videoName = "video_${Utils.getFileName(liveUrl)}";
      String videoPath = '$tmpDirPath/$videoName';

      final res = await Request().downloadFile(liveUrl.http2https, videoPath);
      if (res.statusCode != 200) throw '${res.statusCode}';

      if (!silentDownImg) SmartDialog.showLoading(msg: '正在保存');
      await saveFileImg(
        filePath: videoPath,
        fileName: videoName,
        needToast: true,
      );
      return true;
    } catch (err) {
      SmartDialog.showToast(err.toString());
      return false;
    } finally {
      if (!silentDownImg) SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  static Future<bool> downloadImg(List<String> imgList) async {
    if (!silentDownImg) {
      SmartDialog.showLoading(msg: '正在下载原图');
    }
    final futures = imgList.map((url) async {
      final name = Utils.getFileName(url);
      final file = await CacheManager.manager.getSingleFile(url.http2https);
      return (file, name);
    });
    final List<(File, String)> result;
    try {
      try {
        result = await Future.wait(
          futures,
          eagerError: true,
          cleanUp: (successValue) => successValue.$1.tryDel(),
        );
      } catch (e) {
        SmartDialog.showToast('保存失败');
        return false;
      }
      final dst = await FilePicker.getDirectoryPath();
      if (dst == null) {
        SmartDialog.showToast('取消保存');
        return false;
      }
      await Future.wait([
        for (final (src, name) in result) src.moveOrCopy(path.join(dst, name)),
      ]);
      SmartDialog.showToast(' 已保存 ');
      return true;
    } finally {
      if (!silentDownImg) SmartDialog.dismiss(status: .loading);
    }
  }

  static final _suffixRegex = RegExp(
    r'\.(jpg|jpeg|png|webp|gif|avif)$',
    caseSensitive: false,
  );
  static String safeThumbnailUrl(String? src) {
    if (src != null && _suffixRegex.hasMatch(src)) {
      return thumbnailUrl(src);
    }
    return src.http2https;
  }

  static final _thumbRegex = RegExp(
    r'(@(\d+[a-z]_?)*)(\..*)?$',
    caseSensitive: false,
  );
  static String thumbnailUrl(String? src, [int maxQuality = 1]) {
    if (src != null && maxQuality != 100) {
      maxQuality = math.max(maxQuality, GlobalData().imgQuality);
      bool hasMatch = false;
      src = src.splitMapJoin(
        _thumbRegex,
        onMatch: (match) {
          hasMatch = true;
          String suffix = match.group(3) ?? '.webp';
          return '${match.group(1)}_${maxQuality}q$suffix';
        },
        onNonMatch: (String str) {
          return str;
        },
      );
      if (!hasMatch) {
        src += '@${maxQuality}q.webp';
      }
    }
    return src.http2https;
  }

  static Future<bool?> saveByteImg({
    required Uint8List bytes,
    required String fileName,
    String ext = 'png',
    bool showLoading = true,
  }) async {
    SmartDialog.dismiss();
    final savePath = await FilePicker.saveFile(
      fileName: '$fileName.$ext',
      bytes: Uint8List(0),
    );
    if (savePath == null) {
      SmartDialog.showToast('取消保存');
      return null;
    }
    await File(savePath.toFilePath()).writeAsBytes(bytes);
    SmartDialog.showToast(' 已保存 ');
    return true;
  }

  static Future<void> saveFileImg({
    required String filePath,
    required String fileName,
    bool needToast = false,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      SmartDialog.showToast("文件不存在");
      return;
    }
    final savePath = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List(0),
    );
    if (savePath == null) {
      SmartDialog.showToast('取消保存');
      return;
    }
    await file.moveOrCopy(savePath.toFilePath());
    if (needToast) SmartDialog.showToast(' 已保存 ');
  }
}
