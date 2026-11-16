import '../../data/db/app_database.dart';
import '../../data/jira/jira_client.dart';

/// Доступ к настройкам приложения (хранятся в локальной БД ТСД,
/// не сбрасываются при перезапуске).
class SettingsRepository {
  final AppDatabase db;

  SettingsRepository(this.db);

  Future<AppSetting?> load() => db.settingsDao.getSettings();

  Future<void> save(AppSettingsCompanion companion) =>
      db.settingsDao.saveSettings(companion);

  /// Клиент Jira на сервисном аккаунте из настроек.
  /// null — если настройки не заполнены.
  JiraClient? buildClient(AppSetting? settings) {
    if (settings == null) return null;
    if (settings.jiraBaseUrl.trim().isEmpty) return null;
    if (settings.jiraServiceLogin.trim().isEmpty) return null;
    if (settings.jiraApiToken.trim().isEmpty) return null;
    return JiraClient(
      baseUrl: settings.jiraBaseUrl,
      login: settings.jiraServiceLogin,
      token: settings.jiraApiToken,
    );
  }
}
