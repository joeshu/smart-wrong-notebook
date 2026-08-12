import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_model_strategy.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

Future<void> main() async {
  final settings = InMemorySettingsRepository();
  await settings.saveAiProviderConfig(const AiProviderConfig(
    id: 'default',
    displayName: '默认',
    baseUrl: 'https://example.com/v1',
    model: 'old-model',
    apiKey: 'test-key',
  ));

  final store = AiModelStrategyStore(settings);
  await store.load();
  print('STEP0 raw after load: ${await settings.getString(AiModelStrategyStore.storageKey)}');

  const upgraded = AiProviderConfig(
    id: 'default',
    displayName: '默认',
    baseUrl: 'https://example.com/v1',
    model: 'vision-pro',
    apiKey: 'test-key',
  );
  final synced = await store.syncWithProvider(upgraded);
  print('STEP1 raw right after sync: ${await settings.getString(AiModelStrategyStore.storageKey)}');
  print('STEP1 synced.general=${synced.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel}');

  // 再次直接 sync，观察返回对象与存储
  final synced2 = await store.syncWithProvider(upgraded);
  print('STEP2 raw right after second sync: ${await settings.getString(AiModelStrategyStore.storageKey)}');
  print('STEP2 synced2.general=${synced2.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel}');

  // 直接用 settings 读 raw，确认读路径
  final raw = await settings.getString(AiModelStrategyStore.storageKey);
  print('STEP3 raw via settings: $raw');

  // 手动 decode 检查
  if (raw != null && raw.isNotEmpty) {
    final decoded = AiModelStrategy.decode(raw);
    print('STEP3 decoded.general=${decoded.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel}');
  }
}
