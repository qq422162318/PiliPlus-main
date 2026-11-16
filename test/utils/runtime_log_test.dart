import 'dart:io';

import 'package:PiliPlus/services/runtime_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-log-test-');
    file = File('${directory.path}/log.txt');
  });

  tearDown(() => directory.delete(recursive: true));

  test('log records append in order and preserve same-day sessions', () async {
    final today = DateTime(2026, 11, 15, 12);
    await file.writeAsString(
      '2026-11-15T09:00:00.000 [INFO] existing session\n',
    );
    final writer = RuntimeLogFile(file, now: () => today);
    final first = writer.write('INFO', 'open player');
    final second = writer.write('ERROR', 'decoder failed');
    await Future.wait([first, second]);
    final text = await file.readAsString();
    expect(
      text,
      startsWith('2026-11-15T09:00:00.000 [INFO] existing session\n'),
    );
    expect(text, contains('[INFO] open player'));
    expect(text, contains('[ERROR] decoder failed'));
    expect(
      text.indexOf('open player'),
      lessThan(text.indexOf('decoder failed')),
    );
    expect(writer.error, isNull);
  });

  test('signed URLs, credentials and HTTP headers are redacted', () async {
    final writer = RuntimeLogFile(file);
    await writer.write('WARN', '''
Failed https://cdn.example/video.m4s?deadline=1&sign=signed-secret
Authorization: Bearer auth-secret
Cookie: SESSDATA=cookie-secret; bili_jct=csrf-secret
{"access_key": "access-secret", "refresh_token": "refresh-secret"}
password=password-secret MDK_KEY=license-secret
''');
    final text = await file.readAsString();
    for (final secret in [
      'signed-secret',
      'auth-secret',
      'cookie-secret',
      'csrf-secret',
      'access-secret',
      'refresh-secret',
      'password-secret',
      'license-secret',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect(text, contains('[redacted URL]'));
  });

  test('oversized log is cleared without retaining a previous file', () async {
    await file.writeAsString('old log exceeding limit');
    final previous = File('${file.path}.previous');
    await previous.writeAsString('older log');
    final writer = RuntimeLogFile(file, maxBytes: 8);
    await writer.write('INFO', 'new log');
    expect(await previous.exists(), isFalse);
    expect(await file.readAsString(), contains('new log'));
    expect(await file.readAsString(), isNot(contains('old log')));
    expect(writer.error, isNull);
  });

  test(
    'startup removes other dates but preserves today and its stack traces',
    () async {
      await file.writeAsString('''
2026-11-14T23:59:00.000 [ERROR] yesterday
old stack trace
2026-11-15T09:00:00.000 [ERROR] today
current stack trace
2026-11-16T09:00:00.000 [INFO] another date
''');
      final writer = RuntimeLogFile(
        file,
        now: () => DateTime(2026, 11, 15, 12),
      );
      await writer.write('INFO', 'new entry');
      final text = await file.readAsString();
      expect(text, contains('today\ncurrent stack trace'));
      expect(text, contains('new entry'));
      expect(text, isNot(contains('2026-11-14')));
      expect(text, isNot(contains('old stack trace')));
      expect(text, isNot(contains('2026-11-16')));
    },
  );

  test(
    'crossing midnight clears yesterday on the first new-day write',
    () async {
      var now = DateTime(2026, 11, 15, 23, 59, 59);
      final writer = RuntimeLogFile(file, now: () => now);
      await writer.write('INFO', 'yesterday entry');
      now = DateTime(2026, 11, 16, 0, 0, 1);
      await writer.write('INFO', 'today entry');
      final text = await file.readAsString();
      expect(text, contains('2026-11-16T00:00:01'));
      expect(text, contains('today entry'));
      expect(text, isNot(contains('yesterday entry')));
    },
  );

  test('queued writes use the date when they execute', () async {
    var now = DateTime(2026, 11, 15, 23, 59, 59);
    final writer = RuntimeLogFile(file, now: () => now);
    final pending = writer.write('INFO', 'queued entry');
    now = DateTime(2026, 11, 16, 0, 0, 1);
    await pending;
    expect(await file.readAsString(), startsWith('2026-11-16T'));
  });

  test('unwritable log path does not throw into playback', () async {
    final writer = RuntimeLogFile(File('${directory.path}/missing/log.txt'));
    await writer.write('INFO', 'first');
    await writer.write('ERROR', 'second');
    await writer.flush();
    expect(writer.error, isA<FileSystemException>());
  });
}
