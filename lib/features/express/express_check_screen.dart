import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../features/asset_card/asset_card_screen.dart';
import '../../features/scanner/camera_scan_screen.dart';

/// Модуль 5, вход: экспресс-проверка актива вне инвентаризации.
/// Постоянно активное поле поиска (лазер/ввод кода), камера как запасной
/// вариант. По найденному активу открывается карточка.
class ExpressCheckScreen extends ConsumerStatefulWidget {
  const ExpressCheckScreen({super.key});

  @override
  ConsumerState<ExpressCheckScreen> createState() =>
      _ExpressCheckScreenState();
}

class _ExpressCheckScreenState extends ConsumerState<ExpressCheckScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  StreamSubscription<String>? _scanSub;
  String? _error;

  @override
  void initState() {
    super.initState();
    final scanner = ref.read(scannerProvider);
    scanner.startListening();
    _scanSub = scanner.scanStream.listen(_onCode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    final asset = await ref.read(assetRepositoryProvider).findByCode(trimmed);
    if (!mounted) return;
    if (asset == null) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      setState(() => _error = 'Актив по коду «$trimmed» не найден в снимке Jira.');
      return;
    }
    await ref.read(feedbackProvider).play(ScanFeedback.success);
    if (!mounted) return;
    setState(() => _error = null);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssetCardScreen(assetId: asset.id),
      ),
    );
    _searchController.clear();
    _focusNode.requestFocus();
  }

  Future<void> _scanByCamera() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CameraScanScreen()),
    );
    if (code != null && code.isNotEmpty) {
      await _onCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Экспресс-проверка')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Сканируйте актив лазером ТСД или введите код '
              '(ключ Jira, серийный номер, код 1С).',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              focusNode: _focusNode,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Код актива',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: _onCode,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Сканировать камерой'),
              onPressed: _scanByCamera,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900, fontSize: 15),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
