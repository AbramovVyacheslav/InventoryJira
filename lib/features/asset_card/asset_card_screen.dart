import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../core/printer/tspl_printer.dart';
import '../../data/db/app_database.dart';
import '../../widgets/employee_picker.dart';

/// Модуль 5: карточка актива (экспресс-проверка, состояние, фото).
///
/// - Все атрибуты из Jira (динамически).
/// - Смена состояния из выпадающего списка.
/// - Фотофиксация необязательна и не блокирует сохранение.
/// - При сохранении создаётся заявка JSM «Было -> Стало» (через очередь).
class AssetCardScreen extends ConsumerStatefulWidget {
  final int assetId;

  const AssetCardScreen({super.key, required this.assetId});

  @override
  ConsumerState<AssetCardScreen> createState() => _AssetCardScreenState();
}

class _AssetCardScreenState extends ConsumerState<AssetCardScreen> {
  static const List<String> _statuses = [
    'Работает',
    'Требует ремонта',
    'Повреждено',
    'Новое',
  ];

  String? _status;
  Employee? _mol;
  String? _photoPath;
  bool _saving = false;
  bool _printing = false;

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
    );
    if (file != null) {
      setState(() => _photoPath = file.path);
    }
  }

  Future<void> _save(Asset asset) async {
    final changes = <String, (String, String)>{};
    if (_status != null && _status != asset.status) {
      changes['Состояние'] = (asset.status, _status!);
    }
    if (_mol != null && _mol!.id != asset.molId) {
      changes['МОЛ'] = (asset.molName, _mol!.name);
    }
    if (changes.isEmpty && _photoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет изменений для сохранения.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final settings = await ref.read(settingsProvider.future);
      await ref.read(assetRepositoryProvider).saveAssetChanges(
            asset: asset,
            changes: changes,
            operator: settings?.currentUserLogin ?? '',
            photoPath: _photoPath ?? '',
            newStatus: _status,
            newMol: _mol,
          );
      await ref.read(feedbackProvider).play(ScanFeedback.success);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Сохранено. Заявка на изменение поставлена в очередь отправки в Jira.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printLabel(Asset asset) async {
    final settings = await ref.read(settingsProvider.future);
    if (settings == null || settings.printerIp.trim().isEmpty) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Принтер не настроен.')),
        );
      }
      return;
    }
    setState(() => _printing = true);
    final ok = await ref.read(printerProvider).printLabels(
          ip: settings.printerIp,
          port: settings.printerPort,
          labels: [
            LabelData(
              qrContent: asset.objectKey.isNotEmpty
                  ? asset.objectKey
                  : '${asset.id}',
              name: asset.name,
              objectKey: asset.objectKey,
              code1c: asset.code1c,
              organization: asset.organization,
            ),
          ],
          codepage: settings.printerCodepage,
        );
    ref.read(printerStatusProvider.notifier).state = ok;
    await ref.read(feedbackProvider).play(
          ok ? ScanFeedback.success : ScanFeedback.error,
        );
    if (mounted) {
      setState(() => _printing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Этикетка отправлена на печать.' : 'Принтер не отвечает.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка актива')),
      body: FutureBuilder<Asset?>(
        future: ref.read(databaseProvider).assetDao.getById(widget.assetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final asset = snapshot.data;
          if (asset == null) {
            return const Center(child: Text('Актив не найден.'));
          }
          _status ??= asset.status;
          _mol ??= asset.molId != null
              ? Employee(id: asset.molId!, name: asset.molName)
              : null;

          final attrs = _decodeAttributes(asset.attributesJson);
          final statusItems = _statuses.contains(_status)
              ? _statuses
              : [_status ?? '', ..._statuses];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  asset.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Ключ Jira: ${asset.objectKey} · ID: ${asset.id}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                _InfoRow('Серийный номер', asset.serialNumber),
                _InfoRow('Код 1С', asset.code1c),
                _InfoRow('Организация', asset.organization),
                _InfoRow('Помещение', asset.roomName),
                _InfoRow(
                  'Дата последней инвентаризации',
                  asset.lastInventoryDate != null
                      ? DateFormat('dd.MM.yyyy').format(asset.lastInventoryDate!)
                      : 'не проводилась',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _statuses.contains(_status) ? _status : null,
                  decoration: const InputDecoration(
                    labelText: 'Текущее состояние',
                  ),
                  items: statusItems
                      .where((s) => s.isNotEmpty)
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _status = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person),
                  label: Text(
                    _mol != null ? 'МОЛ: ${_mol!.name}' : 'Выбрать МОЛ',
                  ),
                  onPressed: () async {
                    final employee = await EmployeePicker.show(context);
                    if (employee != null) {
                      setState(() => _mol = employee);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Все атрибуты из Jira:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (attrs.isEmpty)
                  const Text('Атрибуты отсутствуют.'),
                ...attrs.map(
                  (a) => _InfoRow(a.name, a.value),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Добавить фото (необязательно)'),
                  onPressed: _pickPhoto,
                ),
                if (_photoPath != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_photoPath!),
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _photoPath = null),
                    child: const Text('Удалить фото'),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _printing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print),
                        label: const Text('Печать этикетки'),
                        onPressed: _printing ? null : () => _printLabel(asset),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Сохранить'),
                        onPressed: _saving ? null : () => _save(asset),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<({String name, String value})> _decodeAttributes(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return [];
      final result = <({String name, String value})>[];
      for (final entry in decoded.entries) {
        final v = entry.value;
        if (v is Map<String, dynamic>) {
          result.add((
            name: (v['name'] ?? '').toString(),
            value: (v['value'] ?? '').toString(),
          ));
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value.isNotEmpty ? value : '—')),
        ],
      ),
    );
  }
}
