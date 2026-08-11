import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/question_split_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_result_screen.dart';

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.5,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _scrollUntilVisible(tester, finder);
  await tester.tap(finder, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _invokeButton(WidgetTester tester, Finder finder) async {
  await _scrollUntilVisible(tester, finder);
  final widget = tester.widget<Widget>(finder);
  if (widget is FilledButton && widget.onPressed != null) {
    widget.onPressed!();
  } else if (widget is TextButton && widget.onPressed != null) {
    widget.onPressed!();
  } else {
    throw StateError('Unsupported button widget: $widget');
  }
  await tester.pumpAndSettle();
}

Future<void> _selectChoiceChip(WidgetTester tester, Finder finder) async {
  await _scrollUntilVisible(tester, finder);
  final chip = tester.widget<ChoiceChip>(finder);
  chip.onSelected?.call(true);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('low-confidence result shows gate and disables practice',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-low-confidence',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '解方程 x+1=4',
    ).copyWith(
      analysisResult: AnalysisResult(
        finalAnswer: '3',
        steps: const <String>['移项得 x=3'],
        aiTags: const <String>['方程'],
        knowledgePoints: const <String>['一元一次方程'],
        mistakeReason: '',
        studyAdvice: '检查符号',
        confidence: const AiConfidence(
          overall: 0.65,
          fields: <String, double>{'standardAnswer': 0.55},
        ),
        reviewDecision: AiAnalysisReviewDecision(
          disposition: AiAnalysisReviewDisposition.needsConfirmation,
          fields: const <String>['standardAnswer'],
          reasons: const <String>['standardAnswer 置信度 55%'],
          evaluatedAt: DateTime.utc(2026, 7, 25),
        ),
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.byKey(
        const ValueKey<String>('analysis-review-required-banner'),
        skipOffstage: false,
      ),
    );
    expect(
      find.byKey(
        const ValueKey<String>('analysis-review-required-banner'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('整体可信度 65%', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('analysis-confirm-result-button'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.text('开始练习'), findsNothing);
  });

  testWidgets('confirming gated result promotes it to ready and persists it',
      (tester) async {
    final repository = InMemoryQuestionRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        questionRepositoryProvider.overrideWithValue(repository),
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-confirm-ui',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '解方程 x+1=4',
    ).copyWith(
      contentStatus: ContentStatus.needsConfirmation,
      analysisResult: AnalysisResult(
        finalAnswer: '3',
        steps: const <String>['移项得 x=3'],
        aiTags: const <String>['方程'],
        knowledgePoints: const <String>['一元一次方程'],
        mistakeReason: '',
        studyAdvice: '检查符号',
        reviewDecision: AiAnalysisReviewDecision(
          disposition: AiAnalysisReviewDisposition.needsConfirmation,
          fields: const <String>['standardAnswer'],
          reasons: const <String>['standardAnswer 置信度 55%'],
          evaluatedAt: DateTime.utc(2026, 7, 25),
        ),
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('我已核对，确认采用', skipOffstage: false),
    );
    await _invokeButton(
      tester,
      find.byKey(
        const ValueKey<String>('analysis-confirm-result-button'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();

    final current = container.read(currentQuestionProvider);
    expect(current?.contentStatus, ContentStatus.ready);
    expect(
      current?.analysisResult?.reviewDecision.disposition,
      AiAnalysisReviewDisposition.autoApproved,
    );
    expect(
      current?.analysisResult?.reviewDecision.confirmedFields,
      ['standardAnswer'],
    );
    final saved = await repository.getById('q-confirm-ui');
    expect(saved?.contentStatus, ContentStatus.ready);
  });

  testWidgets('editing a review field updates current result and keeps gate',
      (tester) async {
    final repository = InMemoryQuestionRepository();
    final container = ProviderContainer(
      overrides: <Override>[
        questionRepositoryProvider.overrideWithValue(repository),
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-edit-field',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '解方程 x+1=4',
    ).copyWith(
      contentStatus: ContentStatus.needsConfirmation,
      analysisResult: AnalysisResult(
        finalAnswer: '3',
        steps: const <String>['移项得 x=3'],
        aiTags: const <String>['方程'],
        knowledgePoints: const <String>['一元一次方程'],
        mistakeReason: '',
        studyAdvice: '检查符号',
        standardAnswer: '3',
        reviewDecision: AiAnalysisReviewDecision(
          disposition: AiAnalysisReviewDisposition.needsConfirmation,
          fields: const <String>['standardAnswer'],
          reasons: const <String>['standardAnswer 置信度 55%'],
          evaluatedAt: DateTime.utc(2026, 7, 25),
        ),
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.byKey(
        const ValueKey<String>('review-field-card-standardAnswer'),
        skipOffstage: false,
      ),
    );
    expect(
      find.byKey(
        const ValueKey<String>('review-field-card-standardAnswer'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    await _invokeButton(
      tester,
      find.byKey(
        const ValueKey<String>('review-field-edit-standardAnswer'),
        skipOffstage: false,
      ),
    );
    final editor = find.byKey(
      const ValueKey<String>('review-field-editor-standardAnswer'),
    );
    expect(editor, findsOneWidget);
    await tester.enterText(editor, '4');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    final current = container.read(currentQuestionProvider);
    expect(current?.contentStatus, ContentStatus.needsConfirmation);
    expect(current?.analysisResult?.standardAnswer, '4');
    expect(current?.analysisResult?.finalAnswer, '4');
    final saved = await repository.getById('q-edit-field');
    expect(saved?.analysisResult?.standardAnswer, '4');
  });

  testWidgets('analysis result screen shows repaired consistency notice',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-repaired',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '求阴影面积',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: r'25\pi/2',
        steps: <String>[r'阴影面积为 25\pi/2'],
        aiTags: <String>['几何'],
        knowledgePoints: <String>['圆面积'],
        mistakeReason: '漏乘二分之一',
        studyAdvice: '注意半圆面积',
        consistencyStatus: AnalysisConsistencyStatus.repaired,
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('AI 已复核并修正答案', skipOffstage: false),
    );
    expect(find.text('AI 已复核并修正答案', skipOffstage: false), findsOneWidget);
  });

  testWidgets('analysis result screen shows needs review consistency notice',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-review',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '应用题',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: 'C. 10',
        steps: <String>['解得 20，所以选 D。'],
        aiTags: <String>['应用题'],
        knowledgePoints: <String>['方程'],
        mistakeReason: '答案与步骤不一致',
        studyAdvice: '重新验算',
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('答案与步骤可能不一致，请核对', skipOffstage: false),
    );
    expect(
      find.text('答案与步骤可能不一致，请核对', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('analysis result screen shows visual assumption review state',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-visual-review',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '如图，求阴影面积',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: r'25\pi/2',
        steps: <String>[r'若 10 为直径，则面积为 25\pi/2。'],
        aiTags: <String>['几何'],
        knowledgePoints: <String>['半圆面积'],
        mistakeReason: '图中关键标注含义不确定',
        studyAdvice: '先核对图中标注',
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
        consistencyNote: '需核对 10 的标注含义',
        visualAssumptionStatus: VisualAssumptionStatus.needsReview,
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('可能解法', skipOffstage: false),
    );
    expect(find.text('可能解法', skipOffstage: false), findsOneWidget);
    expect(
      find.text('需核对 10 的标注含义', skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('analysis result screen builds with latex content',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-latex',
      imagePath: '',
      subject: Subject.math,
      recognizedText: r'已知 $x^2+1=5$，求 x 的值',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: r'$x=\pm2$',
        steps: <String>[r'$x^2=4$', r'$x=\pm2$'],
        aiTags: <String>['方程'],
        knowledgePoints: <String>['平方根'],
        mistakeReason: r'忽略了 $\pm$',
        studyAdvice: r'注意 $a^2=b$ 需要讨论正负两种情况',
      ),
      savedExercises: <GeneratedExercise>[
        GeneratedExercise(
          id: 'e-1',
          questionId: 'q-latex',
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: r'若 $y^2=9$，则 y 的值为？',
          answer: r'$y=\pm3$',
          explanation: r'因为 $y^2=9$，所以 $y=\pm3$',
          createdAt: DateTime(2026),
        ),
      ],
      splitResult: const QuestionSplitResult(
        sourceText: '1. 第一题\n2. 第二题',
        strategy: QuestionSplitStrategy.numbered,
        candidates: <QuestionSplitCandidate>[
          QuestionSplitCandidate(
            id: 'candidate-0',
            order: 1,
            text: '1. 第一题',
            strategy: QuestionSplitStrategy.numbered,
          ),
          QuestionSplitCandidate(
            id: 'candidate-1',
            order: 2,
            text: '2. 第二题',
            strategy: QuestionSplitStrategy.numbered,
          ),
        ],
      ),
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('AI 解析结果'), findsOneWidget);
    expect(find.byType(AnalysisResultScreen), findsOneWidget);
  });

  testWidgets(
      'analysis result screen does not reuse parent analysis for missing candidate snapshot',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-switch',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '整题文本',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: '第一题答案',
        steps: <String>['第一题步骤'],
        aiTags: <String>['一元二次'],
        knowledgePoints: <String>['平方根'],
        mistakeReason: '第一题错因',
        studyAdvice: '第一题建议',
      ),
      savedExercises: <GeneratedExercise>[
        GeneratedExercise(
          id: 'e-1',
          questionId: 'q-switch',
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: '第一题练习',
          answer: 'A',
          explanation: '第一题解释',
          createdAt: DateTime(2026),
        ),
      ],
      splitResult: const QuestionSplitResult(
        sourceText:
            '1. 第一题\n2. 若 \\(\\frac{a}{b}=2\\) 且 \\(a+b=9\\)，求 \\(a,b\\)。',
        strategy: QuestionSplitStrategy.numbered,
        candidates: <QuestionSplitCandidate>[
          QuestionSplitCandidate(
            id: 'candidate-0',
            order: 1,
            text: '1. 第一题',
            strategy: QuestionSplitStrategy.numbered,
          ),
          QuestionSplitCandidate(
            id: 'candidate-1',
            order: 2,
            text: '2. 若 \\(\\frac{a}{b}=2\\) 且 \\(a+b=9\\)，求 \\(a,b\\)。',
            strategy: QuestionSplitStrategy.numbered,
          ),
        ],
      ),
      candidateAnalyses: const <CandidateAnalysisSnapshot>[
        CandidateAnalysisSnapshot(
          candidateId: 'candidate-0',
          order: 1,
          questionText: '1. 第一题',
          analysisResult: AnalysisResult(
            finalAnswer: '第一题答案',
            steps: <String>['第一题步骤'],
            aiTags: <String>['一元二次'],
            knowledgePoints: <String>['平方根'],
            mistakeReason: '第一题错因',
            studyAdvice: '第一题建议',
          ),
          aiTags: <String>['一元二次'],
          aiKnowledgePoints: <String>['平方根'],
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('当前第 1 题', skipOffstage: false),
    );
    expect(
      find.text('当前第 1 题', skipOffstage: false),
      findsOneWidget,
    );
    await _selectChoiceChip(
      tester,
      find.byKey(
        const ValueKey<String>('candidate-chip-2'),
        skipOffstage: false,
      ),
    );

    await _scrollUntilVisible(
      tester,
      find.text('题号切换', skipOffstage: false),
    );
    expect(find.text('题号切换'), findsOneWidget);
    expect(find.text('当前第 2 题', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('解析失败', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第一题答案'), findsNothing);
    expect(find.textContaining('第一题步骤'), findsNothing);
    expect(find.text('第一题练习'), findsNothing);
  });

  testWidgets(
      'analysis result screen prefers independent candidate analysis content',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-candidate',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '整题文本',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: '整题答案',
        steps: <String>['整题步骤'],
        aiTags: <String>['整题标签'],
        knowledgePoints: <String>['整题知识点'],
        mistakeReason: '整题错因',
        studyAdvice: '整题建议',
      ),
      savedExercises: <GeneratedExercise>[
        GeneratedExercise(
          id: 'e-overall',
          questionId: 'q-candidate',
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: '整题练习',
          answer: 'A',
          explanation: '整题解释',
          createdAt: DateTime(2026),
        ),
      ],
      splitResult: const QuestionSplitResult(
        sourceText: '1. 第一题\n2. 第二题',
        strategy: QuestionSplitStrategy.numbered,
        candidates: <QuestionSplitCandidate>[
          QuestionSplitCandidate(
            id: 'candidate-0',
            order: 1,
            text: '1. 第一题',
            strategy: QuestionSplitStrategy.numbered,
          ),
          QuestionSplitCandidate(
            id: 'candidate-1',
            order: 2,
            text: '2. 第二题',
            strategy: QuestionSplitStrategy.numbered,
          ),
        ],
      ),
      candidateAnalyses: <CandidateAnalysisSnapshot>[
        CandidateAnalysisSnapshot(
          candidateId: 'candidate-0',
          order: 1,
          questionText: '1. 第一题',
          analysisResult: const AnalysisResult(
            finalAnswer: '第一题答案',
            steps: <String>['第一题步骤'],
            aiTags: <String>['一次函数'],
            knowledgePoints: <String>['第一题知识点'],
            mistakeReason: '第一题错因',
            studyAdvice: '第一题建议',
            subject: Subject.math,
          ),
          savedExercises: <GeneratedExercise>[
            GeneratedExercise(
              id: 'e-1',
              questionId: 'q-candidate-1',
              generationMode: ExerciseGenerationMode.practice,
              difficulty: '同级',
              question: '第一题练习',
              answer: 'A',
              explanation: '第一题解释',
              createdAt: DateTime(2026),
            ),
          ],
          aiTags: <String>['一次函数'],
          aiKnowledgePoints: <String>['第一题知识点'],
        ),
        CandidateAnalysisSnapshot(
          candidateId: 'candidate-1',
          order: 2,
          questionText: '2. 第二题',
          analysisResult: const AnalysisResult(
            finalAnswer: '第二题答案',
            steps: <String>['第二题步骤'],
            aiTags: <String>['受力分析'],
            knowledgePoints: <String>['第二题知识点'],
            mistakeReason: '第二题错因',
            studyAdvice: '第二题建议',
            subject: Subject.physics,
          ),
          savedExercises: <GeneratedExercise>[
            GeneratedExercise(
              id: 'e-2',
              questionId: 'q-candidate-2',
              generationMode: ExerciseGenerationMode.practice,
              difficulty: '提高',
              question: '第二题练习',
              answer: 'B',
              explanation: '第二题解释',
              createdAt: DateTime(2026),
            ),
          ],
          aiTags: <String>['受力分析'],
          aiKnowledgePoints: <String>['第二题知识点'],
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnalysisResultScreen()),
    ));
    await tester.pumpAndSettle();

    await _scrollUntilVisible(
      tester,
      find.text('当前第 1 题', skipOffstage: false),
    );
    expect(find.text('当前第 1 题', skipOffstage: false), findsOneWidget);
    expect(find.text('错误定位', skipOffstage: false), findsOneWidget);

    await _selectChoiceChip(
      tester,
      find.byKey(
        const ValueKey<String>('candidate-chip-2'),
        skipOffstage: false,
      ),
    );
    expect(find.text('当前第 2 题', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('解析失败', skipOffstage: false), findsNothing);
    expect(find.text('错误定位', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第二题答案', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('第一题答案', skipOffstage: false), findsNothing);
  });

  testWidgets('analysis result screen isolates six-question sample analyses',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-six-sample',
      imagePath: '',
      subject: Subject.math,
      recognizedText: '六题样例',
    ).copyWith(
      normalizedQuestionText: '六题样例',
      analysisResult: const AnalysisResult(
        finalAnswer: '第一题答案',
        steps: <String>['第一题步骤'],
        aiTags: <String>['方程求解'],
        knowledgePoints: <String>['平方根'],
        mistakeReason: '第一题错因',
        studyAdvice: '第一题建议',
      ),
      savedExercises: const <GeneratedExercise>[],
      splitResult: const QuestionSplitResult(
        sourceText:
            '1. 已知 x^2 + 1 = 5，求 x 的值。\n2. 若 a/b = 2 且 a+b=9，求 a,b。\n3. 函数 f(x)=x^2-2x+1 在 x=3 时的值是？\n4. 解方程组：\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}\n5. 圆锥体积 V=1/3πr^2h，当 r=3,h=4 时求 V。\n6. 在 \\triangle ABC 中，若 AB=AC，且 \\angle A=40\\circ，求 \\angle B。',
        strategy: QuestionSplitStrategy.numbered,
        candidates: <QuestionSplitCandidate>[
          QuestionSplitCandidate(
              id: 'candidate-0',
              order: 1,
              text: '1. 已知 x^2 + 1 = 5，求 x 的值。',
              strategy: QuestionSplitStrategy.numbered),
          QuestionSplitCandidate(
              id: 'candidate-1',
              order: 2,
              text: '2. 若 a/b = 2 且 a+b=9，求 a,b。',
              strategy: QuestionSplitStrategy.numbered),
          QuestionSplitCandidate(
              id: 'candidate-2',
              order: 3,
              text: '3. 函数 f(x)=x^2-2x+1 在 x=3 时的值是？',
              strategy: QuestionSplitStrategy.numbered),
          QuestionSplitCandidate(
              id: 'candidate-3',
              order: 4,
              text: '4. 解方程组：\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}',
              strategy: QuestionSplitStrategy.numbered),
          QuestionSplitCandidate(
              id: 'candidate-4',
              order: 5,
              text: '5. 圆锥体积 V=1/3πr^2h，当 r=3,h=4 时求 V。',
              strategy: QuestionSplitStrategy.numbered),
          QuestionSplitCandidate(
              id: 'candidate-5',
              order: 6,
              text:
                  '6. 在 \\triangle ABC 中，若 AB=AC，且 \\angle A=40\\circ，求 \\angle B。',
              strategy: QuestionSplitStrategy.numbered),
        ],
      ),
      candidateAnalyses: <CandidateAnalysisSnapshot>[
        const CandidateAnalysisSnapshot(
          candidateId: 'candidate-0',
          order: 1,
          questionText: '1. 已知 x^2 + 1 = 5，求 x 的值。',
          analysisResult: AnalysisResult(
            finalAnswer: 'x = 2 或 x = -2',
            steps: <String>['由 x^2+1=5 得 x^2=4，所以 x=±2。'],
            aiTags: <String>['一元二次'],
            knowledgePoints: <String>['平方根'],
            mistakeReason: '容易漏掉负根',
            studyAdvice: '注意平方根有正负两个值',
            subject: Subject.math,
          ),
          aiTags: <String>['一元二次'],
          aiKnowledgePoints: <String>['平方根'],
        ),
        const CandidateAnalysisSnapshot(
          candidateId: 'candidate-3',
          order: 4,
          questionText: '4. 解方程组：\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}',
          analysisResult: AnalysisResult(
            finalAnswer: 'x = 3，y = 2',
            steps: <String>['两式相加得 2x=6，所以 x=3；代入得 y=2。'],
            aiTags: <String>['方程组'],
            knowledgePoints: <String>['消元法'],
            mistakeReason: '容易代入错误',
            studyAdvice: '先消元再代入检验',
            subject: Subject.math,
          ),
          aiTags: <String>['方程组'],
          aiKnowledgePoints: <String>['消元法'],
        ),
        const CandidateAnalysisSnapshot(
          candidateId: 'candidate-5',
          order: 6,
          questionText:
              '6. 在 \\triangle ABC 中，若 AB=AC，且 \\angle A=40\\circ，求 \\angle B。',
          analysisResult: AnalysisResult(
            finalAnswer: r'\angle B = 70\circ',
            steps: <String>[
              r'AB=AC，所以 \angle B=\angle C；又 \angle A=40\circ，所以 \angle B=70\circ。'
            ],
            aiTags: <String>['等腰三角形'],
            knowledgePoints: <String>['三角形内角和'],
            mistakeReason: '容易混淆顶角和底角',
            studyAdvice: '先找等边对应的等角',
            subject: Subject.math,
          ),
          aiTags: <String>['等腰三角形'],
          aiKnowledgePoints: <String>['三角形内角和'],
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 1400,
            child: AnalysisResultScreen(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Parser Error'), findsNothing);
    expect(find.textContaining('begincases'), findsNothing);
    expect(find.textContaining('tri'), findsNothing);
    expect(find.textContaining('x = 3，y = 2'), findsNothing);

    await _scrollUntilVisible(
      tester,
      find.text('题号切换', skipOffstage: false),
    );
    await _selectChoiceChip(
      tester,
      find.byKey(
        const ValueKey<String>('candidate-chip-4'),
        skipOffstage: false,
      ),
    );
    expect(find.textContaining('Parser Error'), findsNothing);
    expect(find.textContaining('begincases'), findsNothing);
    expect(find.text('当前第 4 题', skipOffstage: false), findsOneWidget);
    expect(find.text('错误定位', skipOffstage: false), findsOneWidget);

    await _selectChoiceChip(
      tester,
      find.byKey(
        const ValueKey<String>('candidate-chip-6'),
        skipOffstage: false,
      ),
    );
    expect(find.textContaining('Parser Error'), findsNothing);
    expect(find.textContaining('tri'), findsNothing);
    expect(find.text('当前第 6 题', skipOffstage: false), findsOneWidget);
    expect(find.text('错误定位', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('x = 3，y = 2'), findsNothing);
  });

  testWidgets(
      'analysis result screen navigates to split confirmation when saving',
      (tester) async {
    final container = ProviderContainer(
      overrides: <Override>[
        questionSplitServiceProvider
            .overrideWithValue(const QuestionSplitService()),
      ],
    );
    addTearDown(container.dispose);

    container.read(currentQuestionProvider.notifier).state =
        QuestionRecord.draft(
      id: 'q-save',
      imagePath: '',
      subject: Subject.math,
      recognizedText: r'已知 $x^2+1=5$，求 x 的值',
    ).copyWith(
      analysisResult: const AnalysisResult(
        finalAnswer: r'$x=\pm2$',
        steps: <String>[r'$x^2=4$'],
        aiTags: <String>['方程'],
        knowledgePoints: <String>['平方根'],
        mistakeReason: r'忽略了 $\pm$',
        studyAdvice: r'注意分类讨论',
      ),
      savedExercises: <GeneratedExercise>[
        GeneratedExercise(
          id: 'e-save',
          questionId: 'q-save',
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: r'若 $y^2=9$，则 y 的值为？',
          answer: r'$y=\pm3$',
          explanation: r'因为 $y^2=9$，所以 $y=\pm3$',
          createdAt: DateTime(2026),
        ),
      ],
    );

    final router = GoRouter(
      initialLocation: '/analysis/result',
      routes: <GoRoute>[
        GoRoute(
          path: '/analysis/result',
          builder: (_, __) => const AnalysisResultScreen(),
        ),
        GoRoute(
          path: '/capture/split-confirmation',
          builder: (_, __) => const Scaffold(body: Text('SPLIT_CONFIRMATION')),
        ),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    await _scrollUntilVisible(
      tester,
      find.text('保存到错题本', skipOffstage: false),
    );
    expect(find.text('保存到错题本'), findsOneWidget);
    await _tapVisible(
      tester,
      find.text('保存到错题本', skipOffstage: false),
    );

    expect(find.text('SPLIT_CONFIRMATION'), findsOneWidget);
    expect(container.read(currentQuestionSplitSessionProvider), isNotNull);
  });
}
