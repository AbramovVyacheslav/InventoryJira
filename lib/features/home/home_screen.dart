import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../features/auth/login_screen.dart';
import '../../features/express/express_check_screen.dart';
import '../../features/inventory/inventory_start_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/sync/sync_monitor_screen.dart';
import '../../widgets/service_status_bar.dart';

/// Главное меню: инвентаризация, экспресс-проверка,
/// монитор синхронизации, настройки.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _refreshing = false;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    // Проверка принтера при входе на главный экран.
    Future.microtask(_checkPrinter);
  }

  Future<void> _checkPrinter() async {
    final settings = await ref.read(settingsProvider.future);
    if (settings == null || settings.printerIp.trim().isEmpty) {
      ref.read(printerStatusProvider.notifier).state = false;
      return;
    }
    final ok = await ref.read(printerProvider).checkConnection(
          ip: settings.printerIp,
          port: settings.printerPort,
        );
    if (mounted) {
      ref.read(printerStatusProvider.notifier).state = ok;
    }
  }

  /// Скачивание актуального среза из Jira (модуль 1).
  Future<void> _refreshSnapshot() async {
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final client = await ref.read(jiraClientProvider.future);
      if (client == null || settings == null) {
        throw Exception(
          'Jira не настроена. Заполните настройки (URL, сервисный аккаунт, '
          'токен, ID схемы).',
        );
      }
      if (settings.objectSchemaId.trim().isEmpty) {
        throw Exception('Не указан ID схемы объектов Assets.');
      }
      final result = await ref.read(assetRepositoryProvider).downloadSnapshot(
            client: client,
            schemaId: settings.objectSchemaId,
          );
      ref.invalidate(settingsProvider);
      if (!mounted) return;
      await ref.read(feedbackProvider).play(ScanFeedback.success);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Снимок обновлён: активов ${result.assets}, '
            'помещений ${result.rooms}, сотрудников ${result.employees}.',
          ),
        ),
      );
    } catch (e) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      if (mounted) setState(() => _refreshError = e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(databaseProvider).settingsDao.logout();
    ref.invalidate(settingsProvider);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final pending = ref.watch(pendingCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Главное меню'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          const ServiceStatusBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  settings.when(
                    data: (s) => Text(
                      'Пользователь: ${s?.currentUserName ?? ''} '
                      '(${s?.currentUserLogin ?? ''})',
                      style: const TextStyle(fontSize: 16),
                    ),
                    loading: () => const Text('Загрузка...'),
                    error: (e, _) => Text('Ошибка: $e'),
                  ),
                  if (settings.valueOrNull?.lastSnapshotAt != null)
                    Text(
                      'Снимок Jira: ${DateFormat('dd.MM.yyyy HH:mm').format(
                        settings.valueOrNull!.lastSnapshotAt!,
                      )}',
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: _refreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_download),
                    label: const Text('Обновить данные из Jira'),
                    onPressed: _refreshing ? null : _refreshSnapshot,
                  ),
                  if (_refreshError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _refreshError!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _MenuButton(
                    icon: Icons.inventory,
                    title: 'Инвентаризация помещения',
                    subtitle: 'Сканируйте QR на входе в кабинет',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const InventoryStartScreen(),
                        ),
                      );
                    },
                  ),
                  _MenuButton(
                    icon: Icons.qr_code_scanner,
                    title: 'Экспресс-проверка',
                    subtitle: 'Карточка актива вне инвентаризации',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ExpressCheckScreen(),
                        ),
                      );
                    },
                  ),
                  _MenuButton(
                    icon: Icons.sync,
                    title: 'Монитор синхронизации',
                    subtitle: pending.valueOrNull != null
                        ? 'В очереди: ${pending.valueOrNull}'
                        : 'Очередь отправки в Jira',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SyncMonitorScreen(),
                        ),
                      );
                    },
                  ),
                  _MenuButton(
                    icon: Icons.settings,
                    title: 'Настройки',
                    subtitle: 'Jira API и принтер этикеток',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 36),
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
