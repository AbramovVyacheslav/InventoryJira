import '../../data/db/app_database.dart';

/// Чистая логика поиска и фильтрации списка инвентаризации
/// (покрыта юнит-тестами, не зависит от Flutter).
class InventorySearch {
  /// Сквозной поиск: название, ключ Jira, серийный номер, код 1С, ID.
  /// Используется, когда штрихкод затёрт и код вводится вручную.
  static List<Asset> filterByQuery(List<Asset> assets, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return assets;
    return assets.where((a) {
      return a.name.toLowerCase().contains(q) ||
          a.objectKey.toLowerCase().contains(q) ||
          a.serialNumber.toLowerCase().contains(q) ||
          a.code1c.toLowerCase().contains(q) ||
          a.id.toString() == q;
    }).toList();
  }

  /// Фильтр «Только расхождения»: скрывает проверенную технику,
  /// остаются только недостающие позиции.
  static List<Asset> discrepanciesOnly(List<Asset> assets) =>
      assets.where((a) => !a.isVerified).toList();

  static int verifiedCount(List<Asset> assets) =>
      assets.where((a) => a.isVerified).length;

  static int foreignCount(List<Asset> assets) =>
      assets.where((a) => a.isForeign).length;
}
