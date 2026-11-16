import 'dart:convert';

import 'package:dio/dio.dart';

import 'models.dart';

/// Прямой клиент Jira REST API (без промежуточного бэкенда).
///
/// Авторизация: HTTP Basic (логин + API-токен/PAT).
///  - Jira Cloud: логин = email, токен = API token Atlassian.
///  - Jira Server/Data Center: логин = username (AD), токен = PAT
///    или пароль (если PAT не включён).
///
/// Используемые эндпоинты (официальная документация Atlassian):
///  - GET  /rest/api/2/myself
///  - GET  /rest/assets/1.0/aql/objects        — поиск объектов (AQL)
///  - GET  /rest/assets/1.0/object/{id}        — объект
///  - PUT  /rest/assets/1.0/object/{id}        — обновление атрибутов
///  - GET  /rest/assets/1.0/objecttype/{id}/attributes — структура полей
///  - POST /rest/servicedeskapi/request        — заявка JSM
///  - POST /rest/servicedeskapi/request/{key}/attachment — вложение
class JiraClient {
  final Dio _dio;

  JiraClient({
    required String baseUrl,
    required String login,
    required String token,
  }) : _dio = Dio(
          BaseOptions(
            baseUrl: _normalizeBase(baseUrl),
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('$login:$token'))}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
          ),
        );

  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  // -------------------------------------------------------------------------
  // Проверка связи / авторизация
  // -------------------------------------------------------------------------

  /// Проверка учётных данных пользователя (экран входа).
  Future<JiraUser> getMyself() async {
    final res = await _guard(() => _dio.get('/rest/api/2/myself'));
    return JiraUser.fromJson(_asMap(res.data));
  }

  /// Тестовый запрос схемы (кнопка «Проверить связь с Jira»).
  /// Лёгкий AQL-запрос на 1 объект: проверяет и доступность API,
  /// и существование схемы.
  Future<void> testSchemaConnection(String schemaId) async {
    await _guard(
      () => _dio.get(
        '/rest/assets/1.0/aql/objects',
        queryParameters: {
          'objectSchemaId': schemaId,
          'resultPerPage': 1,
          'includeAttributes': false,
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Assets: объекты
  // -------------------------------------------------------------------------

  /// Поиск всех объектов схемы с пагинацией (AQL).
  Future<List<AssetObject>> searchAllObjects({
    required String schemaId,
    String? qlQuery,
    int pageSize = 100,
  }) async {
    final all = <AssetObject>[];
    var page = 1;
    while (true) {
      final res = await _guard(
        () => _dio.get(
          '/rest/assets/1.0/aql/objects',
          queryParameters: {
            'objectSchemaId': schemaId,
            if (qlQuery != null && qlQuery.isNotEmpty) 'qlQuery': qlQuery,
            'page': page,
            'resultPerPage': pageSize,
            'includeAttributes': true,
          },
        ),
      );
      final data = _asMap(res.data);
      final values = _extractList(data);
      for (final v in values) {
        if (v is Map<String, dynamic>) {
          all.add(AssetObject.fromJson(v));
        }
      }
      final total = _toInt(data['total']);
      if (values.isEmpty || (total > 0 && all.length >= total)) break;
      if (total == 0 && values.length < pageSize) break;
      page++;
      // Защита от бесконечной пагинации при странных ответах.
      if (page > 1000) break;
    }
    return all;
  }

  /// Один объект по ID.
  Future<AssetObject> getObject(int id) async {
    final res = await _guard(() => _dio.get('/rest/assets/1.0/object/$id'));
    return AssetObject.fromJson(_asMap(res.data));
  }

  /// Обновление одного атрибута объекта (например, дата инвентаризации).
  Future<void> updateObjectAttribute({
    required int objectId,
    required int objectTypeId,
    required int attributeId,
    required String value,
  }) async {
    await _guard(
      () => _dio.put(
        '/rest/assets/1.0/object/$objectId',
        data: {
          'objectTypeId': objectTypeId,
          'attributes': [
            {
              'objectTypeAttributeId': attributeId,
              'objectAttributeValues': [
                {'value': value},
              ],
            },
          ],
        },
      ),
    );
  }

  /// Структура полей типа объекта (динамические атрибуты).
  Future<List<AssetAttributeDef>> getObjectTypeAttributes(
    int objectTypeId,
  ) async {
    final res = await _guard(
      () => _dio.get(
        '/rest/assets/1.0/objecttype/$objectTypeId/attributes',
      ),
    );
    final data = res.data;
    final list = data is List ? data : _extractList(_asMap(data));
    return list
        .whereType<Map<String, dynamic>>()
        .map(AssetAttributeDef.fromJson)
        .toList();
  }

  // -------------------------------------------------------------------------
  // Jira Service Management: заявки
  // -------------------------------------------------------------------------

  /// Создание заявки (перемещение / изменение данных).
  /// Текст «Было -> Стало» формируется вызывающим кодом.
  Future<JsmRequestResult> createRequest({
    required String serviceDeskId,
    required String requestTypeId,
    required String summary,
    required String description,
  }) async {
    final res = await _guard(
      () => _dio.post(
        '/rest/servicedeskapi/request',
        data: {
          'serviceDeskId': serviceDeskId,
          'requestTypeId': requestTypeId,
          'requestFieldValues': {
            'summary': summary,
            'description': description,
          },
        },
      ),
    );
    return JsmRequestResult.fromJson(_asMap(res.data));
  }

  /// Вложение фото к заявке (Attachment).
  Future<void> uploadAttachment({
    required String issueKey,
    required String filePath,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: 'defect_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    });
    await _guard(
      () => _dio.post(
        '/rest/servicedeskapi/request/$issueKey/attachment',
        data: form,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Внутреннее
  // -------------------------------------------------------------------------

  Future<Response<dynamic>> _guard(
    Future<Response<dynamic>> Function() call,
  ) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  JiraApiException _toApiException(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return JiraApiException(
        'Доступ запрещён (401/403). Проверьте логин и API-токен.',
        statusCode: code,
      );
    }
    if (code == 404) {
      return JiraApiException(
        'Ресурс не найден (404). Проверьте URL Jira и ID схемы.',
        statusCode: code,
      );
    }
    final body = e.response?.data;
    String? serverMessage;
    if (body is Map<String, dynamic>) {
      final errors = body['errorMessages'];
      if (errors is List && errors.isNotEmpty) {
        serverMessage = errors.first.toString();
      } else if (body['message'] is String) {
        serverMessage = body['message'] as String;
      }
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const JiraApiException(
        'Нет соединения с Jira. Проверьте Wi-Fi и URL сервера.',
      );
    }
    return JiraApiException(
      serverMessage ?? 'Ошибка Jira (${code ?? 'сеть'}): ${e.message}',
      statusCode: code,
    );
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  List<dynamic> _extractList(Map<String, dynamic> data) {
    for (final key in ['values', 'objects', 'results', 'data']) {
      final v = data[key];
      if (v is List) return v;
    }
    return const [];
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
