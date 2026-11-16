import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';

/// Модуль 4: монитор синхронизации.
/// Показывает количество успешно переданных записей и объектов,
/// ожидающих отправки в очереди. Кнопка ручной принудительной выгрузки.
class SyncMonitorScreen extends ConsumerStatefulWidget {
  const SyncMonitorScreen({super.key});

  @override
  ConsumerState<SyncMonitorScreen> createState() => _SyncMonitorScreenState();
}

class _SyncMonitorScreenState extends ConsumerState<SyncMonitorScreen> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final result = await ref.read(syncEngineProvider).processQueue();
      await ref.read(feedbackProvider).play(
            result.failed > 0 ? ScanFeedback.error : ScanFeedback.success,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.skipped
                ? 'Синхронизация пропущена (уже выполняется или Jira не настроена).'
                : 'Отправлено: ${result.sent}, ошибок: ${result.failed}.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(syncQueueStreamProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Монитор синхронизации')),
      body: items.when(
        data: (list) {
          final pending =
              list.where((i) => i.status == 'pending').length;
          final sending =
              list.where((i) => i.status == 'sending').length;
          final failed = list.where((i) => i.status == 'failed').length;
          final sent = list.where((i) => i.status == 'sent').length;

          return RefreshIndicator(
            onRefresh: _syncNow,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        title: 'Отправлено',
                        value: '$sent',
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        title: 'Ожидает',
                        value: '${pending + sending}',
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        title: 'Ошибок',
                        value: '$failed',
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (settings.valueOrNull?.lastSyncAt != null)
                  Text(
                    'Последняя отправка: ${DateFormat('dd.MM.yyyy HH:mm').format(
                      settings.valueOrNull!.lastSyncAt!,
                    )}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: _syncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.cloud_upload),
                  label: const Text('Отправить сейчас'),
                  onPressed: _syncing ? null : _syncNow,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Очередь:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Очередь пуста.'),
                  ),
                ...list.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(_iconFor(item.status)),
                      title: Text(_typeLabel(item.type)),
                      subtitle: Text(
                        'Актив #${item.assetId} · '
                        '${DateFormat('dd.MM.yyyy HH:mm').format(item.createdAt)}'
                        '${item.jiraIssueKey.isNotEmpty ? ' · ${item.jiraIssueKey}' : ''}'
                        '${item.lastError.isNotEmpty ? '\n${item.lastError}' : ''}',
                      ),
                      trailing: Chip(
                        label: Text(_statusLabel(item.status)),
                        backgroundColor: _colorFor(item.status),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
      ),
    );
  }

  IconData _iconFor(String status) {
    switch (status) {
      case 'sent':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'sending':
        return Icons.hourglass_top;
      default:
        return Icons.pending;
    }
  }

  Color _colorFor(String status) {
    switch (status) {
      case 'sent':
        return Colors.green.shade100;
      case 'failed':
        return Colors.red.shade100;
      default:
        return Colors.orange.shade100;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'move':
        return 'Заявка на перемещение';
      case 'inventoryDate':
        return 'Дата инвентаризации';
      case 'assetChange':
        return 'Изменение данных';
      default:
        return type;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'sent':
        return 'Отправлено';
      case 'failed':
        return 'Ошибка';
      case 'sending':
        return 'Отправка';
      default:
        return 'Ожидает';
    }
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(title, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
