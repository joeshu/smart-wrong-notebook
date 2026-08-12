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

  const upgraded = AiProviderConfig(
    id: 'default',
    displayName: '默认',
    baseUrl: 'https://example.com/v1',
    model: 'vision-pro',
    apiKey: 'test-key',
  );
  final synced = await store.syncWithProvider(upgraded);
  print('AFTER SYNC: ${synced.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel}');
  print('RAW AFTER SYNC: ${await settings.getString(AiModelStrategyStore.storageKey)}');

  // 关键：sync 后立刻再 load()，观察是否被覆盖
  final reloaded = await store.load();
  print('AFTER RELOAD: ${reloaded.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel}');
  print('RAW AFTER RELOAD: ${await settings.getString(AiModelStrategyStore.storageKey)}');
}
