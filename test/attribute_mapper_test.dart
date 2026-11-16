import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_jira/data/jira/attribute_mapper.dart';
import 'package:inventory_jira/data/jira/models.dart';

AssetObject buildObject(List<Map<String, dynamic>> attrs) {
  return AssetObject(
    id: 1,
    objectKey: 'IT-00001',
    objectTypeId: 10,
    name: 'Тестовый объект',
    attributes: attrs.map(AssetAttribute.fromJson).toList(),
  );
}

void main() {
  group('AssetObject.attributeValue', () {
    final obj = buildObject([
      {'objectTypeAttributeId': 101, 'name': 'Серийный номер', 'value': 'SN-12345'},
      {'objectTypeAttributeId': 102, 'name': 'Код 1С', 'value': 'BUH-777'},
      {'objectTypeAttributeId': 103, 'name': 'МОЛ', 'value': 'Иванов И.И.'},
      {'objectTypeAttributeId': 104, 'name': 'Состояние', 'displayValue': 'Работает'},
      {'objectTypeAttributeId': 105, 'name': 'Дата последней инвентаризации', 'value': '2026-11-01'},
    ]);

    test('серийный номер и код 1С распознаются', () {
      expect(AttributeMapper.serialNumber(obj), 'SN-12345');
      expect(AttributeMapper.code1c(obj), 'BUH-777');
    });

    test('состояние и дата инвентаризации распознаются', () {
      expect(AttributeMapper.status(obj), 'Работает');
      expect(
        obj.attributeValue(AttributeMapper.lastInventoryCandidates),
        '2026-11-01',
      );
    });

    test('сравнение без учёта регистра и по вхождению', () {
      expect(obj.attributeValue(['СЕРИЙНЫЙ НОМЕР']), 'SN-12345');
      expect(obj.attributeValue(['серийный']), 'SN-12345');
    });

    test('отсутствующий атрибут даёт null / пустую строку', () {
      expect(obj.attributeValue(['несуществующее поле']), isNull);
      expect(AttributeMapper.organization(obj), '');
    });
  });

  group('AssetAttribute.fromJson (разные формы ответа Jira)', () {
    test('displayValue приоритетнее value', () {
      final a = AssetAttribute.fromJson({
        'objectTypeAttributeId': 1,
        'name': 'Состояние',
        'value': 'state-id-xyz',
        'displayValue': 'Требует ремонта',
      });
      expect(a.value, 'Требует ремонта');
    });

    test('форма objectAttributeValues (вложенные значения)', () {
      final a = AssetAttribute.fromJson({
        'objectTypeAttributeId': 2,
        'name': 'Код 1С',
        'objectAttributeValues': [
          {'value': 'BUH-001', 'displayValue': 'BUH-001 (основной)'},
        ],
      });
      expect(a.id, 2);
      expect(a.value, 'BUH-001 (основной)');
    });

    test('ссылка на связанный объект', () {
      final a = AssetAttribute.fromJson({
        'objectTypeAttributeId': 3,
        'name': 'Помещение',
        'referencedObjectId': '555',
        'displayValue': 'Кабинет 101',
      });
      expect(a.referencedObjectId, '555');
      expect(a.value, 'Кабинет 101');
    });

    test('referencedObjectId из objectAttributeValues', () {
      final a = AssetAttribute.fromJson({
        'objectTypeAttributeId': 4,
        'name': 'МОЛ',
        'objectAttributeValues': [
          {'referencedObjectId': 777, 'displayValue': 'Петров П.П.'},
        ],
      });
      expect(a.referencedObjectId, '777');
    });
  });

  group('AttributeMapper.referencedId / referencedName', () {
    test('числовой ID связанного объекта', () {
      final attr = AssetAttribute(
        id: 1,
        name: 'Помещение',
        value: 'Склад',
        referencedObjectId: '321',
      );
      expect(AttributeMapper.referencedId(attr), 321);
      expect(AttributeMapper.referencedName(attr), 'Склад');
    });

    test('битый ID даёт null, а не исключение', () {
      final attr = AssetAttribute(
        id: 1,
        name: 'x',
        value: 'y',
        referencedObjectId: 'не-число',
      );
      expect(AttributeMapper.referencedId(attr), isNull);
    });

    test('null атрибут обрабатывается безопасно', () {
      expect(AttributeMapper.referencedId(null), isNull);
      expect(AttributeMapper.referencedName(null), '');
    });
  });

  group('AssetObject.fromJson', () {
    test('полный объект со списком атрибутов', () {
      final obj = AssetObject.fromJson({
        'id': '42',
        'objectKey': 'IT-00042',
        'objectTypeId': 10,
        'name': 'Ноутбук',
        'attributes': [
          {'objectTypeAttributeId': 1, 'name': 'A', 'value': 'a'},
          {'objectTypeAttributeId': 2, 'name': 'B', 'value': 'b'},
        ],
      });
      expect(obj.id, 42);
      expect(obj.objectKey, 'IT-00042');
      expect(obj.objectTypeId, 10);
      expect(obj.attributes.length, 2);
    });

    test('битый JSON атрибутов не роняет парсинг', () {
      final obj = AssetObject.fromJson({
        'id': 1,
        'attributes': 'не-список',
      });
      expect(obj.attributes, isEmpty);
    });
  });

  group('JiraUser / JsmRequestResult', () {
    test('JiraUser из /myself', () {
      final u = JiraUser.fromJson({
        'name': 'i.ivanov',
        'displayName': 'Иванов Иван Иванович',
        'emailAddress': 'i.ivanov@example.com',
      });
      expect(u.name, 'i.ivanov');
      expect(u.displayName, 'Иванов Иван Иванович');
      expect(u.email, 'i.ivanov@example.com');
    });

    test('JiraUser без displayName откатывается к name', () {
      final u = JiraUser.fromJson({'name': 'j.doe'});
      expect(u.displayName, 'j.doe');
    });

    test('JsmRequestResult из ответа создания заявки', () {
      final r = JsmRequestResult.fromJson({
        'issueKey': 'HELP-123',
        'issueId': '10001',
      });
      expect(r.issueKey, 'HELP-123');
      expect(r.issueId, '10001');
    });
  });
}
