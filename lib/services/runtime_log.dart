import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// 顺序追加日志，限制文件大小和待写队列，避免日志影响播放。
class RuntimeLogFile {
  RuntimeLogFile(this.file, {this.maxBytes = 5 * 1024 * 1024});

  final File file;
  final int maxBytes;
  Future<void> _pending = Future.value();
  int _queued = 0;
  Object? error;

  static final _urls = RegExp(
    r'''\b(?:https?|rtmps?|file)://[^\s<>"']+''',
    caseSensitive: false,
  );
  static final _headers = RegExp(
    r'''\b(?:authorization|proxy-authorization|cookie|set-cookie)["']?\s*[:=][^\r\n]*''',
    caseSensitive: false,
  );
  static final _secrets = RegExp(
    r'''\b(?:SESSDATA|bili_jct|access[_-]?key|access[_-]?token|refresh[_-]?token|password|MDK_KEY)\b["']?\s*[:=]\s*(?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s,;}]+)''',
    caseSensitive: false,
  );
  static final _ansi = RegExp(r'\x1B\[[0-9;]*m');

  static String sanitize(String message) => message
      .replaceAll(_ansi, '')
      .replaceAll(_headers, '[redacted header]')
      .replaceAll(_secrets, '[redacted credential]')
      .replaceAll(_urls, '[redacted URL]');

  Future<void> write(String level, String message) {
    if (_queued >= 256 || error != null) return Future.value();
    final safe = sanitize(message);
    final text = safe.length > 8192 ? '${safe.substring(0, 8192)}…' : safe;
    final line = '${DateTime.now().toIso8601String()} [$level] $text\n';
    _queued++;
    _pending = _pending.then((_) async {
      try {
        if (await file.exists() && await file.length() >= maxBytes) {
          final previous = File('${file.path}.previous');
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
        }
        await file.writeAsString(line, mode: FileMode.append);
      } catch (exception) {
        // 日志目录不可写时，不把日志错误重新抛给播放器。
        error = exception;
      } finally {
        _queued--;
      }
    });
    return _pending;
  }

  Future<void> flush() => _pending;
}

abstract final class RuntimeLog {
  static RuntimeLogFile? _writer;
  static bool _debugPrintInstalled = false;
  static bool get enabled => _writer != null;
  static FlutterExceptionHandler? _flutterHandler;
  static bool Function(Object, StackTrace)? _platformHandler;

  static Future<void> init() async {
    if (_writer != null) return;
    final file = File(
      path.join(path.dirname(Platform.resolvedExecutable), 'log.txt'),
    );
    final writer = _writer = RuntimeLogFile(file);
    await writer.write('INFO', '=== PiliPlus session start pid=$pid ===');
    if (writer.error != null) {
      debugPrint('Cannot write log.txt beside the executable: ${writer.error}');
    }
    if (!_debugPrintInstalled) {
      _debugPrintInstalled = true;
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) info('Flutter: $message');
        previous(message, wrapWidth: wrapWidth);
      };
    }
    installErrorHandlers();
  }

  /// 在 Catcher 配置后再次调用，以保留其处理器并同时写入 log.txt。
  static void installErrorHandlers() {
    if (FlutterError.onError != _flutterHandler || _flutterHandler == null) {
      final previous = FlutterError.onError;
      _flutterHandler = (details) {
        error('Flutter exception', details.exception, details.stack);
        previous?.call(details);
      };
      FlutterError.onError = _flutterHandler;
    }
    final dispatcher = PlatformDispatcher.instance;
    if (dispatcher.onError != _platformHandler || _platformHandler == null) {
      final previous = dispatcher.onError;
      _platformHandler = (exception, stack) {
        error('Uncaught asynchronous exception', exception, stack);
        return previous?.call(exception, stack) ?? true;
      };
      dispatcher.onError = _platformHandler;
    }
  }

  static void info(String message) => _write('INFO', message);
  static void warning(String message) => _write('WARN', message);
  static void error(String message, Object exception, [StackTrace? stack]) =>
      _write('ERROR', '$message: $exception${stack == null ? '' : '\n$stack'}');

  static void _write(String level, String message) {
    final writer = _writer;
    if (writer != null) unawaited(writer.write(level, message));
  }

  static Future<void> flush() => _writer?.flush() ?? Future.value();
}
