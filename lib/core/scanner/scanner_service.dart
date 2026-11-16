import 'dart:async';

import 'package:flutter/services.dart';

/// Сервис лазерного сканера ТСД (Urovo DT50 и аналоги).
///
/// На ТСД сканер работает через Android Broadcast Intents
/// (мгновенное чтение без включения камеры). Нативная часть
/// (MainActivity.kt) ловит broadcast'ы сканера и передаёт код
/// в Flutter через MethodChannel `inventory_jira/scanner`.
///
/// Поддерживаемые intent'ы (см. MainActivity.kt):
///  - android.intent.action.SCANRESULT (Urovo, Chainway и др.)
///  - com.symbol.datawedge.data_string (Zebra DataWedge)
///  - com.zebra.datawedge.data_string
///  - urowo.intent.action.SCAN / com.urovo.scan.action
///
/// Дополнительно работает «keyboard wedge» режим: сканер эмулирует
/// клавиатуру и завершает ввод Enter — это обрабатывается полем поиска
/// экрана инвентаризации (onSubmitted), поэтому отдельный код не нужен.
class ScannerService {
  static const MethodChannel _channel =
      MethodChannel('inventory_jira/scanner');

  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  bool _listening = false;

  /// Поток считанных кодов (лазер ТСД).
  Stream<String> get scanStream => _controller.stream;

  void startListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScan') {
        final code = (call.arguments as String?)?.trim() ?? '';
        if (code.isNotEmpty && !_controller.isClosed) {
          _controller.add(code);
        }
      }
    });
  }

  void stopListening() {
    _listening = false;
    _channel.setMethodCallHandler(null);
  }

  Future<void> dispose() async {
    stopListening();
    await _controller.close();
  }
}
