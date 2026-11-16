import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_providers.dart';
import 'core/logger/app_logger.dart';
import 'data/db/app_database.dart';

/// Точка входа: открытие локальной БД (Drift/SQLite) и запуск приложения.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await AppDatabase.openInDocuments();
  final logger = AppLogger();
  await logger.init();
  logger.info('Database opened');

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        loggerProvider.overrideWithValue(logger),
      ],
      child: const InventoryApp(),
    ),
  );
}
