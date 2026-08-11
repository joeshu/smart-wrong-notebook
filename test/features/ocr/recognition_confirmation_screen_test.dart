import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/recognition_confirmation_screen.dart';

class _FailOnceRepository extends InMemoryQuestionRepository {
  int saveAttempts = 0;
  bool failNext = true;

  @override
  Future<void> saveDraft(QuestionRecord record) async {
    saveAttempts++;
    if (failNext) {
      failNext = false;
      throw StateError('temporary save failure');
    }
    await super.saveDraft(record);
  }
}

class _BlockingRepository extends InMemoryQuestionRepository {
  final Completer<void> release = Completer<void>();
  int saveAttempts = 0;

  @override
  Future<void> saveDraft(QuestionRecord record) async {
    saveAttempts++;
    await release.future;
    await super.saveDraft(record);
  }
}

class _ExtractionService extends TestAiAnalysisService {
  _ExtractionService(AiQuestionExtractionResult extraction)
      : super(
          settingsRepository: InMemorySettingsRepository(),
          extractionResult: extraction,
          analysisResultValue: const AnalysisResult(
            subject: Subject.math,
            finalAnswer: 'x=1',
            steps: <String>[],
            aiTags: <String>[],
            knowledgePoints: <String>[],
            mistakeReason: '',
            studyAdvice: '',
          ),
        );
}

