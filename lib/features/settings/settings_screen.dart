import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../data/db/app_database.dart';
import '../../data/jira/jira_client.dart';

/// Модуль 2: настройки приложения.
/// Все настройки сохраняются в локальной БД ТСД и не сбрасываются
/// при перезапуске приложения.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _jiraUrl = TextEditingController();
  final _serviceLogin = TextEditingController();
  final _apiToken = TextEditingController();
  final _schemaId = TextEditingController();
  final _serviceDeskId = TextEditingController();
  final _requestTypeMove = TextEditingController();
  final _requestTypeChange = TextEditingController();
  final _printerIp = TextEditingController();
  final _printerPort = TextEditingController();
  String _codepage = 'UTF-8';
  bool _loaded = false;
  bool _saving = false;
  bool _checkingJira = false;
  bool _checkingPrinter = false;
  String? _jiraResult;
  String? _printerResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ref.read(settingsProvider.future);
    if (s == null) {
      setState(() => _loaded = true);
      return;
    }
    _jiraUrl.text = s.jiraBaseUrl;
    _serviceLogin.text = s.jiraServiceLogin;
    _apiToken.text = s.jiraApiToken;
    _schemaId.text = s.objectSchemaId;
    _serviceDeskId.text = s.serviceDeskId;
    _requestTypeMove.text = s.requestTypeMoveId;
    _requestTypeChange.text = s.requestTypeChangeId;
    _printerIp.text = s.printerIp;
    _printerPort.text = s.printerPort.toString();
    _codepage = s.printerCodepage;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _jiraUrl.dispose();
    _serviceLogin.dispose();
    _apiToken.dispose();
    _schemaId.dispose();
    _serviceDeskId.dispose();
    _requestTypeMove.dispose();
    _requestTypeChange.dispose();
    _printerIp.dispose();
    _printerPort.dispose();
    super.dispose();
  }

  AppSettingsCompanion _companion() {
    return AppSettingsCompanion(
      jiraBaseUrl: Value(_jiraUrl.text.trim()),
      jiraServiceLogin: Value(_serviceLogin.text.trim()),
      jiraApiToken: Value(_apiToken.text.trim()),
      objectSchemaId: Value(_schemaId.text.trim()),
      serviceDeskId: Value(_serviceDeskId.text.trim()),
      requestTypeMoveId: Value(_requestTypeMove.text.trim()),
      requestTypeChangeId: Value(_requestTypeChange.text.trim()),
      printerIp: Value(_printerIp.text.trim()),
      printerPort: Value(int.tryParse(_printerPort.text.trim()) ?? 9100),
      printerCodepage: Value(_codepage),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(settingsRepositoryProvider).save(_companion());
      ref.invalidate(settingsProvider);
      ref.invalidate(jiraClientProvider);
      if (!mounted) return;
      await ref.read(feedbackProvider).play(ScanFeedback.success);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сохранены.')),
      );
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

  Future<void> _checkJira() async {
    setState(() {
      _checkingJira = true;
      _jiraResult = null;
    });
    try {
      final client = JiraClient(
        baseUrl: _jiraUrl.text.trim(),
        login: _serviceLogin.text.trim(),
        token: _apiToken.text.trim(),
      );
      await client.testSchemaConnection(_schemaId.text.trim());
      await ref.read(feedbackProvider).play(ScanFeedback.success);
      setState(() => _jiraResult = 'Связь с Jira установлена, схема доступна.');
    } catch (e) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      setState(() => _jiraResult = e.toString());
    } finally {
      if (mounted) setState(() => _checkingJira = false);
    }
  }

  Future<void> _testPrint() async {
    setState(() {
      _checkingPrinter = true;
      _printerResult = null;
    });
    try {
      final ok = await ref.read(printerProvider).testPrint(
            ip: _printerIp.text.trim(),
            port: int.tryParse(_printerPort.text.trim()) ?? 9100,
            codepage: _codepage,
          );
      ref.read(printerStatusProvider.notifier).state = ok;
      await ref.read(feedbackProvider).play(
            ok ? ScanFeedback.success : ScanFeedback.error,
          );
      setState(
        () => _printerResult = ok
            ? 'Тестовая этикетка отправлена на принтер.'
            : 'Принтер не отвечает. Проверьте IP, порт и Wi-Fi.',
      );
    } finally {
      if (mounted) setState(() => _checkingPrinter = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Настройки')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionTitle('Jira API'),
            TextField(
              controller: _jiraUrl,
              decoration: const InputDecoration(
                labelText: 'Домен сервера Jira (URL)',
                hintText: 'https://jira.example.com',
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _serviceLogin,
              decoration: const InputDecoration(
                labelText: 'Логин сервисного аккаунта',
                prefixIcon: Icon(Icons.account_circle),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiToken,
              decoration: const InputDecoration(
                labelText: 'API-токен / ключ доступа',
                prefixIcon: Icon(Icons.key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _schemaId,
              decoration: const InputDecoration(
                labelText: 'ID схемы объектов Assets (Object Schema ID)',
                prefixIcon: Icon(Icons.schema),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _checkingJira
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find),
              label: const Text('Проверить связь с Jira'),
              onPressed: _checkingJira ? null : _checkJira,
            ),
            if (_jiraResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_jiraResult!),
              ),
            const SizedBox(height: 20),
            const _SectionTitle('Jira Service Management (заявки)'),
            TextField(
              controller: _serviceDeskId,
              decoration: const InputDecoration(
                labelText: 'Service Desk ID',
                prefixIcon: Icon(Icons.support_agent),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _requestTypeMove,
              decoration: const InputDecoration(
                labelText: 'Тип заявки «Перемещение» (Request Type ID)',
                prefixIcon: Icon(Icons.swap_horiz),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _requestTypeChange,
              decoration: const InputDecoration(
                labelText: 'Тип заявки «Изменение данных» (Request Type ID)',
                prefixIcon: Icon(Icons.edit_note),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Принтер этикеток TSC TE210'),
            TextField(
              controller: _printerIp,
              decoration: const InputDecoration(
                labelText: 'IP-адрес принтера (Wi-Fi)',
                hintText: '192.168.1.50',
                prefixIcon: Icon(Icons.print),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _printerPort,
              decoration: const InputDecoration(
                labelText: 'Порт (по умолчанию 9100)',
                prefixIcon: Icon(Icons.settings_ethernet),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _codepage,
              decoration: const InputDecoration(
                labelText: 'Кодировка кириллицы на принтере',
              ),
              items: const [
                DropdownMenuItem(value: 'UTF-8', child: Text('UTF-8')),
                DropdownMenuItem(
                  value: 'Windows-1251',
                  child: Text('Windows-1251 (старые прошивки TSC)'),
                ),
              ],
              onChanged: (v) => setState(() => _codepage = v ?? 'UTF-8'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: _checkingPrinter
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: const Text('Тестовая печать'),
              onPressed: _checkingPrinter ? null : _testPrint,
            ),
            if (_printerResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_printerResult!),
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('Сохранить настройки'),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
