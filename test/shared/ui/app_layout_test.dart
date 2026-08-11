import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_motion.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

void main() {
  test('responsive breakpoints have stable window classes', () {
    expect(AppBreakpoints.windowClass(320), AppWindowClass.compact);
    expect(AppBreakpoints.windowClass(600), AppWindowClass.medium);
    expect(AppBreakpoints.windowClass(900), AppWindowClass.expanded);
    expect(AppBreakpoints.windowClass(1200), AppWindowClass.large);
  });

  testWidgets('AppPage stays within a 320px viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppPage(
            child: Row(
              children: <Widget>[
                Expanded(child: Text('拍一道错题')),
                SizedBox(width: AppSpace.sm),
                Expanded(child: Text('确认识别')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(AppPage)).width, 320);
  });

  testWidgets('AppPage enforces its maximum content width', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPage(
            maxWidth: AppContentWidth.standard,
            child: Builder(
              builder: (context) => Container(
                key: const Key('content'),
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('content'))).width,
      lessThanOrEqualTo(AppContentWidth.standard),
    );
  });

  testWidgets('core task flow does not overflow at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: AppSpace.page,
            child: AppTaskFlow(
              steps: <String>['拍一道错题', '确认识别', '查看错误定位', '开始练习'],
              currentStep: 2,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('查看错误定位'), findsOneWidget);
  });

  testWidgets('reduced motion follows MediaQuery accessibility settings',
      (tester) async {
    bool? reduced;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduced = AppMotion.isReduced(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(reduced, isTrue);
  });
}
