import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Локальная БД на устройстве (Drift / SQLite).
///
/// Зачем: мгновенный отклик сканера и автономность на ТСД.
/// Сессия инвентаризации сохраняется локально и может прерываться
/// на дни (уйти на выходные — продолжить в понедельник без потери данных).
///
/// Никаких серверных БД на стороне компании не создаётся:
/// приложение общается напрямую с Jira Assets / Jira Service Management.
///
/// ВАЖНО: после изменения таблиц выполните генерацию кода:
///   dart run build_runner build --delete-conflicting-outputs
/// (см. README, раздел «Быстрый старт»).

// ---------------------------------------------------------------------------
// Настройки приложения (одна строка, id = 1)
// ---------------------------------------------------------------------------

class AppSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get jiraBaseUrl => text().withDefault(const Constant(''))();
  TextColumn get jiraServiceLogin => text().withDefault(const Constant(''))();
  TextColumn get jiraApiToken => text().withDefault(const Constant(''))();
  TextColumn get objectSchemaId => text().withDefault(const Constant(''))();

  /// Jira Service Management: заявки на перемещение и изменение данных.
  TextColumn get serviceDeskId => text().withDefault(const Constant(''))();
  TextColumn get requestTypeMoveId => text().withDefault(const Constant(''))();
  TextColumn get requestTypeChangeId => text().withDefault(const Constant(''))();

  /// Принтер этикеток TSC TE210.
  TextColumn get printerIp => text().withDefault(const Constant(''))();
  IntColumn get printerPort => integer().withDefault(const Constant(9100))();
  TextColumn get printerCodepage =>
      text().withDefault(const Constant('UTF-8'))();

  /// Текущая сессия пользователя.
  TextColumn get currentUserLogin => text().withDefault(const Constant(''))();
  TextColumn get currentUserName => text().withDefault(const Constant(''))();

  DateTimeColumn get lastSnapshotAt => dateTime().nullable()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Активы (снимок из Jira Assets)
// ---------------------------------------------------------------------------

class Assets extends Table {
  /// ID объекта в Jira Assets.
  IntColumn get id => integer()();
  TextColumn get objectKey => text().withDefault(const Constant(''))();
  IntColumn get objectTypeId => integer().withDefault(const Constant(0))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant(''))();
  TextColumn get serialNumber => text().withDefault(const Constant(''))();
  TextColumn get code1c => text().withDefault(const Constant(''))();
  TextColumn get organization => text().withDefault(const Constant(''))();

  /// Помещение, где актив должен находиться (по Jira).
  IntColumn get roomId => integer().nullable()();
  TextColumn get roomName => text().withDefault(const Constant(''))();

  /// Пользователь (МОЛ).
  IntColumn get molId => integer().nullable()();
  TextColumn get molName => text().withDefault(const Constant(''))();

  DateTimeColumn get lastInventoryDate => dateTime().nullable()();

  /// Все динамические атрибуты из Jira (JSON: {attrId: {name, value, ...}}).
  /// Приложение подтягивает новые реквизиты без изменения кода.
  TextColumn get attributesJson => text().withDefault(const Constant('{}'))();

  /// Локальный статус проверки в текущей сессии.
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get verifiedAt => dateTime().nullable()();
  BoolColumn get isForeign => boolean().withDefault(const Constant(false))();
  IntColumn get verifiedSessionId => integer().nullable()();

  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Помещения, сотрудники, очередь синхронизации, сессии
// ---------------------------------------------------------------------------

class Rooms extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get barcode => text().withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Employees extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get email => text().withDefault(const Constant(''))();
  TextColumn get department => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Локальная очередь отправки в Jira (офлайн-устойчивость).
/// Заявки складываются сюда при отсутствии Wi-Fi и отправляются
/// автоматически при восстановлении сети.
class SyncQueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// move | inventoryDate | assetChange
  TextColumn get type => text()();
  IntColumn get assetId => integer()();
  TextColumn get payloadJson => text()();

  /// pending | sending | failed | sent
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().withDefault(const Constant(''))();
  TextColumn get jiraIssueKey => text().withDefault(const Constant(''))();
  TextColumn get photoPath => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}

class InventorySessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get roomId => integer()();
  TextColumn get roomName => text().withDefault(const Constant(''))();
  TextColumn get operatorLogin => text().withDefault(const Constant(''))();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get totalExpected => integer().withDefault(const Constant(0))();
  IntColumn get totalFound => integer().withDefault(const Constant(0))();
  IntColumn get totalForeign => integer().withDefault(const Constant(0))();
}

