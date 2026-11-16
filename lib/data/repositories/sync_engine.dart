import 'dart:convert';
import 'dart:io';

import '../../core/logger/app_logger.dart';
import '../../data/db/app_database.dart';
import '../../data/jira/jira_client.dart';
import '../../data/jira/models.dart';
import 'settings_repository.dart';

class SyncRunResult {
  final int sent;
  final int failed;
  final bool skipped;

  const SyncRunResult({required this.sent, required this.failed, this.skipped = false});
}

/// Фоновая отправка очереди в Jira.
///
/// Защита от падения Wi-Fi: заявки складываются в локальную очередь
/// (SyncQueueItems) и отправляются автоматически при восстановлении
/// сети (см. NetworkMonitor) либо вручную с экрана «Монитор синхронизации».
class SyncEngine {
  final AppDatabase db;
  final SettingsRepository settingsRepo;
  final AppLogger logger;

  bool _running = false;

  SyncEngine({
    required this.db,
    required this.settingsRepo,
    required this.logger,
  });

  Future<SyncRunResult> processQueue() async {
    if (_running) {
      return const SyncRunResult(sent: 0, failed: 0, skipped: true);
    }
    _running = true;
    var sent = 0;
    var failed = 0;
    try {
      final settings = await settingsRepo.load();
      final client = settingsRepo.buildClient(settings);
      if (client == null || settings == null) {
        logger.warn('Sync: Jira не настроен, очередь отложена');
        return const SyncRunResult(sent: 0, failed: 0, skipped: true);
      }

      final items = await db.syncQueueDao.getPending(limit: 100);
      for (final item in items) {
        await db.syncQueueDao.markSending(item.id);
        try {
          final payload =
              jsonDecode(item.payloadJson) as Map<String, dynamic>;
          final issueKey = await _sendOne(
            client: client,
            settings: settings,
            type: item.type,
            payload: payload,
            photoPath: item.photoPath,
          );
          await db.syncQueueDao.markSent(item.id, issueKey: issueKey);
          sent++;
        } catch (e) {
          await db.syncQueueDao.markFailed(item.id, e.toString());
          failed++;
          logger.error('Sync: запись ${item.id} (${item.type}) не отправлена', e);
        }
      }
      if (sent > 0) {
        await db.settingsDao.setLastSyncAt(DateTime.now());
      }
      return SyncRunResult(sent: sent, failed: failed);
    } finally {
      _running = false;
    }
  }

  Future<String> _sendOne({
    required JiraClient client,
    required AppSetting settings,
    required String type,
    required Map<String, dynamic> payload,
    required String photoPath,
  }) async {
    switch (type) {
      case 'move':
        _requireJsm(settings, move: true);
        final res = await client.createRequest(
          serviceDeskId: settings.serviceDeskId,
          requestTypeId: settings.requestTypeMoveId,
          summary: (payload['summary'] ?? 'Перемещение').toString(),
          description: (payload['description'] ?? '').toString(),
        );
        return res.issueKey;
      case 'assetChange':
        _requireJsm(settings, move: false);
        final res = await client.createRequest(
          serviceDeskId: settings.serviceDeskId,
          requestTypeId: settings.requestTypeChangeId,
          summary: (payload['summary'] ?? 'Изменение данных').toString(),
          description: (payload['description'] ?? '').toString(),
        );
        if (photoPath.isNotEmpty && await File(photoPath).exists()) {
          await client.uploadAttachment(
            issueKey: res.issueKey,
            filePath: photoPath,
          );
        }
        return res.issueKey;
      case 'inventoryDate':
        await client.updateObjectAttribute(
          objectId: _toInt(payload['objectId']),
          objectTypeId: _toInt(payload['objectTypeId']),
          attributeId: _toInt(payload['attributeId']),
          value: (payload['value'] ?? '').toString(),
        );
        return '';
      default:
        throw JiraApiException('Неизвестный тип записи очереди: $type');
    }
  }

  void _requireJsm(AppSetting settings, {required bool move}) {
    if (settings.serviceDeskId.trim().isEmpty) {
      throw const JiraApiException(
        'Не настроен Service Desk ID (Настройки → Jira Service Management).',
      );
    }
    final typeId = move
        ? settings.requestTypeMoveId
        : settings.requestTypeChangeId;
    if (typeId.trim().isEmpty) {
      throw JiraApiException(
        move
            ? 'Не настроен тип заявки «Перемещение».'
            : 'Не настроен тип заявки «Изменение данных».',
      );
    }
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
