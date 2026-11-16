import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Данные этикетки 58×30 мм (ТЗ, раздел 4):
/// левая половина — QR-код (ключ объекта Jira),
/// правая — название, ключ, код 1С, организация.
class LabelData {
  final String qrContent;
  final String name;
  final String objectKey;
  final String code1c;
  final String organization;

  const LabelData({
    required this.qrContent,
    required this.name,
    required this.objectKey,
    required this.code1c,
    required this.organization,
  });
}

/// Кодировка Windows-1251 для кириллицы на TSC TE210.
///
/// Часть прошивок TSC не умеет UTF-8 и требует CODEPAGE 1251.
/// Кириллица в 1251: А–Я = 0xC0–0xDF, а–я = 0xE0–0xFF, Ё = 0xA8, ё = 0xB8.
class Cp1251 {
  static List<int> encode(String input) {
    final out = <int>[];
    for (final rune in input.runes) {
      if (rune < 0x80) {
        out.add(rune);
      } else if (rune >= 0x410 && rune <= 0x42F) {
        // А–Я, а–я
        out.add(rune - 0x410 + 0xC0);
      } else if (rune == 0x401) {
        out.add(0xA8); // Ё
      } else if (rune == 0x451) {
        out.add(0xB8); // ё
      } else if (rune == 0x2013) {
        out.add(0x96); // –
      } else if (rune == 0x2014) {
        out.add(0x97); // —
      } else if (rune == 0xAB) {
        out.add(0xAB); // «
      } else if (rune == 0xBB) {
        out.add(0xBB); // »
      } else {
        out.add(0x3F); // ? — неподдерживаемый символ
      }
    }
    return out;
  }
}

/// Построитель TSPL-программы этикетки 58×30 мм.
///
/// Разрешение TE210 — 203 dpi: ширина 58 мм ≈ 463 точки, высота 30 мм ≈ 240 точек.
/// Левая половина (~170 точек) — QR, правая — текст.
class TsplBuilder {
  static const int widthDots = 463;
  static const int heightDots = 240;

  /// Собирает TSPL для одной этикетки.
  static String buildLabel(LabelData label, {String codepage = 'UTF-8'}) {
    final cp = codepage == 'Windows-1251' ? '1251' : 'UTF-8';
    final qr = _escape(label.qrContent);
    final name = _truncate(_escape(label.name), 26);
    final key = _truncate(_escape(label.objectKey), 26);
    final code1c = _truncate(_escape(label.code1c), 26);
    final org = _truncate(_escape(label.organization), 26);

    final sb = StringBuffer();
    sb.writeln('SIZE 58 mm,30 mm');
    sb.writeln('DIRECTION 1');
    sb.writeln('REFERENCE 0,0');
    sb.writeln('DENSITY 12');
    sb.writeln('SPEED 4');
    sb.writeln('GAP 2 mm,0 mm');
    sb.writeln('CODEPAGE $cp');
    sb.writeln('CLS');
    // QR-код слева. Синтаксис TSPL: QRCODE x,y,ECC,cellwidth,mode,rotation,"content"
    sb.writeln('QRCODE 12,42,M,5,A,0,"$qr"');
    // Текст справа. Синтаксис: TEXT x,y,"font",rotation,xmul,ymul,"content"
    // Шрифт "0" — встроенный растровый, xmul/ymul=1 даёт ~12 точек на символ.
    sb.writeln('TEXT 178,18,"0",0,1,1,"$name"');
    sb.writeln('TEXT 178,52,"0",0,1,1,"$key"');
    sb.writeln('TEXT 178,86,"0",0,1,1,"$code1c"');
    sb.writeln('TEXT 178,120,"0",0,1,1,"$org"');
    sb.writeln('PRINT 1,1');
    return sb.toString();
  }

  /// Пустая тестовая этикетка (кнопка «Тестовая печать»).
  static String buildTestLabel({String codepage = 'UTF-8'}) {
    final cp = codepage == 'Windows-1251' ? '1251' : 'UTF-8';
    final sb = StringBuffer();
    sb.writeln('SIZE 58 mm,30 mm');
    sb.writeln('DIRECTION 1');
    sb.writeln('REFERENCE 0,0');
    sb.writeln('DENSITY 12');
    sb.writeln('SPEED 4');
    sb.writeln('GAP 2 mm,0 mm');
    sb.writeln('CODEPAGE $cp');
    sb.writeln('CLS');
    sb.writeln('QRCODE 12,42,M,5,A,0,"TEST"');
    sb.writeln('TEXT 178,18,"0",0,1,1,"TEST PRINT"');
    sb.writeln('TEXT 178,52,"0",0,1,1,"TSC TE210 OK"');
    sb.writeln('PRINT 1,1');
    return sb.toString();
  }

  /// Кодирует TSPL-строку в байты для сокета.
  static List<int> encode(String tspl, String codepage) {
    if (codepage == 'Windows-1251') return Cp1251.encode(tspl);
    return utf8.encode(tspl);
  }

  static String _escape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';
}

/// Прямая отправка TSPL через TCP-сокет (порт 9100) на TSC TE210 по Wi-Fi.
/// Никаких драйверов и промежуточных серверов не требуется.
class TsplPrinter {
  /// Проверка доступности принтера (подключение без печати).
  Future<bool> checkConnection({
    required String ip,
    required int port,
  }) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 4),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Печать списка этикеток одним соединением (пакетная печать).
  Future<bool> printLabels({
    required String ip,
    required int port,
    required List<LabelData> labels,
    String codepage = 'UTF-8',
  }) async {
    if (labels.isEmpty) return false;
    Socket? socket;
    try {
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      for (final label in labels) {
        final tspl = TsplBuilder.buildLabel(label, codepage: codepage);
        socket.add(TsplBuilder.encode(tspl, codepage));
        await socket.flush();
        // Пауза, чтобы принтер успел отпечатать этикетку.
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      await socket.close();
      return true;
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
      return false;
    }
  }

  /// Тестовая печать одной пустой этикетки.
  Future<bool> testPrint({
    required String ip,
    required int port,
    String codepage = 'UTF-8',
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      final tspl = TsplBuilder.buildTestLabel(codepage: codepage);
      socket.add(TsplBuilder.encode(tspl, codepage));
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      try {
        await socket?.close();
      } catch (_) {}
      return false;
    }
  }
}
