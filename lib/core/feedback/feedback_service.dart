import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// Тип звукового/вибро-отклика оператора (ТЗ, раздел 4).
enum ScanFeedback {
  /// Успешный скан: короткий высокий пик + короткая вибрация.
  success,

  /// Перемещение: двойной сигнал + двойная вибрация.
  move,

  /// Ошибка / дубликат / пустой МОЛ: низкий тон + долгая вибрация 1 с.
  error,
}

/// Звуковой и вибро-отклик. Оператор работает «вслепую» по звукам ТСД,
/// поэтому каждый сценарий имеет distinct-паттерн.
class FeedbackService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play(ScanFeedback feedback) async {
    try {
      switch (feedback) {
        case ScanFeedback.success:
          await _player.play(AssetSource('sounds/beep_success.wav'));
          await _vibrate(80);
        case ScanFeedback.move:
          await _player.play(AssetSource('sounds/beep_move.wav'));
          await _vibrate(80);
          await Future<void>.delayed(const Duration(milliseconds: 160));
          await _vibrate(80);
        case ScanFeedback.error:
          await _player.play(AssetSource('sounds/beep_error.wav'));
          await _vibrate(1000);
      }
    } catch (_) {
      // Отсутствие динамика/вибромотора не должно ломать сценарий.
    }
  }

  Future<void> _vibrate(int milliseconds) async {
    try {
      final has = await Vibration.hasVibrator();
      if (has == true) {
        await Vibration.vibrate(duration: milliseconds);
      }
    } catch (_) {
      // Эмулятор без вибромотора — молча пропускаем.
    }
  }

  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
