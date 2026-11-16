import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

/// Корневой виджет: тема, навигация, фоновая синхронизация.
///
/// Автосинхронизация: при восстановлении сети очередь отправляется
/// автоматически (модуль 4), плюс периодическая попытка раз в 60 секунд.
class InventoryApp extends ConsumerStatefulWidget {
  const InventoryApp({super.key});

  @override
  ConsumerState<InventoryApp> createState() => _InventoryAppState();
}

class _InventoryAppState extends ConsumerState<InventoryApp> {
  StreamSubscription<bool>? _onlineSub;
  Timer? _periodicTimer;

  @override
  void initState() {
    super.initState();
    final logger = ref.read(loggerProvider);
    logger.info('App started');

    // Автоматическая отправка при восстановлении Wi-Fi.
    _onlineSub = ref.read(networkMonitorProvider).onlineStream.listen(
      (online) {
        if (online) {
          ref.read(syncEngineProvider).processQueue();
        }
      },
    );

    // Периодическая попытка (на случай пропущенного события сети).
    _periodicTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ref.read(syncEngineProvider).processQueue(),
    );

    // Первая попытка при старте.
    Future.microtask(() => ref.read(syncEngineProvider).processQueue());
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Инвентаризация Jira',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

/// Выбор стартового экрана по наличию активной сессии пользователя.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return settings.when(
      data: (s) {
        if (s != null && s.currentUserLogin.isNotEmpty) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const LoginScreen(),
    );
  }
}
