import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

class SharedPrefsSettingsRepository implements SettingsRepository {
  SharedPrefsSettingsRepository._();

  static final SharedPrefsSettingsRepository _instance = SharedPrefsSettingsRepository._();
  static SharedPrefsSettingsRepository get instance => _instance;

  static const _configKey = 'ai_provider_config';
  static const _apiKeyStorageKey = 'ai_provider_api_key';

  SharedPreferences? _prefs;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  Future<AiProviderConfig?> getAiProviderConfig() async {
    final json = await _getString(_configKey);
    if (json == null || json.isEmpty) return null;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final secureApiKey = await _secureStorage.read(key: _apiKeyStorageKey);
      final legacyApiKey = map['apiKey'] as String? ?? '';

      // One-way upgrade for existing installs: move the old plaintext key to
      // Keychain/Keystore, then immediately rewrite the preferences payload.
      final apiKey = secureApiKey ?? legacyApiKey;
      if (secureApiKey == null && legacyApiKey.isNotEmpty) {
        await _secureStorage.write(key: _apiKeyStorageKey, value: legacyApiKey);
        map.remove('apiKey');
        await _setString(_configKey, jsonEncode(map));
      }

      return AiProviderConfig(
        id: map['id'] as String? ?? 'default',
        displayName: map['displayName'] as String? ?? '默认',
        baseUrl: map['baseUrl'] as String? ?? '',
        model: map['model'] as String? ?? '',
        apiKey: apiKey,
        maxConcurrency:
            (map['maxConcurrency'] as num?)?.toInt() ?? 2,
        timeoutSeconds:
            (map['timeoutSeconds'] as num?)?.toInt() ?? 60,
        serviceType: AiServiceType.fromSerializedName(
            map['serviceType'] as String?),
        isPrivate: map['isPrivate'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {
    await _secureStorage.write(key: _apiKeyStorageKey, value: config.apiKey);
    await _setString(_configKey, jsonEncode({
      'id': config.id,
      'displayName': config.displayName,
      'baseUrl': config.baseUrl,
      'model': config.model,
      'maxConcurrency': config.maxConcurrency,
      'timeoutSeconds': config.timeoutSeconds,
      'serviceType': config.serviceType.serializedName,
      'isPrivate': config.isPrivate,
    }));
  }

  @override
  Future<String?> getString(String key) async {
    return _getString('setting_$key');
  }

  @override
  Future<void> setString(String key, String value) async {
    await _setString('setting_$key', value);
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

  Future<String?> _getString(String key) async {
    return (await _preferences).getString(key);
  }

  Future<void> _setString(String key, String value) async {
    await (await _preferences).setString(key, value);
  }
}
