import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/app/router.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

class _TestSettingsRepository implements SettingsRepository {
  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => null;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {}

  @override
  Future<String?> getString(String key) async => null;

  @override
  Future<void> setString(String key, String value) async {}

  @override
  Future<bool> isQuickCaptureEnabled() async => false;

  @override
  Future<void> setQuickCaptureEnabled(bool enabled) async {}
}

void main() {
  test('router exposes primary tabs and supported deep links', () {
    final notifier = OnboardingNotifier(initialDone: true);
    final router = buildRouter(
      _TestSettingsRepository(),
      onboardingNotifier: notifier,
    );
    addTearDown(router.dispose);
    addTearDown(notifier.dispose);

    for (final path in <String>[
      '/',
      '/notebook',
      '/review',
      '/settings',
      '/add',
      '/export',
      '/capture/split-confirmation',
    ]) {
      expect(
        router.configuration.findMatch(Uri.parse(path)).matches,
        isNotEmpty,
        reason: 'expected route to resolve: $path',
      );
    }
  });
}
