import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_jira/data/db/app_database.dart';
import 'package:inventory_jira/features/inventory/inventory_search.dart';

Asset makeAsset({
  required int id,
  String name = 'ПК',
  String objectKey = 'IT-00001',
  String serial = 'SN-001',
  String code1c = 'BUH-0001',
  bool verified = false,
  bool foreign = false,
}) {
  return Asset(
    id: id,
    objectKey: objectKey,
    objectTypeId: 10,
    name: name,
    status: 'Работает',
    serialNumber: serial,
    code1c: code1c,
    organization: 'Головной офис',
    roomId: 1,
    roomName: 'Кабинет 101',
    molId: null,
    molName: '',
    lastInventoryDate: null,
    attributesJson: '{}',
    isVerified: verified,
    verifiedAt: null,
    isForeign: foreign,
    verifiedSessionId: null,
    updatedAt: null,
  );
}

void main() {
  group('InventorySearch.filterByQuery', () {
    final assets = [
      makeAsset(id: 1, name: 'Ноутбук Lenovo', serial: 'SER-A', code1c: '1C-AAA'),
      makeAsset(id: 2, name: 'Монитор Dell', serial: 'SER-B', code1c: '1C-BBB',
          objectKey: 'IT-00002'),
      makeAsset(id: 3, name: 'Принтер', serial: 'SER-C', code1c: '1C-CCC'),
    ];

    test('пустой запрос возвращает всё', () {
      expect(InventorySearch.filterByQuery(assets, '').length, 3);
      expect(InventorySearch.filterByQuery(assets, '   ').length, 3);
    });

    test('поиск по серийному номеру (без учёта регистра)', () {
      final r = InventorySearch.filterByQuery(assets, 'ser-a');
      expect(r.length, 1);
      expect(r.first.id, 1);
    });

    test('поиск по коду 1С', () {
      final r = InventorySearch.filterByQuery(assets, '1c-bbb');
      expect(r.length, 1);
      expect(r.first.id, 2);
    });

    test('поиск по названию', () {
      final r = InventorySearch.filterByQuery(assets, 'ноут');
      expect(r.length, 1);
      expect(r.first.id, 1);
    });

    test('поиск по ключу Jira', () {
      final r = InventorySearch.filterByQuery(assets, 'IT-00002');
      expect(r.length, 1);
      expect(r.first.id, 2);
    });
  });

  group('InventorySearch.discrepanciesOnly', () {
    test('фильтр «Только расхождения» скрывает проверенные', () {
      final assets = [
        makeAsset(id: 1, verified: true),
        makeAsset(id: 2),
        makeAsset(id: 3, verified: true),
        makeAsset(id: 4),
      ];
      final r = InventorySearch.discrepanciesOnly(assets);
      expect(r.map((a) => a.id), [2, 4]);
    });
  });

  group('счётчики', () {
    test('verifiedCount и foreignCount', () {
      final assets = [
        makeAsset(id: 1, verified: true),
        makeAsset(id: 2, verified: true, foreign: true),
        makeAsset(id: 3),
      ];
      expect(InventorySearch.verifiedCount(assets), 2);
      expect(InventorySearch.foreignCount(assets), 1);
    });
  });
}
