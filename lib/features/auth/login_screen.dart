import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../core/feedback/feedback_service.dart';
import '../../data/jira/jira_client.dart';
import '../../features/home/home_screen.dart';
import '../../features/settings/settings_screen.dart';

/// Модуль 1: авторизация по корпоративным учётным записям Jira
/// (синхронизированы с Active Directory на стороне сервера Jira).
///
/// Учётные данные пользователя проверяются через GET /rest/api/2/myself
/// и не сохраняются на устройстве. Дальнейшие вызовы API идут
/// через сервисный аккаунт из настроек.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final login = _loginController.text.trim();
    final password = _passwordController.text;
    if (login.isEmpty || password.isEmpty) {
      setState(() => _error = 'Введите логин и пароль.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final baseUrl = settings?.jiraBaseUrl.trim() ?? '';
      if (baseUrl.isEmpty) {
        throw const JiraApiException(
          'Не настроен URL сервера Jira. Откройте «Настройки» и заполните '
          'параметры подключения.',
        );
      }
      final client = JiraClient(
        baseUrl: baseUrl,
        login: login,
        token: password,
      );
      final user = await client.getMyself();
      await ref
          .read(databaseProvider)
          .settingsDao
          .setCurrentUser(user.name, user.displayName);
      ref.invalidate(settingsProvider);
      if (!mounted) return;
      await ref.read(feedbackProvider).play(ScanFeedback.success);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      await ref.read(feedbackProvider).play(ScanFeedback.error);
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Инвентаризация Jira')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.inventory_2, size: 72, color: Colors.blueGrey),
            const SizedBox(height: 12),
            const Text(
              'Вход в систему',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Используйте корпоративный логин и пароль Jira',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Логин Jira',
                prefixIcon: Icon(Icons.person),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              onSubmitted: (_) => _login(),
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
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.login),
              label: const Text('Войти'),
              onPressed: _busy ? null : _login,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Настройки подключения'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
