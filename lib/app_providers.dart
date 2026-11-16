import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/feedback/feedback_service.dart';
import 'core/logger/app_logger.dart';
import 'core/network/network_monitor.dart';
import 'core/printer/tspl_printer.dart';
import 'core/scanner/scanner_service.dart';
import 'data/db/app_database.dart';
import 'data/jira/jira_client.dart';
import 'data/repositories/asset_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/sync_engine.dart';

/// База данных (переопределяется в main() после открытия файла).
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('databaseProvider должен быть переопределён в main()');
});

final loggerProvider = Provider<AppLogger>((ref) => AppLogger());

final feedbackProvider = Provider<FeedbackService>((ref) {
  final service = FeedbackService();
  ref.onDispose(service.dispose);
  return service;
});

final scannerProvider = Provider<ScannerService>((ref) {
  final service = ScannerService();
  ref.onDispose(service.dispose);
  return service;
});

final networkMonitorProvider = Provider<NetworkMonitor>((ref) => NetworkMonitor());

final printerProvider = Provider<TsplPrinter>((ref) => TsplPrinter());

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

final assetRepositoryProvider = Provider<AssetRepository>((ref) {
  return AssetRepository(
    db: ref.watch(databaseProvider),
    logger: ref.watch(loggerProvider),
  );
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    db: ref.watch(databaseProvider),
    settingsRepo: ref.watch(settingsRepositoryProvider),
    logger: ref.watch(loggerProvider),
  );
});

/// Настройки приложения (локальная БД).
final settingsProvider = FutureProvider<AppSetting?>((ref) async {
  return ref.watch(databaseProvider).settingsDao.getSettings();
});

/// Клиент Jira на сервисном аккаунте (null — не настроен).
final jiraClientProvider = FutureProvider<JiraClient?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  return ref.watch(settingsRepositoryProvider).buildClient(settings);
});

/// Количество неотправленных записей в очереди (бейдж на главном экране).
final pendingCountProvider = StreamProvider<int>((ref) {
  return ref.watch(databaseProvider).syncQueueDao.watchAll().map(
        (items) => items.where((i) => i.status == 'pending').length,
      );
});

/// Статус сетевого принтера (зелёный/красный индикатор).
final printerStatusProvider = StateProvider<bool>((ref) => false);

/// Онлайн-статус сети.
final onlineProvider = StreamProvider<bool>((ref) {
  return ref.watch(networkMonitorProvider).onlineStream;
});

/// Уровень батареи ТСД (сервисная панель).
final batteryLevelProvider = StreamProvider<int>((ref) async* {
  final battery = Battery();
  yield await battery.getBatteryLevel();
  await for (final _ in battery.onBatteryStateChanged) {
    yield await battery.getBatteryLevel();
  }
});

/// Список помещений (снимок из Jira).
final roomsStreamProvider = StreamProvider<List<Room>>((ref) {
  return ref.watch(databaseProvider).roomDao.watchAll();
});

/// Список сотрудников (снимок из Jira).
final employeesStreamProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(databaseProvider).employeeDao.watchAll();
});

/// Полная очередь синхронизации (экран «Монитор синхронизации»).
final syncQueueStreamProvider = StreamProvider<List<SyncQueueItem>>((ref) {
  return ref.watch(databaseProvider).syncQueueDao.watchAll();
});

/// Техника текущего кабинета (экран инвентаризации).
final roomAssetsProvider =
    StreamProvider.family<List<Asset>, int>((ref, roomId) {
  return ref.watch(databaseProvider).assetDao.watchByRoom(roomId);
});