void main() {
  Future<void> selectCompactSegment(WidgetTester tester, bool showImage) async {
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    segmented.onSelectionChanged?.call(<bool>{showImage});
    await tester.pumpAndSettle();
  }

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pumpWorkbench(
    WidgetTester tester, {
    required Size size,
    required ThemeMode themeMode,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state = QuestionRecord.draft(
      id: 'phase2-review',
      imagePath: '/tmp/missing-phase2-image.jpg',
      subject: Subject.math,
      recognizedText: '求 x 的值\nA. 1\nB. 2',
    ).copyWith(
      extractedQuestionText: 'OCR: 求x值 A1 B2',
      normalizedQuestionText: '求 x 的值\nA. 1\nB. 2',
      ocrConfidence: .55,
      studentAnswer: 'B',
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.light(useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: themeMode,
        home: const RecognitionConfirmationScreen(),
      ),
    ));
    await tester.pump();
  }

  QuestionRecord reviewRecord() => QuestionRecord.draft(
        id: 'phase6-review',
        imagePath: File('assets/icon/app_icon.png').absolute.path,
        subject: Subject.math,
        recognizedText: '旧题干\nA. 旧选项\nB. 另一选项',
      ).copyWith(
        extractedQuestionText: '旧 OCR',
        normalizedQuestionText: '旧题干\nA. 旧选项\nB. 另一选项',
        ocrConfidence: .45,
        studentAnswer: 'B',
      );

  Future<void> pumpWithRouter(
    WidgetTester tester, {
    required QuestionRepository repository,
    required AiAnalysisService service,
    required GoRouter router,
  }) async {
    final container = ProviderContainer(overrides: <Override>[
      questionRepositoryProvider.overrideWithValue(repository),
      aiAnalysisServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state = reviewRecord();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
  }

  GoRouter workbenchRouter() => GoRouter(
        initialLocation: '/capture/recognition-confirmation',
        routes: <GoRoute>[
          GoRoute(
            path: '/capture/recognition-confirmation',
            builder: (_, __) => const RecognitionConfirmationScreen(),
          ),
          GoRoute(
            path: '/capture/correction',
            builder: (_, __) => const Scaffold(body: Text('CORRECTION')),
          ),
          GoRoute(
            path: '/notebook',
            builder: (_, __) => const Scaffold(body: Text('NOTEBOOK')),
          ),
          GoRoute(
            path: '/analysis/loading',
            builder: (_, __) => const Scaffold(body: Text('ANALYSIS')),
          ),
        ],
      );

  Future<void> showReviewPane(WidgetTester tester) async {
    final segmented = find.byType(SegmentedButton<bool>);
    if (segmented.evaluate().isNotEmpty) {
      await tester.tap(find.text('识别文字'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> scrollReviewTo(
    WidgetTester tester,
    Finder target,
  ) async {
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pump();
  }

  Future<void> confirmRequiredFields(WidgetTester tester) async {
    await showReviewPane(tester);
    for (final label in <String>['确认题干', '确认选项', '确认学生答案']) {
      final target = find.text(label);
      await scrollReviewTo(tester, target);
      await tester.tap(target);
      await tester.pump();
    }
  }

  Future<void> revealReviewActions(WidgetTester tester) async {
    await showReviewPane(tester);
    await scrollReviewTo(tester, find.text('重新识别整题'));
  }

  FilterChip confirmationChip(WidgetTester tester, String label) =>
      tester.widget<FilterChip>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(FilterChip),
        ),
      );

  testWidgets('320px compact layout switches between image and review', (tester) async {
    await pumpWorkbench(tester, size: const Size(320, 700), themeMode: ThemeMode.light);
    expect(find.text('原图附件缺失，请手动录入或放弃此草稿'), findsOneWidget);
    await selectCompactSegment(tester, false);
    expect(find.text('识别来源对照'), findsOneWidget);
    expect(find.text('为什么需要确认'), findsOneWidget);
    expect(find.textContaining('题干置信度较低'), findsOneWidget);
    expect(find.textContaining('原图附件不可用'), findsOneWidget);
    expect(find.text('OCR 原文'), findsNothing);
    await tester.tap(find.text('识别来源对照'));
    await tester.pumpAndSettle();
    expect(find.text('OCR 原文'), findsOneWidget);
    expect(find.text('AI 规范化文本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet dark layout shows image and layered text side by side', (tester) async {
    await pumpWorkbench(tester, size: const Size(1024, 900), themeMode: ThemeMode.dark);
    expect(find.text('原图附件缺失，请手动录入或放弃此草稿'), findsOneWidget);
    expect(find.text('识别来源对照'), findsOneWidget);
    expect(find.text('OCR 原文'), findsNothing);
    await tester.tap(find.text('识别来源对照'));
    await tester.pumpAndSettle();
    expect(find.text('OCR 原文'), findsOneWidget);
    expect(find.text('AI 规范化文本'), findsOneWidget);
    expect(find.textContaining('确认低置信度'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm is single-flight and navigates once after save completes', (tester) async {
    final repository = _BlockingRepository();
    await pumpWithRouter(
      tester,
      repository: repository,
      service: _ExtractionService(const AiQuestionExtractionResult(
        extractedQuestionText: 'unused',
        normalizedQuestionText: 'unused',
      )),
      router: workbenchRouter(),
    );
    await confirmRequiredFields(tester);

    final confirm = find.text('确认文字并开始分析');
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(repository.saveAttempts, 1);

    repository.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('ANALYSIS'), findsOneWidget);
    expect(repository.saveAttempts, 1);
  });

  testWidgets('draft save failure unlocks the action for retry', (tester) async {
    final repository = _FailOnceRepository();
    await pumpWithRouter(
      tester,
      repository: repository,
      service: _ExtractionService(const AiQuestionExtractionResult(
        extractedQuestionText: 'unused',
        normalizedQuestionText: 'unused',
      )),
      router: workbenchRouter(),
    );

    await showReviewPane(tester);
    final draft = find.text('保留草稿');
    await tester.tap(draft);
    await tester.pumpAndSettle();
    await revealReviewActions(tester);
    final error = find.textContaining('保留草稿失败');
    await scrollReviewTo(tester, error);
    expect(error, findsOneWidget);
    expect(repository.saveAttempts, 1);

    await tester.tap(draft);
    await tester.pumpAndSettle();
    expect(find.text('NOTEBOOK'), findsOneWidget);
    expect(repository.saveAttempts, 2);
  });

  testWidgets('draft save is single-flight while persistence is pending', (tester) async {
    final repository = _BlockingRepository();
    await pumpWithRouter(
      tester,
      repository: repository,
      service: _ExtractionService(const AiQuestionExtractionResult(
        extractedQuestionText: 'unused',
        normalizedQuestionText: 'unused',
      )),
      router: workbenchRouter(),
    );

    await showReviewPane(tester);
    final draft = find.text('保留草稿');
    await tester.tap(draft);
    await tester.tap(draft);
    await tester.pump();
    expect(repository.saveAttempts, 1);

    repository.release.complete();
    await tester.pumpAndSettle();
    expect(find.text('NOTEBOOK'), findsOneWidget);
    expect(repository.saveAttempts, 1);
  });

  testWidgets('whole-question retry updates OCR data and clears prior confirmations', (tester) async {
    final repository = InMemoryQuestionRepository();
    await pumpWithRouter(
      tester,
      repository: repository,
      service: _ExtractionService(const AiQuestionExtractionResult(
        extractedQuestionText: '新的 OCR',
        normalizedQuestionText: '新题干\nA. 新选项\nB. 另一新选项',
        studentAnswer: 'A',
        ocrConfidence: .40,
      )),
      router: workbenchRouter(),
    );
    await confirmRequiredFields(tester);
    await revealReviewActions(tester);

    await tester.tap(find.text('重新识别整题'));
    await tester.pumpAndSettle();

    for (final label in <String>['确认题干', '确认选项', '确认学生答案']) {
      expect(confirmationChip(tester, label).selected, isFalse);
    }
    final saved = await repository.getById('phase6-review');
    expect(saved?.extractedQuestionText, '新的 OCR');
    expect(saved?.normalizedQuestionText, '新题干\nA. 新选项\nB. 另一新选项');
    expect(saved?.studentAnswer, 'A');
    expect(saved?.ocrConfidence, .40);
  });

  testWidgets('stem-only retry preserves unrelated fields and confirmations', (tester) async {
    final repository = InMemoryQuestionRepository();
    await pumpWithRouter(
      tester,
      repository: repository,
      service: _ExtractionService(const AiQuestionExtractionResult(
        extractedQuestionText: '不应覆盖 OCR',
        normalizedQuestionText: '新题干\nA. 不应覆盖选项',
        studentAnswer: '不应覆盖答案',
        ocrConfidence: .95,
      )),
      router: workbenchRouter(),
    );
    await confirmRequiredFields(tester);
    await revealReviewActions(tester);

    await tester.tap(find.text('只重识别题干'));
    await tester.pumpAndSettle();

    expect(confirmationChip(tester, '确认题干').selected, isFalse);
    expect(confirmationChip(tester, '确认选项').selected, isTrue);
    expect(confirmationChip(tester, '确认学生答案').selected, isTrue);
    final saved = await repository.getById('phase6-review');
    expect(saved?.extractedQuestionText, '旧 OCR');
    expect(saved?.normalizedQuestionText, '新题干\nA. 旧选项\nB. 另一选项');
    expect(saved?.studentAnswer, 'B');
    expect(saved?.ocrConfidence, .45);
  });

  testWidgets('cancel returns to correction without saving', (tester) async {
    final repository = InMemoryQuestionRepository();
    await pumpWithRouter(
      tester,
      repository: repository,
      service: _ExtractionService(const AiQuestionExtractionResult(
        extractedQuestionText: 'unused',
        normalizedQuestionText: 'unused',
      )),
      router: workbenchRouter(),
    );

    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    expect(find.text('CORRECTION'), findsOneWidget);
    expect(await repository.getById('phase6-review'), isNull);
  });
}
