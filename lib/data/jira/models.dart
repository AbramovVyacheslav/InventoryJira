/// Модели Jira Assets / Jira Service Management.
///
/// Парсинг толерантный: разные версии Jira (Cloud / Data Center)
/// возвращают немного разные формы JSON, поэтому читаем
/// несколько возможных ключей.

/// Один атрибут объекта Assets.
class AssetAttribute {
  final int id;
  final String name;
  final String value;

  /// Для атрибутов-ссылок: ID/ключ/имя связанного объекта.
  final String? referencedObjectId;
  final String? referencedObjectKey;
  final String? referencedObjectName;

  const AssetAttribute({
    required this.id,
    required this.name,
    required this.value,
    this.referencedObjectId,
    this.referencedObjectKey,
    this.referencedObjectName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'referencedObjectId': referencedObjectId,
        'referencedObjectKey': referencedObjectKey,
        'referencedObjectName': referencedObjectName,
      };

  factory AssetAttribute.fromJson(Map<String, dynamic> json) {
    // Формы значений в разных версиях Assets:
    //  - {"value": "...", "displayValue": "..."}
    //  - {"objectAttributeValues": [{"value": ..., "displayValue": ...}]}
    //  - {"referencedObjectId": ..., "displayValue": ...}
    String value = '';
    String? refId;
    String? refKey;
    String? refName;

    final display = json['displayValue'];
    if (display is String && display.isNotEmpty) value = display;

    final rawValue = json['value'];
    if (rawValue is String && value.isEmpty) value = rawValue;
    if (rawValue is num) value = rawValue.toString();

    final ref = json['referencedObjectId'];
    if (ref != null) refId = ref.toString();
    final refKeyRaw = json['referencedObjectKey'];
    if (refKeyRaw is String) refKey = refKeyRaw;
    final refNameRaw = json['referencedObjectName'];
    if (refNameRaw is String) refName = refNameRaw;

    final values = json['objectAttributeValues'];
    if (values is List && values.isNotEmpty) {
      final first = values.first;
      if (first is Map<String, dynamic>) {
        final dv = first['displayValue'];
        if (dv is String && dv.isNotEmpty) value = dv;
        final v = first['value'];
        if (v is String && value.isEmpty) value = v;
        if (v is num) value = v.toString();
        final rid = first['referencedObjectId'];
        if (rid != null) refId = rid.toString();
      }
    }

    return AssetAttribute(
      id: _toInt(json['objectTypeAttributeId'] ?? json['id']),
      name: (json['name'] ?? '').toString(),
      value: value,
      referencedObjectId: refId,
      referencedObjectKey: refKey,
      referencedObjectName: refName,
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// Объект Jira Assets (актив, помещение, сотрудник...).
class AssetObject {
  final int id;
  final String objectKey;
  final int objectTypeId;
  final String name;
  final List<AssetAttribute> attributes;

  const AssetObject({
    required this.id,
    required this.objectKey,
    required this.objectTypeId,
    required this.name,
    required this.attributes,
  });

  /// Значение атрибута по списку кандидатов имён (без учёта регистра).
  String? attributeValue(List<String> candidates) {
    final lower = candidates.map((c) => c.toLowerCase()).toList();
    for (final attr in attributes) {
      final n = attr.name.toLowerCase();
      for (final c in lower) {
        if (n == c || n.contains(c)) return attr.value;
      }
    }
    return null;
  }

  AssetAttribute? attributeByName(List<String> candidates) {
    final lower = candidates.map((c) => c.toLowerCase()).toList();
    for (final attr in attributes) {
      final n = attr.name.toLowerCase();
      for (final c in lower) {
        if (n == c || n.contains(c)) return attr;
      }
    }
    return null;
  }

  factory AssetObject.fromJson(Map<String, dynamic> json) {
    final attrsRaw = json['attributes'];
    final attrs = <AssetAttribute>[];
    if (attrsRaw is List) {
      for (final a in attrsRaw) {
        if (a is Map<String, dynamic>) {
          attrs.add(AssetAttribute.fromJson(a));
        }
      }
    }
    return AssetObject(
      id: _toInt(json['id']),
      objectKey: (json['objectKey'] ?? '').toString(),
      objectTypeId: _toInt(json['objectTypeId']),
      name: (json['name'] ?? '').toString(),
      attributes: attrs,
    );
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// Определение атрибута типа объекта (для динамического UI).
class AssetAttributeDef {
  final int id;
  final String name;
  final String type;

  const AssetAttributeDef({
    required this.id,
    required this.name,
    required this.type,
  });

  factory AssetAttributeDef.fromJson(Map<String, dynamic> json) {
    return AssetAttributeDef(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      name: (json['name'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
    );
  }
}

/// Пользователь Jira (для проверки входа).
class JiraUser {
  final String name;
  final String displayName;
  final String email;

  const JiraUser({
    required this.name,
    required this.displayName,
    required this.email,
  });

  factory JiraUser.fromJson(Map<String, dynamic> json) {
    return JiraUser(
      name: (json['name'] ?? '').toString(),
      displayName: (json['displayName'] ?? json['name'] ?? '').toString(),
      email: (json['emailAddress'] ?? '').toString(),
    );
  }
}

/// Результат создания заявки Jira Service Management.
class JsmRequestResult {
  final String issueKey;
  final String issueId;

  const JsmRequestResult({required this.issueKey, required this.issueId});

  factory JsmRequestResult.fromJson(Map<String, dynamic> json) {
    return JsmRequestResult(
      issueKey: (json['issueKey'] ?? '').toString(),
      issueId: (json['issueId'] ?? '').toString(),
    );
  }
}

/// Ошибка Jira API с понятным текстом для UI.
class JiraApiException implements Exception {
  final String message;
  final int? statusCode;

  const JiraApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
