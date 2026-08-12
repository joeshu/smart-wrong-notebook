import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('commercial visual token baseline stays stable', () {
    for (final style in AppVisualStyle.values) {
      final light = buildLightTheme(style: style);
      final dark = buildDarkTheme(style: style);
      final lightTokens = light.extension<AppVisualTokens>();
      final darkTokens = dark.extension<AppVisualTokens>();
      expect(lightTokens?.style, style);
      expect(darkTokens?.style, style);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(lightTokens!.cardRadius, greaterThanOrEqualTo(18));
      expect(lightTokens.controlRadius, greaterThanOrEqualTo(8));
      expect(light.colorScheme.primary, isNot(dark.colorScheme.primary));
    }
  });

  testWidgets('baseline card renders in light and dark themes', (tester) async {
    for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(style: AppVisualStyle.academic),
        darkTheme: buildDarkTheme(style: AppVisualStyle.academic),
        themeMode: mode,
        home: const Scaffold(
          body: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('商业化视觉基线'),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('商业化视觉基线'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
