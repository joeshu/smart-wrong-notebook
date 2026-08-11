import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_screen.dart';

QuestionRecord _reviewQuestion(
  String id, {
  String text = 'sample',
  String? rootQuestionId,
  int? splitOrder,
  MasteryLevel masteryLevel = MasteryLevel.newQuestion,
  int reviewCount = 0,
}) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: id,
    imagePath: '/tmp/$id.jpg',
    subject: Subject.math,
    extractedQuestionText: text,
    normalizedQuestionText: text,
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: reviewCount,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: masteryLevel,
    analysisResult: null,
    rootQuestionId: rootQuestionId,
    splitOrder: splitOrder,
  );
}

Future<void> _pumpReviewScreen(
  WidgetTester tester,
  InMemoryQuestionRepository repository, {
  InMemoryReviewLogRepository? reviewLogRepository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        questionRepositoryProvider.overrideWithValue(repository),
        if (reviewLogRepository != null)
          reviewLogRepositoryProvider.overrideWithValue(reviewLogRepository),
      ],
      child: const MaterialApp(home: ReviewScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ReviewScreen', () {
    testWidgets('shows empty state when no questions due', (tester) async {
      await _pumpReviewScreen(tester, InMemoryQuestionRepository());

      expect(find.text('待复习 0'), findsOneWidget);
      expect(find.text('暂无待复习错题'), findsOneWidget);
    });

    testWidgets('shows summary card with correct counts', (tester) async {
      await _pumpReviewScreen(tester, InMemoryQuestionRepository());

      expect(find.text('整体进度'), findsOneWidget);
      expect(find.text('共 0 题'), findsOneWidget);
    });

    testWidgets('shows history link', (tester) async {
      await _pumpReviewScreen(tester, InMemoryQuestionRepository());

      expect(find.byIcon(CupertinoIcons.clock), findsOneWidget);
      expect(find.byTooltip('复习记录'), findsOneWidget);
    });

    testWidgets('shows today progress using distinct reviewed questions',
        (tester) async {
      final repository = InMemoryQuestionRepository();
      final logs = InMemoryReviewLogRepository();
      final now = DateTime.now();
      await repository.saveDraft(_reviewQuestion('q-1', text: '待复习题'));
      await logs.insert(ReviewLog(
        id: 'today-1',
        questionRecordId: 'q-answered',
        reviewedAt: now,
        result: 'mastered',
        masteryAfter: MasteryLevel.mastered,
      ));
      await logs.insert(ReviewLog(
        id: 'today-2',
        questionRecordId: 'q-answered',
        reviewedAt: now,
        result: 'reviewing',
        masteryAfter: MasteryLevel.reviewing,
      ));

      await _pumpReviewScreen(tester, repository, reviewLogRepository: logs);

      expect(find.text('1 / 2 今日完成'), findsOneWidget);
    });

    testWidgets('does not show batch label for standalone due question',
        (tester) async {
      final repository = InMemoryQuestionRepository();
      await repository.saveDraft(_reviewQuestion('q-1', text: '单题'));

      await _pumpReviewScreen(tester, repository);

      expect(find.text('单题'), findsOneWidget);
      expect(find.textContaining('来自同一拍照批次'), findsNothing);
    });

    testWidgets('shows batch labels for due sibling questions', (tester) async {
      // Phase 7-1/7-3 后顶部新增模式选择条 + 第二行统计 _MiniStat，
      // TabBarView 视口变窄，多题场景下 ListView 会懒加载，需要更大的画布
      // 才能让所有题目卡片同时渲染。
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = InMemoryQuestionRepository();
      await repository.saveDrafts(<QuestionRecord>[
        _reviewQuestion('q-1',
            text: '第一题', rootQuestionId: 'root-1', splitOrder: 1),
        _reviewQuestion('q-2',
            text: '第二题', rootQuestionId: 'root-1', splitOrder: 2),
      ]);

      await _pumpReviewScreen(tester, repository);

      expect(find.text('第一题'), findsOneWidget);
      expect(find.text('第二题'), findsOneWidget);
      expect(find.text('来自同一拍照批次 · 第 1 题'), findsOneWidget);
      expect(find.text('来自同一拍照批次 · 第 2 题'), findsOneWidget);
    });

    testWidgets('shows mastery status without quick action buttons',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = InMemoryQuestionRepository();
      await repository.saveDrafts(<QuestionRecord>[
        _reviewQuestion('q-new', text: '新增题'),
        _reviewQuestion('q-reviewing',
            text: '复习题', masteryLevel: MasteryLevel.reviewing),
      ]);

      await _pumpReviewScreen(tester, repository);

      expect(find.text('新增题'), findsOneWidget);
      expect(find.text('复习题'), findsOneWidget);
      expect(find.text('待复习'), findsWidgets);
      expect(find.text('仍需复习'), findsNothing);
      expect(find.text('继续巩固'), findsNothing);
      expect(find.widgetWithText(FilledButton, '已掌握'), findsNothing);
    });

    testWidgets('Phase 7-1: shows review mode segmented button '
        '(顺序/随机/专项) and Phase 7-3 stats row', (tester) async {
      await _pumpReviewScreen(tester, InMemoryQuestionRepository());

      // 模式选择条
      expect(find.text('顺序'), findsOneWidget);
      expect(find.text('随机'), findsOneWidget);
      expect(find.text('专项'), findsOneWidget);

      // 复习统计（近 7 天 / 掌握率 / 连续天）
      expect(find.text('近7天'), findsOneWidget);
      expect(find.text('掌握率'), findsOneWidget);
      expect(find.text('连续天'), findsOneWidget);
    });

    testWidgets('Phase 7-1: default mode is sequential (no focused chip)',
        (tester) async {
      await _pumpReviewScreen(tester, InMemoryQuestionRepository());

      // 默认顺序模式，不应出现「正在专项复习」提示
      expect(find.textContaining('正在专项复习'), findsNothing);
      expect(find.text('退出专项'), findsNothing);
    });

    testWidgets('Phase 7-1: random mode persists selection without crash',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repository = InMemoryQuestionRepository();
      await repository.saveDrafts(<QuestionRecord>[
        _reviewQuestion('q-1', text: '题目一'),
        _reviewQuestion('q-2', text: '题目二'),
        _reviewQuestion('q-3', text: '题目三'),
      ]);

      await _pumpReviewScreen(tester, repository);

      // 切换到随机模式
      await tester.tap(find.text('随机'));
      await tester.pumpAndSettle();

      // 随机模式下三道题仍应都展示（顺序可能不同，但内容必须存在）
      expect(find.text('题目一'), findsOneWidget);
      expect(find.text('题目二'), findsOneWidget);
      expect(find.text('题目三'), findsOneWidget);
    });
  });
}
