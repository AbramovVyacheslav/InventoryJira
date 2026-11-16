import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_jira/data/db/app_database.dart';

/// Тесты локальной БД (in-memory Drift/SQLite).
/// Проверяют ключевые сценарии, из-за которых приложение
/// не должно терять данные при прерывании инвентаризации.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedRoom({int id = 1, String name = 'Кабинет 101'}) {
    return db.into(db.rooms).insert(
          RoomsCompanion.insert(
            id: id,
            name: name,
            barcode: const drift.Value('ROOM-101'),
          ),
        );
  }

  Future<int> seedAsset({
    required int id,
    String serial = '',
    String code1c = '',
    int? roomId = 1,
  }) {
    return db.into(db.assets).insert(
          AssetsCompanion.insert(
            id: id,
            objectKey: drift.Value('IT-${id.toString().padLeft(5, '0')}'),
            objectTypeId: const drift.Value(10),
            name: drift.Value('Актив $id'),
            serialNumber: drift.Value(serial),
            code1c: drift.Value(code1c),
            roomId: drift.Value(roomId),
            roomName: const drift.Value('Кабинет 101'),
          ),
        );
  }

  test('getByCode находит актив по серийнику, коду 1С и ключу Jira', () async {
    await seedRoom();
    await seedAsset(id: 11, serial: 'SN-XYZ', code1c: '1C-XYZ');

    expect((await db.assetDao.getByCode('SN-XYZ'))?.id, 11);
    expect((await db.assetDao.getByCode('1C-XYZ'))?.id, 11);
    expect((await db.assetDao.getByCode('IT-00011'))?.id, 11);
    expect((await db.assetDao.getByCode('11'))?.id, 11);
    expect(await db.assetDao.getByCode('НЕТ-ТАКОГО'), isNull);
  });

  test('markVerified помечает актив проверенным и ставит дату инвентаризации', () async {
    await seedRoom();
    await seedAsset(id: 21);
    await db.assetDao.markVerified(
      assetId: 21,
      sessionId: 1,
      date: DateTime(2026, 11, 16),
    );
    final asset = await db.assetDao.getById(21);
    expect(asset!.isVerified, isTrue);
    expect(asset.lastInventoryDate, isNotNull);
    expect(asset.verifiedSessionId, 1);
  });

  test('moveToRoom перемещает актив и помечает его чужим', () async {
    await seedRoom(id: 1);
    await seedRoom(id: 2, name: 'Склад А');
    await seedAsset(id: 31, roomId: 2);
    await db.assetDao.moveToRoom(
      assetId: 31,
      roomId: 1,
      roomName: 'Кабинет 101',
      sessionId: 9,
      date: DateTime(2026, 11, 16),
    );
    final asset = await db.assetDao.getById(31);
    expect(asset!.roomId, 1);
    expect(asset.isVerified, isTrue);
    expect(asset.isForeign, isTrue);
  });

  test('resetVerification очищает результаты проверки (новая инвентаризация)', () async {
    await seedRoom();
    await seedAsset(id: 41);
    await db.assetDao.markVerified(
      assetId: 41,
      sessionId: 1,
      date: DateTime(2026, 11, 16),
    );
    await db.assetDao.resetVerification();
    final asset = await db.assetDao.getById(41);
    expect(asset!.isVerified, isFalse);
    expect(asset.isForeign, isFalse);
    expect(asset.verifiedAt, isNull);
  });

  test('очередь синхронизации: enqueue → getPending → markSent', () async {
    await seedRoom();
    await seedAsset(id: 51);
    await db.syncQueueDao.enqueue(
      type: 'move',
      assetId: 51,
      payloadJson: '{"summary":"Перемещение"}',
    );

    final pending = await db.syncQueueDao.getPending();
    expect(pending.length, 1);
    expect(pending.first.type, 'move');
    expect(pending.first.status, 'pending');

    await db.syncQueueDao.markSent(pending.first.id, issueKey: 'HELP-1');
    expect(await db.syncQueueDao.getPending(), isEmpty);
  });

  test('markFailed переводит запись в failed и увеличивает счётчик попыток', () async {
    await seedRoom();
    await seedAsset(id: 61);
    await db.syncQueueDao.enqueue(
      type: 'inventoryDate',
      assetId: 61,
      payloadJson: '{}',
    );
    final pending = await db.syncQueueDao.getPending();
    await db.syncQueueDao.markFailed(pending.first.id, 'нет сети');

    final all = await db.syncQueueDao.watchAll().first;
    expect(all.first.status, 'failed');
    expect(all.first.retryCount, 1);
    expect(all.first.lastError, 'нет сети');
  });

  test('настройки сохраняются и переживают «перезапуск» (новая сессия DAO)', () async {
    await db.settingsDao.saveSettings(
      const AppSettingsCompanion(
        jiraBaseUrl: drift.Value('https://jira.example.com'),
        printerIp: drift.Value('192.168.1.50'),
      ),
    );
    final s = await db.settingsDao.getSettings();
    expect(s!.jiraBaseUrl, 'https://jira.example.com');
    expect(s.printerIp, '192.168.1.50');
    expect(s.printerPort, 9100); // дефолт
  });

  test('сессия инвентаризации создаётся и продолжается (getActiveSession)', () async {
    await seedRoom();
    final sessionId = await db.sessionDao.createSession(
      roomId: 1,
      roomName: 'Кабинет 101',
      operatorLogin: 'ivanov',
      totalExpected: 5,
    );
    final active = await db.sessionDao.getActiveSession(1);
    expect(active, isNotNull);
    expect(active!.id, sessionId);

    await db.sessionDao.finishSession(sessionId);
    expect(await db.sessionDao.getActiveSession(1), isNull);
  });
}