// ---------------------------------------------------------------------------
// База данных
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [
  AppSettings,
  Assets,
  Rooms,
  Employees,
  SyncQueueItems,
  InventorySessions,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Открытие БД в каталоге документов приложения.
  static Future<AppDatabase> openInDocuments() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, 'inventory.sqlite'));
    return AppDatabase(NativeDatabase.createInBackground(file));
  }

  /// In-memory БД (для тестов).
  factory AppDatabase.inMemory() =>
      AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Миграции добавляются по мере роста схемы.
        },
      );

  late final SettingsDao settingsDao = SettingsDao(this);
  late final AssetDao assetDao = AssetDao(this);
  late final RoomDao roomDao = RoomDao(this);
  late final EmployeeDao employeeDao = EmployeeDao(this);
  late final SyncQueueDao syncQueueDao = SyncQueueDao(this);
  late final SessionDao sessionDao = SessionDao(this);
}

// ---------------------------------------------------------------------------
// DAO: настройки
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<AppSetting?> getSettings() async {
    final query = select(appSettings)..where((t) => t.id.equals(1));
    return query.getSingleOrNull();
  }

  Stream<AppSetting?> watchSettings() {
    final query = select(appSettings)..where((t) => t.id.equals(1));
    return query.watchSingleOrNull();
  }

  Future<void> saveSettings(AppSettingsCompanion companion) async {
    await into(appSettings).insertOnConflictUpdate(
      companion.copyWith(id: const Value(1)),
    );
  }

  Future<void> setCurrentUser(String login, String displayName) async {
    await saveSettings(
      AppSettingsCompanion(
        currentUserLogin: Value(login),
        currentUserName: Value(displayName),
      ),
    );
  }

  Future<void> logout() async {
    await saveSettings(
      const AppSettingsCompanion(
        currentUserLogin: Value(''),
        currentUserName: Value(''),
      ),
    );
  }

  Future<void> setLastSnapshotAt(DateTime date) async {
    await saveSettings(
      AppSettingsCompanion(lastSnapshotAt: Value(date)),
    );
  }

  Future<void> setLastSyncAt(DateTime date) async {
    await saveSettings(
      AppSettingsCompanion(lastSyncAt: Value(date)),
    );
  }
}

// ---------------------------------------------------------------------------
// DAO: активы
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Assets])
class AssetDao extends DatabaseAccessor<AppDatabase> with _$AssetDaoMixin {
  AssetDao(super.db);

  Stream<List<Asset>> watchAll() {
    final query = select(assets)..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Stream<List<Asset>> watchByRoom(int roomId) {
    final query = select(assets)
      ..where((t) => t.roomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Future<Asset?> getById(int id) async {
    final query = select(assets)..where((t) => t.id.equals(id));
    return query.getSingleOrNull();
  }

  /// Поиск актива по считанному коду: ключ Jira, серийный номер,
  /// код 1С или числовой ID объекта.
  Future<Asset?> getByCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final query = select(assets)
      ..where(
        (t) =>
            t.objectKey.equals(c) |
            t.serialNumber.equals(c) |
            t.code1c.equals(c),
      );
    final found = await query.get();
    if (found.isNotEmpty) return found.first;
    final asInt = int.tryParse(c);
    if (asInt != null) return getById(asInt);
    return null;
  }

  Future<void> upsertAssets(List<AssetsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(assets, rows);
    });
  }

  Future<void> clearAll() async {
    await delete(assets).go();
  }

  /// Сброс результатов проверки при старте новой инвентаризации.
  Future<void> resetVerification() async {
    await (update(assets)
          ..where((t) => t.isVerified.equals(true) | t.isForeign.equals(true)))
        .write(
      const AssetsCompanion(
        isVerified: Value(false),
        isForeign: Value(false),
        verifiedAt: Value(null),
        verifiedSessionId: Value(null),
      ),
    );
  }

