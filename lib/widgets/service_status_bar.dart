import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';

/// Верхняя сервисная панель (ТЗ, раздел 4):
/// заряд батареи ТСД, количество неотправленных пакетов Wi-Fi,
/// статус подключения к сетевому принтеру (зелёный/красный индикатор).
class ServiceStatusBar extends ConsumerWidget {
  const ServiceStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(batteryLevelProvider);
    final pending = ref.watch(pendingCountProvider);
    final printerOk = ref.watch(printerStatusProvider);
    final online = ref.watch(onlineProvider);

    return Container(
      color: const Color(0xFF263238),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Батарея
          Icon(
            _batteryIcon(battery.valueOrNull),
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 4),
          Text(
            battery.valueOrNull != null ? '${battery.valueOrNull}%' : '--%',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(width: 16),
          // Сеть
          Icon(
            online.valueOrNull == true ? Icons.wifi : Icons.wifi_off,
            color: online.valueOrNull == true ? Colors.lightGreen : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 4),
          // Очередь синхронизации
          Badge(
            label: Text('${pending.valueOrNull ?? 0}'),
            backgroundColor: (pending.valueOrNull ?? 0) > 0
                ? Colors.orange
                : Colors.grey,
            child: const Icon(Icons.cloud_upload, color: Colors.white, size: 20),
          ),
          const Spacer(),
          // Принтер
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: printerOk ? Colors.lightGreen : Colors.redAccent,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.print, color: Colors.white, size: 20),
        ],
      ),
    );
  }

  IconData _batteryIcon(int? level) {
    if (level == null) return Icons.battery_unknown;
    if (level >= 90) return Icons.battery_full;
    if (level >= 60) return Icons.battery_6_bar;
    if (level >= 30) return Icons.battery_3_bar;
    return Icons.battery_alert;
  }
}
