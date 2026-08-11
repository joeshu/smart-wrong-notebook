import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

class LayoutProviderRepository {
  static const _configKey = 'layout_provider_config_v1';
  static const _legacyApiKey = 'layout_provider_api_key_v1';
  static const _legacySecondaryApiKey = 'layout_provider_secondary_api_key_v1';
  static const _paddleApiKey = 'layout_provider_paddle_api_key_v2';
  static const _mineruApiKey = 'layout_provider_mineru_api_key_v2';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<LayoutProviderConfig> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_configKey);
    if (raw == null || raw.isEmpty) {
      return const LayoutProviderConfig(type: LayoutProviderType.currentVision);
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final type = LayoutProviderType.values.firstWhere(
        (item) => item.name == json['type'],
        orElse: () => LayoutProviderType.currentVision,
      );
      String apiKey = '';
      String secondaryApiKey = '';
      try {
        final paddle = await readPaddleToken();
        final mineru = await readMineruToken();
        if (type == LayoutProviderType.mineruCloud) {
          apiKey = mineru.isNotEmpty ? mineru : paddle;
        } else if (type == LayoutProviderType.autoCloud) {
          apiKey = paddle;
          secondaryApiKey = mineru;
        } else {
          apiKey = paddle;
        }
      } catch (_) {
        // Do not erase the selected service merely because Keychain is
        // temporarily unavailable. The UI can now report that re-entry is needed.
      }
      return LayoutProviderConfig(
        type: type,
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: apiKey,
        secondaryApiKey: secondaryApiKey,
      );
    } catch (_) {
      return const LayoutProviderConfig(type: LayoutProviderType.currentVision);
    }
  }

  Future<LayoutProviderConfig> loadForType(LayoutProviderType type) async {
    final selected = await load();
    final paddle = await readPaddleToken();
    final mineru = await readMineruToken();
    return LayoutProviderConfig(
      type: type,
      baseUrl: selected.baseUrl,
      apiKey: type == LayoutProviderType.mineruCloud ? mineru : paddle,
      secondaryApiKey: type == LayoutProviderType.autoCloud ? mineru : '',
    );
  }

  Future<void> save(LayoutProviderConfig config) async {
    if (config.type == LayoutProviderType.mineruCloud) {
      await _secureStorage.write(key: _mineruApiKey, value: config.apiKey);
    } else if (config.type == LayoutProviderType.autoCloud) {
      await _secureStorage.write(key: _paddleApiKey, value: config.apiKey);
      await _secureStorage.write(key: _mineruApiKey, value: config.secondaryApiKey);
    } else if (config.type == LayoutProviderType.paddleCloud) {
      await _secureStorage.write(key: _paddleApiKey, value: config.apiKey);
    }
    await (await SharedPreferences.getInstance()).setString(_configKey, jsonEncode({
      'type': config.type.name,
      'baseUrl': config.baseUrl,
    }));
  }

  Future<String> readPaddleToken() async {
    final current = await _secureStorage.read(key: _paddleApiKey);
    return current ?? await _secureStorage.read(key: _legacyApiKey) ?? '';
  }

  Future<String> readMineruToken() async {
    final current = await _secureStorage.read(key: _mineruApiKey);
    return current ?? await _secureStorage.read(key: _legacySecondaryApiKey) ?? '';
  }
}
