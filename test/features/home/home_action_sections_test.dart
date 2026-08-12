import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers/review_providers.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/widgets/home_action_sections.dart';

void main() {
  Widget host({
    required TodayReviewPlan plan,
    int pendingRecognition = 0,
    VoidCallback? onReview,
    VoidCallback? onRecognize,
    VoidCallback? onCapture,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UnifiedActionPanel(
            plan: plan,
            pendingRecognition: pendingRecognition,
            topMistakeCategory: null,
            onOpenReview: onReview ?? () {},
            onOpenRecognize: onRecognize ?? () {},
            onCapture: onCapture ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('prioritizes due review as the primary action', (tester) async {
    var reviewTapped = false;
    await tester.pumpWidget(host(
      plan: const TodayReviewPlan(dueCount: 3, completedCount: 0, streakDays: 2),
      onReview: () => reviewTapped = true,
    ));

    expect(find.text('先复习 3 道到期错题'), findsOneWidget);
    expect(find.text('开始复习'), findsOneWidget);
    await tester.tap(find.text('开始复习').last);
    expect(reviewTapped, isTrue);
  });

  testWidgets('prioritizes recognition before capture when review is empty',
      (tester) async {
    var recognizeTapped = false;
    await tester.pumpWidget(host(
      plan: const TodayReviewPlan(dueCount: 0, completedCount: 0, streakDays: 0),
      pendingRecognition: 2,
      onRecognize: () => recognizeTapped = true,
    ));

    expect(find.text('先确认 2 项识别内容'), findsOneWidget);
    expect(find.text('继续确认'), findsOneWidget);
    await tester.tap(find.text('继续确认').last);
    expect(recognizeTapped, isTrue);
  });

  testWidgets('empty plan keeps capture as the primary action', (tester) async {
    var captureTapped = false;
    await tester.pumpWidget(host(
      plan: const TodayReviewPlan(dueCount: 0, completedCount: 0, streakDays: 0),
      onCapture: () => captureTapped = true,
    ));

    expect(find.text('记录今天遇到的第一道错题'), findsOneWidget);
    expect(find.text('拍一道题'), findsOneWidget);
    await tester.tap(find.text('拍一道题').last);
    expect(captureTapped, isTrue);
  });

  testWidgets('secondary actions stack on narrow layouts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(
      plan: const TodayReviewPlan(dueCount: 2, completedCount: 0, streakDays: 0),
      pendingRecognition: 1,
    ));

    expect(find.text('其他可做'), findsOneWidget);
    expect(find.text('稍后确认识别内容'), findsOneWidget);
    expect(find.text('遇到新错题时随时补充档案'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
