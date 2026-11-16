import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/logger/app_logger.dart';
import '../../data/db/app_database.dart';
import '../../data/jira/attribute_mapper.dart';
import '../../data/jira/jira_client.dart';
import 'sync_payloads.dart';

class SnapshotResult {
  final int assets;
  final int rooms;
  final int employees;

  const SnapshotResult({
    required this.assets,
    required this.rooms,
    required this.employees,
  });
}

/// Репозиторий активов: снимок из Jira + локальные операции инвентаризации.
class AssetRepository {
  final AppDatabase db;
  final AppLogger logger;

  AssetRepository({required this.db, required this.logger});

  // -------------------------------------------------------------------------
  // Снимок данных из Jira Assets
  // -------------------------------------------------------------------------

  /// Скачивает актуальный срез (активы, помещения, сотрудники) из Jira
  /// в локальную БД. Старые результаты проверки очищаются.
  ///
  /// Классификация типов объектов одной схемы (эвристика по атрибутам,
  /// см. README «Как устроен снимок»):
  ///  - есть e-mail → сотрудник;
  ///  - есть серийник/код 1С/ссылка на помещение или МОЛ → актив;
  ///  - иначе → помещение.
  Future<SnapshotResult> downloadSnapshot({
    required JiraClient client,
    required String schemaId,
  }) async {
    logger.info('Snapshot: запрос объектов схемы $schemaId');
    final objects = await client.searchAllObjects(schemaId: schemaId);
    logger.info('Snapshot: получено объектов: ${objects.length}');

    final assetRows = <AssetsCompanion>[];
    final roomRows = <RoomsCompanion>[];
    final employeeRows = <EmployeesCompanion>[];

    for (final obj in objects) {
      final email = obj.attributeValue(['email', 'почта', 'e-mail']);
      final serial = AttributeMapper.serialNumber(obj);
      final code1c = AttributeMapper.code1c(obj);
      final roomAttr = AttributeMapper.roomAttribute(obj);
      final molAttr = AttributeMapper.molAttribute(obj);

      if (email != null && email.contains('@')) {
        employeeRows.add(
          EmployeesCompanion(
            id: Value(obj.id),
            name: Value(obj.name.isNotEmpty ? obj.name : obj.objectKey),
            email: Value(email),
            department: Value(
              obj.attributeValue(['отдел', 'department', 'подразделение']) ?? '',
            ),
          ),
        );
      } else if (serial.isNotEmpty ||
          code1c.isNotEmpty ||
          roomAttr != null ||
          molAttr != null) {
        final attrsJson = jsonEncode({
          for (final a in obj.attributes) '${a.id}': a.toJson(),
        });
        assetRows.add(
          AssetsCompanion(
            id: Value(obj.id),
            objectKey: Value(obj.objectKey),
            objectTypeId: Value(obj.objectTypeId),
            name: Value(obj.name.isNotEmpty ? obj.name : obj.objectKey),
            status: Value(AttributeMapper.status(obj)),
            serialNumber: Value(serial),
            code1c: Value(code1c),
            organization: Value(AttributeMapper.organization(obj)),
            roomId: Value(AttributeMapper.referencedId(roomAttr)),
            roomName: Value(AttributeMapper.referencedName(roomAttr)),
            molId: Value(AttributeMapper.referencedId(molAttr)),
            molName: Value(AttributeMapper.referencedName(molAttr)),
            attributesJson: Value(attrsJson),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        roomRows.add(
          RoomsCompanion(
            id: Value(obj.id),
            name: Value(obj.name.isNotEmpty ? obj.name : obj.objectKey),
            barcode: Value(
              obj.attributeValue([
                    'штрихкод',
                    'qr-код',
                    'qr',
                    'barcode',
                    'код помещения',
                  ]) ??
                  '',
            ),
            description: Value(
              obj.attributeValue(['описание', 'description']) ?? '',
            ),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }

    await db.transaction(() async {
      await db.assetDao.clearAll();
      await db.roomDao.clearAll();
      await db.employeeDao.clearAll();
      await db.assetDao.upsertAssets(assetRows);
      await db.roomDao.upsertRooms(roomRows);
      await db.employeeDao.upsertEmployees(employeeRows);
    });
    await db.settingsDao.setLastSnapshotAt(DateTime.now());
    logger.info(
      'Snapshot: активов ${assetRows.length}, помещений ${roomRows.length}, '
      'сотрудников ${employeeRows.length}',
    );
    return SnapshotResult(
      assets: assetRows.length,
      rooms: roomRows.length,
      employees: employeeRows.length,
    );
  }

  // -------------------------------------------------------------------------
  // Операции инвентаризации
  // -------------------------------------------------------------------------

  Future<Asset?> findByCode(String code) => db.assetDao.getByCode(code);

  /// «Свой» актив: помечен проверенным, дата инвентаризации —
  /// локально и (через очередь) в Jira.
  Future<void> markVerified({
    required Asset asset,
    required int sessionId,
    required String operator,
  }) async {
    final now = DateTime.now();
    await db.assetDao.markVerified(
      assetId: asset.id,
      sessionId: sessionId,
      date: now,
    );
    await _enqueueInventoryDate(asset, now);
  }

  /// «Чужой» актив: перемещение в текущий кабинет + заявка JSM в очередь.
  Future<void> moveToRoom({
    required Asset asset,
    required Room room,
    required int sessionId,
    required String operator,
  }) async {
    final now = DateTime.now();
    await db.assetDao.moveToRoom(
      assetId: asset.id,
      roomId: room.id,
      roomName: room.name,
      sessionId: sessionId,
      date: now,
    );
    await db.syncQueueDao.enqueue(
      type: 'move',
      assetId: asset.id,
      payloadJson: jsonEncode(
        SyncPayloads.move(
          assetId: asset.id,
          assetName: asset.name,
          assetKey: asset.objectKey,
          fromRoomName: asset.roomName.isNotEmpty
              ? asset.roomName
              : 'не указано',
          toRoomName: room.name,
          operator: operator,
        ),
      ),
    );
    await _enqueueInventoryDate(asset, now);
  }

  Future<void> updateMol({
    required Asset asset,
    required Employee employee,
  }) async {
    await db.assetDao.updateMol(
      assetId: asset.id,
      molId: employee.id,
      molName: employee.name,
    );
  }

  /// Сохранение правок карточки: локально сразу, заявка «Было -> Стало»
  /// в очередь (прозрачность изменений в Jira).
  Future<void> saveAssetChanges({
    required Asset asset,
    required Map<String, (String, String)> changes,
    required String operator,
    String photoPath = '',
    String? newStatus,
    Employee? newMol,
  }) async {
    if (newStatus != null && newStatus != asset.status) {
      await db.assetDao.updateStatus(assetId: asset.id, status: newStatus);
    }
    if (newMol != null && newMol.id != asset.molId) {
      await updateMol(asset: asset, employee: newMol);
    }
    if (changes.isNotEmpty || photoPath.isNotEmpty) {
      await db.syncQueueDao.enqueue(
        type: 'assetChange',
        assetId: asset.id,
        payloadJson: jsonEncode(
          SyncPayloads.assetChange(
            assetId: asset.id,
            assetName: asset.name,
            assetKey: asset.objectKey,
            changes: changes,
            operator: operator,
          ),
        ),
        photoPath: photoPath,
      );
    }
  }

  Future<void> _enqueueInventoryDate(Asset asset, DateTime date) async {
    final attrId = _findAttributeId(
      asset.attributesJson,
      AttributeMapper.lastInventoryCandidates,
    );
    if (attrId == null) {
      logger.warn(
        'Asset ${asset.id}: атрибут «Дата последней инвентаризации» '
        'не найден, обновление в Jira пропущено',
      );
      return;
    }
    final value =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    await db.syncQueueDao.enqueue(
      type: 'inventoryDate',
      assetId: asset.id,
      payloadJson: jsonEncode(
        SyncPayloads.inventoryDate(
          objectId: asset.id,
          objectTypeId: asset.objectTypeId,
          attributeId: attrId,
          value: value,
        ),
      ),
    );
  }

  int? _findAttributeId(String attributesJson, List<String> candidates) {
    try {
      final decoded = jsonDecode(attributesJson);
      if (decoded is! Map<String, dynamic>) return null;
      final lower = candidates.map((c) => c.toLowerCase()).toList();
      for (final entry in decoded.entries) {
        final v = entry.value;
        if (v is Map<String, dynamic>) {
          final name = (v['name'] ?? '').toString().toLowerCase();
          for (final c in lower) {
            if (name == c || name.contains(c)) {
              return int.tryParse(entry.key);
            }
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
