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

  test('syncWithProvider aligns single-provider routes to the new model',
      () async {
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

    expect(synced.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel,
        'vision-pro');
    expect(synced.routeFor(AiTaskProfile.specializedAnalysis)?.primaryModel,
        'vision-pro');
    expect(synced.routeFor(AiTaskProfile.documentLayout)?.primaryModel,
        'vision-pro');

    final reloaded = await AiModelStrategyStore(settings).load();
    expect(reloaded.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel,
        'vision-pro');
  });

  test('syncWithProvider fills empty routes without overwriting custom ones',
      () async {
    final settings = InMemorySettingsRepository();
    await settings.saveAiProviderConfig(const AiProviderConfig(
      id: 'default',
      displayName: '默认',
      baseUrl: 'https://example.com/v1',
      model: 'current-model',
      apiKey: 'test-key',
    ));
    final store = AiModelStrategyStore(settings);
    final migrated = await store.load();

    // 模拟用户把复杂题分析改成了另一个提供方/模型，其余路由保持默认形态。
    final custom = migrated.copyWith(
      routes: migrated.routes
          .map((route) => route.task == AiTaskProfile.specializedAnalysis
              ? route.copyWith(
                  primaryProviderId: 'premium-provider',
                  primaryModel: 'custom-premium',
                )
              : route)
          .toList(growable: false),
    );
    await store.save(custom);

    const changed = AiProviderConfig(
      id: 'default',
      displayName: '默认',
      baseUrl: 'https://example.com/v1',
      model: 'another-model',
      apiKey: 'test-key',
    );
    final synced = await store.syncWithProvider(changed);

    // 多提供方形态：不再整体跟随，只补空模型路由。
    expect(
      synced.routeFor(AiTaskProfile.specializedAnalysis)?.primaryModel,
      'custom-premium',
    );
    expect(
      synced.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel,
      'another-model',
    );
  });

  test('syncWithProvider keeps custom model under same provider',
      () async {
    final settings = InMemorySettingsRepository();
    await settings.saveAiProviderConfig(const AiProviderConfig(
      id: 'default',
      displayName: '默认',
      baseUrl: 'https://example.com/v1',
      model: 'current-model',
      apiKey: 'test-key',
    ));
    final store = AiModelStrategyStore(settings);
    final migrated = await store.load();

    // 同一提供方下，把风险字段复核固定为专用模型。
    final custom = migrated.copyWith(
      routes: migrated.routes
          .map((route) => route.task == AiTaskProfile.riskReview
              ? route.copyWith(primaryModel: 'review-guard-model')
              : route)
          .toList(growable: false),
    );
    await store.save(custom);

    const changed = AiProviderConfig(
      id: 'default',
      displayName: '默认',
      baseUrl: 'https://example.com/v1',
      model: 'another-model',
      apiKey: 'test-key',
    );
    final synced = await store.syncWithProvider(changed);

    // 两条不同非空模型属于多模型形态，保留手工配置。
    expect(
      synced.routeFor(AiTaskProfile.riskReview)?.primaryModel,
      'review-guard-model',
    );
    expect(
      synced.routeFor(AiTaskProfile.generalAnalysis)?.primaryModel,
      'another-model',
    );
  });
}
