import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/widgets/home_action_sections.dart';

Widget _host() {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: BestNextActionCard(
          icon: Icons.replay,
          title: '先复习 3 道到期错题',
          reason: '先处理今天到期的内容，保持学习节奏。',
          meta: '预计 9 分钟 · 优先级较高',
          action: '开始复习',
          streakDays: 2,
          onTap: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('primary action card fits compact phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('先复习 3 道到期错题'), findsOneWidget);
    expect(find.text('开始复习'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary action card keeps side action on wide layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('开始复习'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
