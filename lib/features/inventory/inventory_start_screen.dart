import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../data/db/app_database.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/scanner/camera_scan_screen.dart';

/// Вход в процесс инвентаризации: сканируется QR-код на входе
/// в кабинет (лазер ТСД или камера). Также доступен ручной выбор
/// помещения из списка.
class InventoryStartScreen extends ConsumerStatefulWidget {
  const InventoryStartScreen({super.key});

  @override
  ConsumerState<InventoryStartScreen> createState() =>
      _InventoryStartScreenState();
}

class _InventoryStartScreenState
    extends ConsumerState<InventoryStartScreen> {
  StreamSubscription<String>? _scanSub;

  @override
  void initState() {
    super.initState();
    final scanner = ref.read(scannerProvider);
    scanner.startListening();
    _scanSub = scanner.scanStream.listen(_onScanned);
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _onScanned(String code) async {
    final room = await ref.read(databaseProvider).roomDao.getByBarcode(code);
    if (!mounted) return;
    if (room == null) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помещение по коду «$code» не найдено.')),
      );
      return;
    }
    await ref.read(feedbackProvider).play(ScanFeedback.success);
    if (!mounted) return;
    await _enterRoom(room);
  }

  Future<void> _enterRoom(Room room) async {
    final db = ref.read(databaseProvider);
    final settings = await ref.read(settingsProvider.future);
    final operator = settings?.currentUserLogin ?? '';
    // Продолжить активную сессию (можно прерывать на дни) или создать новую.
    final session = await db.sessionDao.getActiveSession(room.id);
    if (session != null) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InventoryScreen(room: room, sessionId: session.id),
        ),
      );
      return;
    }
    // Новая сессия инвентаризации: очищаем результаты прошлой проверки
    // (данные активов сохраняются, пока не обновлён снимок из Jira).
    await db.assetDao.resetVerification();
    final expected = (await db.assetDao.watchByRoom(room.id).first).length;
    final sessionId = await db.sessionDao.createSession(
      roomId: room.id,
      roomName: room.name,
      operatorLogin: operator,
      totalExpected: expected,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InventoryScreen(room: room, sessionId: sessionId),
      ),
    );
  }

  Future<void> _scanByCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (code != null && code.isNotEmpty) {
      await _onScanned(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(roomsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Инвентаризация помещения')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Сканируйте QR-код на входе в кабинет '
                  'лазером ТСД или камерой.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Сканировать камерой'),
                  onPressed: _scanByCamera,
                ),
              ],
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Или выберите помещение вручную:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: rooms.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Помещения не найдены. Сначала обновите данные '
                        'из Jira на главном экране.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final room = list[i];
                    return ListTile(
                      leading: const Icon(Icons.meeting_room),
                      title: Text(room.name),
                      subtitle: room.barcode.isNotEmpty
                          ? Text('QR: ${room.barcode}')
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _enterRoom(room),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Ошибка: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
