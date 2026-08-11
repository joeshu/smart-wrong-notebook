import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/data_management_screen.dart';

QuestionRecord _question(String id) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目',
    normalizedQuestionText: '题目',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

ReviewLog _reviewLog(String questionId) {
  return ReviewLog(
    id: 'log-$questionId',
    questionRecordId: questionId,
    reviewedAt: DateTime(2026),
    result: 'reviewing',
    masteryAfter: MasteryLevel.reviewing,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AiAnalysisService.diagnosticsRawResponseEnabledKey: false,
      AiAnalysisService.diagnosticsRawRetentionDaysKey: 7,
    });
  });

  testWidgets('shows review log count and clears questions with logs',
      (tester) async {
    final questionRepository = InMemoryQuestionRepository();
    final reviewLogRepository = InMemoryReviewLogRepository();
    await questionRepository.saveDraft(_question('q-1'));
    await reviewLogRepository.insert(_reviewLog('q-1'));

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        questionRepositoryProvider.overrideWithValue(questionRepository),
        reviewLogRepositoryProvider.overrideWithValue(reviewLogRepository),
      ],
      child: const MaterialApp(home: DataManagementScreen()),
    ));
    await tester.pumpAndSettle();

    // 滚动到「存储概览」区段，避免新增的学情周报卡片把存储卡片挤出视口。
    await tester.scrollUntilVisible(
      find.text('题库总量'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('题库总量'), findsOneWidget);
    expect(find.text('1 题'), findsOneWidget);
    expect(find.text('复习记录总量'), findsOneWidget);
    expect(find.text('1 条'), findsOneWidget);

    // 「删除所有错题和复习记录，不可恢复」提示位于存储概览上方，需要反向滚动找到。
    await tester.scrollUntilVisible(
      find.text('删除所有错题和复习记录，不可恢复'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('删除所有错题和复习记录，不可恢复'), findsOneWidget);

    final clearData = find.text('清空所有数据');
    await tester.ensureVisible(clearData);
    await tester.pumpAndSettle();
    await tester.tap(clearData);
    await tester.pumpAndSettle();
    expect(find.text('确定要删除全部 1 道错题及其复习记录吗？此操作不可恢复。'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(await questionRepository.listAll(), isEmpty);
    expect(await reviewLogRepository.listAll(), isEmpty);
    // 清空数据后存储概览会更新为 0；滚动到该区段再断言。
    await tester.scrollUntilVisible(
      find.text('题库总量'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('0 题'), findsOneWidget);
    expect(find.text('0 条'), findsOneWidget);
  });

  testWidgets('shows ai diagnostics controls with safe defaults',
      (tester) async {
    final questionRepository = InMemoryQuestionRepository();
    final reviewLogRepository = InMemoryReviewLogRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        questionRepositoryProvider.overrideWithValue(questionRepository),
        reviewLogRepositoryProvider.overrideWithValue(reviewLogRepository),
      ],
      child: const MaterialApp(home: DataManagementScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('AI 诊断数据'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('保存原始 AI 响应用于诊断'), findsOneWidget);
    expect(find.text('默认关闭；仅保存长度、指纹、修复策略与采集时间等安全摘要'),
        findsOneWidget);
    expect(find.text('原始响应保留天数'), findsOneWidget);
    expect(find.text('7 天'), findsOneWidget);
    expect(find.text('清理 AI 原始响应'), findsOneWidget);
  });
}
