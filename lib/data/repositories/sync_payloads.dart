/// Построители payload'ов очереди синхронизации (чистые функции,
/// покрыты юнит-тестами).
///
/// Очередь SyncQueueItems хранит JSON; движок синхронизации
/// интерпретирует его по типу записи:
///  - move:          заявка JSM «Перемещение»
///  - inventoryDate: обновление атрибута «Дата последней инвентаризации»
///  - assetChange:   заявка JSM «Изменение данных» (Было -> Стало) + фото
class SyncPayloads {
  static Map<String, dynamic> move({
    required int assetId,
    required String assetName,
    required String assetKey,
    required String fromRoomName,
    required String toRoomName,
    required String operator,
  }) {
    return {
      'assetId': assetId,
      'summary': 'Перемещение: $assetName ($assetKey)',
      'description':
          'Заявка создана автоматически при инвентаризации.\n'
          'Актив: $assetName ($assetKey)\n'
          'Было (помещение): $fromRoomName\n'
          'Стало (помещение): $toRoomName\n'
          'Оператор: $operator',
    };
  }

  static Map<String, dynamic> inventoryDate({
    required int objectId,
    required int objectTypeId,
    required int attributeId,
    required String value,
  }) {
    return {
      'objectId': objectId,
      'objectTypeId': objectTypeId,
      'attributeId': attributeId,
      'value': value,
    };
  }

  static Map<String, dynamic> assetChange({
    required int assetId,
    required String assetName,
    required String assetKey,
    required Map<String, (String, String)> changes,
    required String operator,
  }) {
    final buffer = StringBuffer()
      ..writeln('Изменение данных актива (автоматически при инвентаризации).')
      ..writeln('Актив: $assetName ($assetKey)')
      ..writeln('Оператор: $operator')
      ..writeln();
    changes.forEach((field, pair) {
      buffer.writeln('$field: ${pair.$1} -> ${pair.$2}');
    });
    return {
      'assetId': assetId,
      'summary': 'Изменение данных: $assetName ($assetKey)',
      'description': buffer.toString(),
    };
  }
}
