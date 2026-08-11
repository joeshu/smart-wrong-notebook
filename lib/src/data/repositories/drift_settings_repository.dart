import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db, {FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _apiKeyStorageKey = 'ai_provider_api_key';
  final AppDatabase _db;
  final FlutterSecureStorage _secureStorage;

  @override
  Future<AiProviderConfig?> getAiProviderConfig() async {
    final id = await getString('ai_provider_id');
    final displayName = await getString('ai_provider_display_name');
    final baseUrl = await getString('ai_base_url');
    final secureApiKey = await _secureStorage.read(key: _apiKeyStorageKey);
    // Upgrade the legacy database key in place, then remove plaintext.
    final legacyApiKey = await getString('ai_api_key');
    final model = await getString('ai_model');
    final apiKey = secureApiKey ?? legacyApiKey;
    if (secureApiKey == null && legacyApiKey != null && legacyApiKey.isNotEmpty) {
      await _secureStorage.write(key: _apiKeyStorageKey, value: legacyApiKey);
      await _deleteString('ai_api_key');
    }
    if (id == null || displayName == null || baseUrl == null || apiKey == null || model == null) return null;
    final timeoutStr = await getString('ai_timeout_seconds');
    final serviceTypeStr = await getString('ai_service_type');
    final concurrencyStr = await getString('ai_max_concurrency');
    final privateStr = await getString('ai_provider_private');
    return AiProviderConfig(
      id: id,
      displayName: displayName,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      maxConcurrency: int.tryParse(concurrencyStr ?? '') ?? 2,
      timeoutSeconds: int.tryParse(timeoutStr ?? '') ?? 60,
      serviceType: AiServiceType.fromSerializedName(serviceTypeStr),
      isPrivate: privateStr == 'true',
    );
  }

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {
    await setString('ai_provider_id', config.id);
    await setString('ai_provider_display_name', config.displayName);
    await setString('ai_base_url', config.baseUrl);
    await _secureStorage.write(key: _apiKeyStorageKey, value: config.apiKey);
    await _deleteString('ai_api_key');
    await setString('ai_model', config.model);
    await setString('ai_timeout_seconds', config.timeoutSeconds.toString());
    await setString('ai_service_type', config.serviceType.serializedName);
    await setString('ai_max_concurrency', config.maxConcurrency.toString());
    await setString('ai_provider_private', config.isPrivate.toString());
  }

  @override
  Future<String?> getString(String key) async {
    final row = await (_db.select(_db.settingsEntries)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _deleteString(String key) async {
    await (_db.delete(_db.settingsEntries)..where((t) => t.key.equals(key))).go();
  }

  @override
  Future<void> setString(String key, String value) async {
    await _db.into(_db.settingsEntries).insertOnConflictUpdate(
          SettingsEntriesCompanion(
            key: Value(key),
            value: Value(value),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<bool> isQuickCaptureEnabled() async {
    final value = await getString('quick_capture_enabled');
    return value == 'true';
  }

  @override
  Future<void> setQuickCaptureEnabled(bool enabled) async {
    await setString('quick_capture_enabled', enabled ? 'true' : 'false');
  }
}