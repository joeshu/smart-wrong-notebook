import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_model_strategy.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

void main() {
  test('migrates legacy provider into balanced task routes', () async {
    final settings = InMemorySettingsRepository();
    const legacy = AiProviderConfig(
      id: 'legacy-openai',
      displayName: 'Legacy OpenAI',
      baseUrl: 'https://example.com/v1',
      model: 'vision-model',
      apiKey: 'test-key',
    );
    await settings.saveAiProviderConfig(legacy);

    final store = AiModelStrategyStore(settings);
    final strategy = await store.load();

    expect(strategy.preset, AiStrategyPreset.balanced);
    expect(strategy.routes, hasLength(AiTaskProfile.values.length));
    expect(
      strategy.routeFor(AiTaskProfile.generalAnalysis)?.primaryProviderId,
      'legacy-openai',
    );
    expect(
      strategy.routeFor(AiTaskProfile.specializedAnalysis)?.primaryModel,
      'vision-model',
    );
    expect(await settings.getString(AiModelStrategyStore.storageKey), isNotEmpty);
  });

  test('persists selected preset without losing migrated routes', () async {
    final settings = InMemorySettingsRepository();
    final store = AiModelStrategyStore(settings);
    final original = await store.load();

    final updated = await store.selectPreset(AiStrategyPreset.accuracy);
    final restored = await AiModelStrategyStore(settings).load();

    expect(updated.preset, AiStrategyPreset.accuracy);
    expect(restored.preset, AiStrategyPreset.accuracy);
    expect(restored.routes.length, original.routes.length);
    expect(restored.complexProblemReviewEnabled, isTrue);
  });

  test('corrupt strategy falls back to legacy migration', () async {
    final settings = InMemorySettingsRepository();
    await settings.setString(AiModelStrategyStore.storageKey, '{broken');

    final strategy = await AiModelStrategyStore(settings).load();

    expect(strategy.preset, AiStrategyPreset.balanced);
    expect(strategy.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel,
        'test-model');
  });
}
