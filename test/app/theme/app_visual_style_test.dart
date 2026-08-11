import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all visual styles expose distinct theme tokens', () {
    final primaryColors = <Color>{};
    final backgrounds = <Color>{};
    final radii = <double>{};

    for (final style in AppVisualStyle.values) {
      final theme = buildLightTheme(style: style);
      final tokens = theme.extension<AppVisualTokens>();
      expect(tokens, isNotNull);
      expect(tokens?.style, style);
      primaryColors.add(theme.colorScheme.primary);
      backgrounds.add(theme.scaffoldBackgroundColor);
      radii.add(tokens!.cardRadius);
    }

    expect(primaryColors, hasLength(AppVisualStyle.values.length));
    expect(backgrounds, hasLength(AppVisualStyle.values.length));
    expect(radii.length, greaterThanOrEqualTo(3));
  });

  test('each style supports light and dark modes', () {
    for (final style in AppVisualStyle.values) {
      final light = buildLightTheme(style: style);
      final dark = buildDarkTheme(style: style);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
      expect(light.extension<AppVisualTokens>()?.style, style);
      expect(dark.extension<AppVisualTokens>()?.style, style);
    }
  });

  test('visual style notifier persists selection', () async {
    final settings = InMemorySettingsRepository();
    final notifier = AppVisualStyleNotifier(settings);
    await Future<void>.delayed(Duration.zero);
    await notifier.setStyle(AppVisualStyle.paper);

    expect(notifier.state, AppVisualStyle.paper);
    expect(await settings.getString('app_visual_style'), 'paper');
  });
}
