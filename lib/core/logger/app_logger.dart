import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Технические логи приложения в локальный файл на ТСД
/// (для разбора администратором). Аудит действий пользователей
/// ведётся штатными средствами самой Jira.
///
/// Файл: <docs>/logs/app.log, ротация: 5 файлов по 1 МБ.
class AppLogger {
  static const int _maxFileBytes = 1024 * 1024;
  static const int _maxFiles = 5;

  File? _file;
  final List<String> _buffer = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'logs'));
      await dir.create(recursive: true);
      _file = File(p.join(dir.path, 'app.log'));
      _initialized = true;
      for (final line in _buffer) {
        await _write(line);
      }
      _buffer.clear();
    } catch (e) {
      // Логгер не должен ронять приложение.
      _initialized = false;
    }
  }

  Future<void> _write(String line) async {
    final file = _file;
    if (file == null) return;
    try {
      final size = await file.length();
      if (size > _maxFileBytes) {
        await _rotate(dir: file.parent);
      }
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // Игнорируем ошибки записи логов.
    }
  }

  Future<void> _rotate({required Directory dir}) async {
    for (var i = _maxFiles - 1; i >= 1; i--) {
      final src = File(p.join(dir.path, 'app.log.$i'));
      final dst = File(p.join(dir.path, 'app.log.${i + 1}'));
      if (await src.exists()) {
        if (await dst.exists()) await dst.delete();
        await src.rename(dst.path);
      }
    }
    final current = File(p.join(dir.path, 'app.log'));
    if (await current.exists()) {
      await current.rename(p.join(dir.path, 'app.log.1'));
    }
    _file = File(p.join(dir.path, 'app.log'));
  }

  void _log(String level, String message) {
    final line =
        '${DateTime.now().toIso8601String()} [$level] $message';
    if (!_initialized) {
      _buffer.add(line);
      // Пытаемся инициализироваться лениво.
      unawaited(init());
      return;
    }
    unawaited(_write(line));
  }

  void info(String message) => _log('INFO', message);
  void warn(String message) => _log('WARN', message);
  void error(String message, [Object? error, StackTrace? stack]) {
    _log('ERROR', '$message${error != null ? ' | $error' : ''}');
    if (stack != null) {
      _log('ERROR', stack.toString());
    }
  }

  /// Путь к текущему файлу логов (для экрана «Диагностика»).
  Future<String> get logFilePath async {
    await init();
    return _file?.path ?? 'недоступно';
  }
}