  Future<void> markVerified({
    required int assetId,
    required int sessionId,
    required DateTime date,
  }) async {
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        isVerified: const Value(true),
        verifiedAt: Value(date),
        lastInventoryDate: Value(date),
        verifiedSessionId: Value(sessionId),
        updatedAt: Value(date),
      ),
    );
  }

  /// «Чужое» оборудование: перемещение в текущий кабинет.
  Future<void> moveToRoom({
    required int assetId,
    required int roomId,
    required String roomName,
    required int sessionId,
    required DateTime date,
  }) async {
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        roomId: Value(roomId),
        roomName: Value(roomName),
        isVerified: const Value(true),
        isForeign: const Value(true),
        verifiedAt: Value(date),
        lastInventoryDate: Value(date),
        verifiedSessionId: Value(sessionId),
        updatedAt: Value(date),
      ),
    );
  }

  Future<void> updateMol({
    required int assetId,
    required int molId,
    required String molName,
  }) async {
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        molId: Value(molId),
        molName: Value(molName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateStatus({
    required int assetId,
    required String status,
  }) async {
    await (update(assets)..where((t) => t.id.equals(assetId))).write(
      AssetsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DAO: помещения и сотрудники
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Rooms])
class RoomDao extends DatabaseAccessor<AppDatabase> with _$RoomDaoMixin {
  RoomDao(super.db);

  Stream<List<Room>> watchAll() {
    final query = select(rooms)..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Future<Room?> getById(int id) async {
    final query = select(rooms)..where((t) => t.id.equals(id));
    return query.getSingleOrNull();
  }

  Future<Room?> getByBarcode(String code) async {
    final query = select(rooms)..where((t) => t.barcode.equals(code.trim()));
    return query.getSingleOrNull();
  }

  Future<void> upsertRooms(List<RoomsCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(rooms, rows);
    });
  }

  Future<void> clearAll() async {
    await delete(rooms).go();
  }
}

@DriftAccessor(tables: [Employees])
class EmployeeDao extends DatabaseAccessor<AppDatabase>
    with _$EmployeeDaoMixin {
  EmployeeDao(super.db);

  Stream<List<Employee>> watchAll() {
    final query = select(employees)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Future<List<Employee>> getAll() async {
    final query = select(employees)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.get();
  }

  Future<void> upsertEmployees(List<EmployeesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(employees, rows);
    });
  }

  Future<void> clearAll() async {
    await delete(employees).go();
  }
}

// ---------------------------------------------------------------------------
// DAO: очередь синхронизации
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [SyncQueueItems])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  Future<int> enqueue({
    required String type,
    required int assetId,
    required String payloadJson,
    String photoPath = '',
  }) async {
    return into(syncQueueItems).insert(
      SyncQueueItemsCompanion(
        type: Value(type),
        assetId: Value(assetId),
        payloadJson: Value(payloadJson),
        photoPath: Value(photoPath),
        status: const Value('pending'),
        createdAt: Value(DateTime.now()),
      ),
    );
  }

  Stream<List<SyncQueueItem>> watchAll() {
    final query = select(syncQueueItems)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  Future<List<SyncQueueItem>> getPending({int limit = 50}) async {
    final query = select(syncQueueItems)
      ..where((t) => t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<void> markSending(int id) async {
    await (update(syncQueueItems)..where((t) => t.id.equals(id))).write(
      SyncQueueItemsCompanion(
        status: const Value('sending'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markSent(int id, {String issueKey = ''}) async {
    await (update(syncQueueItems)..where((t) => t.id.equals(id))).write(
      SyncQueueItemsCompanion(
        status: const Value('sent'),
        jiraIssueKey: Value(issueKey),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markFailed(int id, String error) async {
    final current = await (select(syncQueueItems)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    final retries = (current?.retryCount ?? 0) + 1;
    await (update(syncQueueItems)..where((t) => t.id.equals(id))).write(
      SyncQueueItemsCompanion(
        status: const Value('failed'),
        lastError: Value(error),
        retryCount: Value(retries),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> countByStatus(String status) async {
    final query = selectOnly(syncQueueItems)
      ..addColumns([syncQueueItems.id.count()])
      ..where(syncQueueItems.status.equals(status));
    final row = await query.getSingle();
    return row.read(syncQueueItems.id.count()) ?? 0;
  }

  Future<int> get pendingCount => countByStatus('pending');
  Future<int> get failedCount => countByStatus('failed');
  Future<int> get sentCount => countByStatus('sent');
}

// ---------------------------------------------------------------------------
// DAO: сессии инвентаризации
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [InventorySessions])
class SessionDao extends DatabaseAccessor<AppDatabase>
    with _$SessionDaoMixin {
  SessionDao(super.db);

  Future<int> createSession({
    required int roomId,
    required String roomName,
    required String operatorLogin,
    required int totalExpected,
  }) async {
    return into(inventorySessions).insert(
      InventorySessionsCompanion(
        roomId: Value(roomId),
        roomName: Value(roomName),
        operatorLogin: Value(operatorLogin),
        startedAt: Value(DateTime.now()),
        totalExpected: Value(totalExpected),
      ),
    );
  }

  Future<InventorySession?> getActiveSession(int roomId) async {
    final query = select(inventorySessions)
      ..where(
        (t) => t.roomId.equals(roomId) & t.finishedAt.isNull(),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    final list = await query.get();
    return list.isEmpty ? null : list.first;
  }

  Future<void> updateProgress({
    required int sessionId,
    required int found,
    required int foreign,
  }) async {
    await (update(inventorySessions)..where((t) => t.id.equals(sessionId)))
        .write(
      InventorySessionsCompanion(
        totalFound: Value(found),
        totalForeign: Value(foreign),
      ),
    );
  }

  Future<void> finishSession(int sessionId) async {
    await (update(inventorySessions)..where((t) => t.id.equals(sessionId)))
        .write(
      InventorySessionsCompanion(
        finishedAt: Value(DateTime.now()),
      ),
    );
  }
}
