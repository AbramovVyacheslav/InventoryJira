import 'models.dart';

/// Маппинг динамических атрибутов Jira Assets на внутренние поля.
///
/// Приложение автоматически запрашивает структуру полей из Jira.
/// Известные реквизиты (серийный номер, код 1С, МОЛ, помещение...)
/// распознаются по русским/английским названиям атрибутов,
/// остальные показываются в карточке как есть — без изменения кода
/// при добавлении новых характеристик в Jira.
///
/// Если в вашей схеме атрибуты называются иначе, поправьте списки
/// кандидатов ниже под свою схему (см. README, «Настройка Jira»).
class AttributeMapper {
  static const List<String> serialCandidates = [
    'серийный номер',
    'serial',
    'заводской номер',
  ];
  static const List<String> code1cCandidates = [
    'код 1с',
    'код1с',
    'код 1c',
    'code1c',
    '1сбу',
  ];
  static const List<String> organizationCandidates = [
    'организация',
    'organization',
  ];
  static const List<String> roomCandidates = [
    'помещение',
    'кабинет',
    'room',
    'location',
  ];
  static const List<String> molCandidates = [
    'пользователь (мол)',
    'пользователь',
    'мол',
    'материально ответственное',
    'user',
  ];
  static const List<String> statusCandidates = [
    'состояние',
    'статус',
    'status',
  ];
  static const List<String> lastInventoryCandidates = [
    'дата последней инвентаризации',
    'последняя инвентаризация',
    'last inventory',
  ];

  static String serialNumber(AssetObject obj) =>
      obj.attributeValue(serialCandidates) ?? '';

  static String code1c(AssetObject obj) =>
      obj.attributeValue(code1cCandidates) ?? '';

  static String organization(AssetObject obj) =>
      obj.attributeValue(organizationCandidates) ?? '';

  static String status(AssetObject obj) =>
      obj.attributeValue(statusCandidates) ?? '';

  /// Ссылка на помещение: возвращает связанный объект, если есть.
  static AssetAttribute? roomAttribute(AssetObject obj) =>
      obj.attributeByName(roomCandidates);

  /// Ссылка на МОЛ: возвращает связанный объект, если есть.
  static AssetAttribute? molAttribute(AssetObject obj) =>
      obj.attributeByName(molCandidates);

  static int? referencedId(AssetAttribute? attr) {
    if (attr == null) return null;
    final raw = attr.referencedObjectId;
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  static String referencedName(AssetAttribute? attr) {
    if (attr == null) return '';
    return attr.referencedObjectName ??
        attr.referencedObjectKey ??
        attr.value;
  }
}
