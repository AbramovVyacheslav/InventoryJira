import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_jira/core/printer/tspl_printer.dart';

void main() {
  group('Cp1251.encode', () {
    test('латиница и цифры проходят как есть (ASCII)', () {
      expect(Cp1251.encode('Abc123!'), [65, 98, 99, 49, 50, 51, 33]);
    });

    test('заглавные кириллические буквы А-Я = 0xC0-0xDF', () {
      final bytes = Cp1251.encode('АБВГ');
      expect(bytes, [0xC0, 0xC1, 0xC2, 0xC3]);
    });

    test('строчные кириллические буквы а-п = 0xE0-0xEF', () {
      final bytes = Cp1251.encode('абвг');
      expect(bytes, [0xE0, 0xE1, 0xE2, 0xE3]);
    });

    test('Ё = 0xA8, ё = 0xB8', () {
      expect(Cp1251.encode('Ёё'), [0xA8, 0xB8]);
    });

    test('неподдерживаемый символ заменяется на «?»', () {
      expect(Cp1251.encode('中文'), [0x3F, 0x3F]);
    });
  });

  group('TsplBuilder.buildLabel', () {
    const label = LabelData(
      qrContent: 'IT-00042',
      name: 'Ноутбук Lenovo ThinkPad',
      objectKey: 'IT-00042',
      code1c: 'BUH-0042',
      organization: 'Головной офис',
    );

    test('содержит команды TSPL этикетки 58×30 мм', () {
      final tspl = TsplBuilder.buildLabel(label);
      expect(tspl, contains('SIZE 58 mm,30 mm'));
      expect(tspl, contains('GAP 2 mm,0 mm'));
      expect(tspl, contains('QRCODE'));
      expect(tspl, contains('IT-00042'));
      expect(tspl, contains('BUH-0042'));
      expect(tspl, contains('PRINT 1,1'));
    });

    test('UTF-8: кириллица кодируется в UTF-8 байты', () {
      final tspl = TsplBuilder.buildLabel(label);
      final bytes = Uint8List.fromList(TsplBuilder.encode(tspl, 'UTF-8'));
      expect(bytes, isNotEmpty);
      // UTF-8 кириллица — многобайтная последовательность
      expect(utf8.decode(bytes), contains('Ноутбук'));
    });

    test('Windows-1251: каждая кириллическая буква — один байт', () {
      final tspl = TsplBuilder.buildLabel(label, codepage: 'Windows-1251');
      final bytes = TsplBuilder.encode(tspl, 'Windows-1251');
      expect(bytes, contains(0xCD)); // «Н» = 0xCD в cp1251
    });

    test('кавычки в данных экранируются для TSPL', () {
      const bad = LabelData(
        qrContent: 'IT"42',
        name: 'ПК "Офис"',
        objectKey: 'IT-1',
        code1c: '1C-1',
        organization: 'ООО "Ромашка"',
      );
      final tspl = TsplBuilder.buildLabel(bad);
      expect(tspl, isNot(contains('"ПК "Офис""')));
      expect(tspl, contains(r'\"'));
    });

    test('длинное название обрезается', () {
      final longName = LabelData(
        qrContent: 'X',
        name: 'А' * 100,
        objectKey: 'K',
        code1c: '1',
        organization: 'O',
      );
      final tspl = TsplBuilder.buildLabel(longName);
      // Строка с названием не должна превышать разумную длину
      final nameLine = tspl.split('\n').firstWhere((l) => l.startsWith('TEXT 178,18'));
      expect(nameLine.length, lessThan(60));
    });
  });

  group('TsplBuilder.buildTestLabel', () {
    test('тестовая этикетка собирается без ошибок', () {
      final tspl = TsplBuilder.buildTestLabel();
      expect(tspl, contains('TEST PRINT'));
      expect(tspl, contains('PRINT 1,1'));
    });
  });
}
