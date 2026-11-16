import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import '../data/db/app_database.dart';

/// Выбор сотрудника (МОЛ) из локального списка Jira.
/// Возвращает выбранного [Employee] или null при отмене.
class EmployeePicker extends ConsumerStatefulWidget {
  const EmployeePicker({super.key});

  static Future<Employee?> show(BuildContext context) {
    return showDialog<Employee>(
      context: context,
      builder: (_) => const EmployeePicker(),
    );
  }

  @override
  ConsumerState<EmployeePicker> createState() => _EmployeePickerState();
}

class _EmployeePickerState extends ConsumerState<EmployeePicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesStreamProvider);

    return AlertDialog(
      title: const Text('Выберите сотрудника (МОЛ)'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Поиск по имени',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: employees.when(
                data: (list) {
                  final q = _query.trim().toLowerCase();
                  final filtered = q.isEmpty
                      ? list
                      : list
                          .where((e) => e.name.toLowerCase().contains(q))
                          .toList();
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Сотрудники не найдены. '
                          'Обновите снимок данных из Jira.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      return ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(e.name),
                        subtitle: Text(
                          [e.department, e.email]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                        ),
                        onTap: () => Navigator.of(context).pop(e),
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Ошибка: $e'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}

/// Крупное модальное окно «Заполнение МОЛ» (ТЗ, модуль 3 п.5):
/// блокирует интерфейс и требует выбрать сотрудника перед сохранением.
/// Закрыть без выбора нельзя (barrierDismissible = false).
class MolRequiredDialog extends StatelessWidget {
  final String assetName;

  const MolRequiredDialog({super.key, required this.assetName});

  static Future<Employee?> show(BuildContext context, String assetName) {
    return showDialog<Employee>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MolRequiredDialog(assetName: assetName),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber, color: Colors.orange, size: 32),
          SizedBox(width: 8),
          Expanded(child: Text('Не заполнен МОЛ')),
        ],
      ),
      content: Text(
        'У актива «$assetName» не указан пользователь (МОЛ).\n\n'
        'Выберите сотрудника из списка Jira — без этого '
        'инвентаризацию нельзя сохранить.',
      ),
      actions: [
        ElevatedButton.icon(
          icon: const Icon(Icons.person_search),
          label: const Text('Выбрать сотрудника'),
          onPressed: () async {
            final employee = await EmployeePicker.show(context);
            if (employee != null && context.mounted) {
              Navigator.of(context).pop(employee);
            }
          },
        ),
      ],
    );
  }
}
