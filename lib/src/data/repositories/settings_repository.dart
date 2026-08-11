import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

abstract class SettingsRepository {
  Future<AiProviderConfig?> getAiProviderConfig();
  Future<void> saveAiProviderConfig(AiProviderConfig config);
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);

  /// 是否启用"拍照即录极速模式"。
  ///
  /// 极速模式开启后，拍照/选图完成会跳过裁剪与校对页，直接进入 AI 解析。
  /// 默认关闭（false）。子类通常无需重写，直接复用 [getString]/[setString]
  /// 即可；但 `implements` 形式的实现类需要按 Dart 规则显式提供实现。
  Future<bool> isQuickCaptureEnabled() async {
    final value = await getString('quick_capture_enabled');
    return value == 'true';
  }

  /// 写入极速模式开关。
  Future<void> setQuickCaptureEnabled(bool enabled) async {
    await setString('quick_capture_enabled', enabled ? 'true' : 'false');
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  AiProviderConfig? _config;
  final Map<String, String> _strings = {};

  InMemorySettingsRepository() {
    _config = const AiProviderConfig(
      id: 'test',
      displayName: 'Test',
      baseUrl: 'https://api.test.com',
      model: 'test-model',
      apiKey: 'test-key',
    );
  }

  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => _config;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {
    _config = config;
  }

  @override
  Future<String?> getString(String key) async => _strings[key];

  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
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
