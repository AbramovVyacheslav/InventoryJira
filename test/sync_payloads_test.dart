import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_jira/data/repositories/sync_payloads.dart';

void main() {
  group('SyncPayloads.move', () {
    test('формирует заявку перемещения с «Было → Стало»', () {
      final p = SyncPayloads.move(
        assetId: 42,
        assetName: 'Ноутбук',
        assetKey: 'IT-00042',
        fromRoomName: 'Кабинет 101',
        toRoomName: 'Склад А',
        operator: 'ivanov',
      );
      expect(p['assetId'], 42);
      expect(p['summary'], contains('Ноутбук'));
      expect(p['summary'], contains('IT-00042'));
      expect(p['description'], contains('Кабинет 101'));
      expect(p['description'], contains('Склад А'));
      expect(p['description'], contains('ivanov'));
    });
  });

  group('SyncPayloads.assetChange', () {
    test('фиксирует каждое изменение «Было -> Стало»', () {
      final p = SyncPayloads.assetChange(
        assetId: 7,
        assetName: 'Принтер',
        assetKey: 'IT-00007',
        changes: {
          'Состояние': ('Работает', 'Повреждено'),
          'МОЛ': ('Иванов И.И.', 'Петров П.П.'),
        },
        operator: 'sidorov',
      );
      final description = p['description'] as String;
      expect(description, contains('Состояние: Работает -> Повреждено'));
      expect(description, contains('МОЛ: Иванов И.И. -> Петров П.П.'));
      expect(description, contains('sidorov'));

      // Payload должен быть сериализуем — он сохраняется в SyncQueue как JSON.
      expect(() => jsonEncode(p), returnsNormally);
    });
  });

  group('SyncPayloads.inventoryDate', () {
    test('передаёт атрибут и значение даты', () {
      final p = SyncPayloads.inventoryDate(
        objectId: 11,
        objectTypeId: 22,
        attributeId: 33,
        value: '2026-11-16',
      );
      expect(p['objectId'], 11);
      expect(p['objectTypeId'], 22);
      expect(p['attributeId'], 33);
      expect(p['value'], '2026-11-16');
    });
  });
}
