import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

class LayoutProviderRepository {
  static const _configKey = 'layout_provider_config_v1';
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
      return LayoutProviderConfig(
        type: type,
        baseUrl: json['baseUrl'] as String? ?? '',
      );
    } catch (_) {
      return const LayoutProviderConfig(type: LayoutProviderType.currentVision);
    }
  }

  Future<LayoutProviderConfig> loadForType(LayoutProviderType type) async {
    final selected = await load();
    return LayoutProviderConfig(
      type: type,
      baseUrl: selected.baseUrl,
    );
  }

  Future<void> save(LayoutProviderConfig config) async {
    await (await SharedPreferences.getInstance()).setString(_configKey, jsonEncode({
      'type': config.type.name,
      'baseUrl': config.baseUrl,
    }));
  }
}
