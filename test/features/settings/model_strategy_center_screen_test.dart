import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_model_strategy.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/model_strategy_center_screen.dart';

void main() {
  testWidgets('shows visible presets and persists strategy selection',
      (tester) async {
    final settings = InMemorySettingsRepository();
    await settings.saveAiProviderConfig(const AiProviderConfig(
      id: 'openai',
      displayName: 'OpenAI',
      baseUrl: 'https://api.example.com/v1',
      model: 'model-a',
      apiKey: 'test-key',
    ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: const MaterialApp(home: ModelStrategyCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型策略中心'), findsOneWidget);
    expect(find.text('当前：均衡'), findsOneWidget);
    expect(find.byKey(const Key('model-strategy-balanced')), findsOneWidget);
    expect(find.text('OpenAI', skipOffstage: false), findsOneWidget);

    final economy = find.byKey(
      const Key('model-strategy-economy'),
      skipOffstage: false,
    );
    tester.widget<InkWell>(economy).onTap!();
    await tester.pumpAndSettle();

    expect(find.text('当前：省钱优先'), findsOneWidget);
    expect((await AiModelStrategyStore(settings).load()).preset,
        AiStrategyPreset.economy);
  });

  testWidgets('privacy strategy explains missing private provider',
      (tester) async {
    final settings = InMemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
        child: const MaterialApp(home: ModelStrategyCenterScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final privacy = find.byKey(
      const Key('model-strategy-privacy'),
      skipOffstage: false,
    );
    tester.widget<InkWell>(privacy).onTap!();
    await tester.pump();

    expect(find.text('请先在高级设置中配置本地或私有服务，再启用隐私优先'),
        findsOneWidget);
    expect((await AiModelStrategyStore(settings).load()).preset,
        AiStrategyPreset.balanced);
  });
}
