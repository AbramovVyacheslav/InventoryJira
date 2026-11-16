import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../core/printer/tspl_printer.dart';
import '../../data/db/app_database.dart';
import '../../features/asset_card/asset_card_screen.dart';
import '../../features/inventory/inventory_search.dart';
import '../../features/inventory/widgets/asset_tile.dart';
import '../../features/scanner/camera_scan_screen.dart';
import '../../widgets/employee_picker.dart';
import '../../widgets/service_status_bar.dart';

/// Модуль 3: основной процесс инвентаризации помещения.
///
/// - Всегда активная строка поиска (курсор автоматически, клавиатура
///   скрыта, чтобы не мешать лазерному сканированию; для ручного ввода
///   есть кнопка «Клавиатура»).
/// - Фильтр «Только расхождения».
/// - «Своё» оборудование → проверено + дата инвентаризации.
/// - «Чужое» → перемещение + заявка JSM в очередь.
/// - Пакетная печать отмеченных позиций без прерывания сессии.
class InventoryScreen extends ConsumerStatefulWidget {
  final Room room;
  final int sessionId;

  const InventoryScreen({
    super.key,
    required this.room,
    required this.sessionId,
  });

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<String>? _scanSub;
  bool _onlyDiscrepancies = false;
  bool _showKeyboard = false;
  final Set<int> _selectedForPrint = {};
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    final scanner = ref.read(scannerProvider);
    scanner.startListening();
    _scanSub = scanner.scanStream.listen(_onScan);
    // Курсор в поле поиска автоматически, клавиатура скрыта.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _hideKeyboard();
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _hideKeyboard() {
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _toggleKeyboard() {
    setState(() => _showKeyboard = !_showKeyboard);
    if (_showKeyboard) {
      _focusNode.requestFocus();
    } else {
      _hideKeyboard();
    }
  }

  // -------------------------------------------------------------------------
  // Сканирование
  // -------------------------------------------------------------------------

  Future<void> _onScan(String code) async {
    final repo = ref.read(assetRepositoryProvider);
    final feedback = ref.read(feedbackProvider);
    final asset = await repo.findByCode(code);
    if (!mounted) return;

    if (asset == null) {
      await feedback.play(ScanFeedback.error);
      _snack('Не найдено в Jira: «$code»');
      return;
    }

    if (asset.isVerified && !asset.isForeign) {
      await feedback.play(ScanFeedback.error);
      _snack('Дубликат: «${asset.name}» уже проверено.');
      return;
    }

    final settings = await ref.read(settingsProvider.future);
    final operator = settings?.currentUserLogin ?? '';

    if (asset.roomId == widget.room.id) {
      // Своё оборудование.
      if (asset.molId == null || asset.molName.isEmpty) {
        final employee = await MolRequiredDialog.show(context, asset.name);
        if (employee == null || !mounted) return;
        await repo.updateMol(asset: asset, employee: employee);
      }
      await repo.markVerified(
        asset: asset,
        sessionId: widget.sessionId,
        operator: operator,
      );
      await feedback.play(ScanFeedback.success);
      _snack('Проверено: ${asset.name}');
    } else {
      // Чужое оборудование → перемещение.
      await repo.moveToRoom(
        asset: asset,
        room: widget.room,
        sessionId: widget.sessionId,
        operator: operator,
      );
      await feedback.play(ScanFeedback.move);
      _snack(
        'Перемещение: ${asset.name} '
        '(${asset.roomName.isNotEmpty ? asset.roomName : 'не указано'} → '
        '${widget.room.name})',
      );
    }
    await _updateSessionProgress();
  }

  Future<void> _updateSessionProgress() async {
    final list = await ref
        .read(databaseProvider)
        .assetDao
        .watchByRoom(widget.room.id)
        .first;
    await ref.read(databaseProvider).sessionDao.updateProgress(
          sessionId: widget.sessionId,
          found: InventorySearch.verifiedCount(list),
          foreign: InventorySearch.foreignCount(list),
        );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // -------------------------------------------------------------------------
  // Пакетная печать
  // -------------------------------------------------------------------------

  Future<void> _bulkPrint(List<Asset> assets) async {
    final selected =
        assets.where((a) => _selectedForPrint.contains(a.id)).toList();
    if (selected.isEmpty) {
      _snack('Отметьте позиции для печати галочками.');
      return;
    }
    final settings = await ref.read(settingsProvider.future);
    if (settings == null || settings.printerIp.trim().isEmpty) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      _snack('Принтер не настроен (Настройки → Принтер этикеток).');
      return;
    }
    setState(() => _printing = true);
    final labels = selected
        .map(
          (a) => LabelData(
            qrContent: a.objectKey.isNotEmpty ? a.objectKey : '${a.id}',
            name: a.name,
            objectKey: a.objectKey,
            code1c: a.code1c,
            organization: a.organization,
          ),
        )
        .toList();
    final ok = await ref.read(printerProvider).printLabels(
          ip: settings.printerIp,
          port: settings.printerPort,
          labels: labels,
          codepage: settings.printerCodepage,
        );
    ref.read(printerStatusProvider.notifier).state = ok;
    await ref.read(feedbackProvider).play(
          ok ? ScanFeedback.success : ScanFeedback.error,
        );
    if (!mounted) return;
    setState(() => _printing = false);
    _snack(
      ok
          ? 'Отправлено на печать: ${labels.length} этикеток.'
          : 'Принтер не отвечает. Проверьте Wi-Fi и IP.',
    );
    if (ok) {
      setState(_selectedForPrint.clear);
    }
  }

  // -------------------------------------------------------------------------
  // Защита от случайного выхода
  // -------------------------------------------------------------------------

  Future<bool> _confirmExit() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Завершить инвентаризацию?'),
        content: const Text(
          'Прогресс сохранён локально. Сессию можно продолжить позже '
          '(например, в понедельник) без потери данных.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Продолжить'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (result == true) {
      await ref
          .read(databaseProvider)
          .sessionDao
          .finishSession(widget.sessionId);
    }
    return result ?? false;
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(roomAssetsProvider(widget.room.id));

    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.room.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Сканировать камерой',
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const CameraScanScreen()),
                );
                if (code != null && code.isNotEmpty) {
                  await _onScan(code);
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            const ServiceStatusBar(),
            assetsAsync.when(
              data: (all) {
                final found = InventorySearch.verifiedCount(all);
                final foreign = InventorySearch.foreignCount(all);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Найдено: $found из ${all.length} · Чужих: $foreign',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: all.isEmpty ? 0 : found / all.length,
                        minHeight: 8,
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Поиск / скан: код 1С, серийник, название',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (value) {
                        final code = value.trim();
                        if (code.isNotEmpty) {
                          _onScan(code);
                          _searchController.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(
                      _showKeyboard ? Icons.keyboard_hide : Icons.keyboard,
                    ),
                    tooltip: 'Клавиатура (ручной ввод)',
                    onPressed: _toggleKeyboard,
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Только расхождения (не найденные)'),
              value: _onlyDiscrepancies,
              onChanged: (v) => setState(() => _onlyDiscrepancies = v),
            ),
            Expanded(
              child: assetsAsync.when(
                data: (all) {
                  var list = InventorySearch.filterByQuery(
                    all,
                    _searchController.text,
                  );
                  if (_onlyDiscrepancies) {
                    list = InventorySearch.discrepanciesOnly(list);
                  }
                  if (list.isEmpty) {
                    return const Center(
                      child: Text(
                        'Ничего не найдено.\n'
                        'Отключите фильтр «Только расхождения» '
                        'или измените запрос.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final asset = list[i];
                      return AssetTile(
                        asset: asset,
                        selectedForPrint:
                            _selectedForPrint.contains(asset.id),
                        onPrintSelected: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedForPrint.add(asset.id);
                            } else {
                              _selectedForPrint.remove(asset.id);
                            }
                          });
                        },
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AssetCardScreen(assetId: asset.id),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Ошибка: $e')),
              ),
            ),
          ],
        ),
        bottomNavigationBar: assetsAsync.maybeWhen(
          data: (all) => Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              icon: _printing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.print),
              label: Text(
                'Печать этикеток (${_selectedForPrint.length})',
              ),
              onPressed: _printing ? null : () => _bulkPrint(all),
            ),
          ),
          orElse: () => null,
        ),
      ),
    );
  }
}
