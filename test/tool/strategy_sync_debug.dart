import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_model_strategy.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

Future<void> main() async {
  final settings = InMemorySettingsRepository();
  print('DEFAULT CONFIG: ${await settings.getAiProviderConfig()}');

  await settings.saveAiProviderConfig(const AiProviderConfig(
    id: 'default',
    displayName: '默认',
    baseUrl: 'https://example.com/v1',
    model: 'old-model',
    apiKey: 'test-key',
  ));
  print('AFTER SAVE: ${(await settings.getAiProviderConfig())?.model}');

  final store = AiModelStrategyStore(settings);
  final loaded = await store.load();
  print('AFTER LOAD: general=${loaded.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel} '
      'providerId=${loaded.routeFor(AiTaskProfile.generalAnalysis)?.primaryProviderId}');
  print('RAW STORED: ${await settings.getString(AiModelStrategyStore.storageKey)}');

  const upgraded = AiProviderConfig(
    id: 'default',
    displayName: '默认',
    baseUrl: 'https://example.com/v1',
    model: 'vision-pro',
    apiKey: 'test-key',
  );
  final synced = await store.syncWithProvider(upgraded);
  print('AFTER SYNC: general=${synced.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel} '
      'document=${synced.routeFor(AiTaskProfile.documentLayout)?.primaryModel}');
  print('RAW AFTER SYNC: ${await settings.getString(AiModelStrategyStore.storageKey)}');

  final reloaded = await AiModelStrategyStore(settings).load();
  print('RAW BEFORE RELOAD: ${await settings.getString(AiModelStrategyStore.storageKey)}');
  print('AFTER RELOAD: general=${reloaded.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel} '
      'providerId=${reloaded.routeFor(AiTaskProfile.generalAnalysis)?.primaryProviderId}');
  print('RAW AFTER RELOAD: ${await settings.getString(AiModelStrategyStore.storageKey)}');
  print('PROVIDER AFTER RELOAD: ${(await settings.getAiProviderConfig())?.model}');
}
