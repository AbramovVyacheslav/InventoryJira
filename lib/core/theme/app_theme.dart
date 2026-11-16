import 'package:flutter/material.dart';

/// Промышленная тема: высококонтрастная, крупные элементы управления,
/// читаемость на солнце и в перчатках. Цвета кодировки статусов
/// соответствуют ТЗ: зелёный — проверено, серый — осталось найти,
/// оранжевый — чужая техника (перемещение), красный — ошибка/дубликат.
class AppTheme {
  static const Color seed = Color(0xFF0D477A);
  static const Color verified = Color(0xFF1B8C5A);
  static const Color pending = Color(0xFF757575);
  static const Color foreign = Color(0xFFE65100);
  static const Color error = Color(0xFFC62828);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      // Кнопки «под палец»: минимальная высота 52 dp.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(fontSize: 16),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        textStyle: TextStyle(fontSize: 16),
      ),
    );
  }
}

/// Цветовая кодировка позиций списка инвентаризации.
class InventoryColors {
  static Color forAsset({required bool isVerified, required bool isForeign}) {
    if (isForeign) return AppTheme.foreign;
    if (isVerified) return AppTheme.verified;
    return AppTheme.pending;
  }
}
