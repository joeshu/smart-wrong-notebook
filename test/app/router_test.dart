import 'dart:io';

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
  Future<bool> isQuickCaptureEnabled() async {
    final value = await getString('quick_capture_enabled');
    return value == 'true';
  }

  @override
  Future<void> setQuickCaptureEnabled(bool enabled) async {
    await setString('quick_capture_enabled', enabled ? 'true' : 'false');
  }
}

void main() {
  test('router keeps four primary tabs and compatibility deep links', () {
    final notifier = OnboardingNotifier(initialDone: true);
    final router = buildRouter(
      _TestSettingsRepository(),
      onboardingNotifier: notifier,
    );
    addTearDown(router.dispose);
    addTearDown(notifier.dispose);

    final configuration = router.configuration;
    expect(configuration.findMatch(Uri.parse('/')).matches, isNotEmpty);
    expect(configuration.findMatch(Uri.parse('/notebook')).matches, isNotEmpty);
    expect(configuration.findMatch(Uri.parse('/review')).matches, isNotEmpty);
    expect(configuration.findMatch(Uri.parse('/settings')).matches, isNotEmpty);
    expect(configuration.findMatch(Uri.parse('/add')).matches, isNotEmpty);
    expect(configuration.findMatch(Uri.parse('/export')).matches, isNotEmpty);
    expect(configuration.findMatch(Uri.parse('/capture/split-confirmation')).matches,
        isNotEmpty);
  });

  test('primary navigation uses a single centralized capture action', () {
    final source = File('lib/src/app/router.dart').readAsStringSync();

    expect(source, contains('CaptureEntryLauncher.show(context)'));
    expect(source, contains('FloatingActionButtonLocation.centerFloat'));
    expect('StatefulShellBranch('.allMatches(source).length, 4);
    expect(source, contains("path: '/add'"));
    expect(source, contains("path: '/export'"));
    expect(source, contains('label: AppStrings.notebookTab'));
    expect(source, contains('label: AppStrings.reviewTab'));
    expect(source, contains('label: AppStrings.settingsTab'));
  });
}
