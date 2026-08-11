import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart' hide GeneratedExercise, QuestionRecord;
import 'package:smart_wrong_notebook/src/data/repositories/drift_question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  late AppDatabase database;
  late DriftQuestionRepository repository;

  setUp(() {
    database = AppDatabase.memory();
    repository = DriftQuestionRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('preserves lineage metadata and saved exercises', () async {
    final now = DateTime(2026, 4, 28);
    final record = QuestionRecord(
      id: 'q-child-1',
      imagePath: '/tmp/q-child-1.jpg',
      subject: Subject.math,
      extractedQuestionText: '第一题',
      normalizedQuestionText: '第一题',
      contentFormat: QuestionContentFormat.latexMixed,
      tags: const <String>['manual'],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: DateTime(2026, 4, 29),
      reviewCount: 3,
      isFavorite: true,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.reviewing,
      analysisResult: null,
      savedExercises: <GeneratedExercise>[
        GeneratedExercise(
          id: 'exercise-1',
          questionId: 'stale-id',
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '简单',
          question: '1+1=?',
          options: const <String>['A. 1', 'B. 2'],
          answer: 'B',
          explanation: '基础加法',
          createdAt: now,
          order: 1,
          userAnswer: 'B',
          isCorrect: true,
        ),
      ],
      aiTags: const <String>['计算'],
      aiKnowledgePoints: const <String>['加法'],
      customTags: const <String>['课堂'],
      parentQuestionId: 'q-parent',
      rootQuestionId: 'q-root',
      splitOrder: 1,
    );

    await repository.saveDraft(record);

    final loaded = await repository.getById('q-child-1');

    expect(loaded, isNotNull);
    expect(loaded!.parentQuestionId, 'q-parent');
    expect(loaded.rootQuestionId, 'q-root');
    expect(loaded.splitOrder, 1);
    expect(loaded.savedExercises.single.questionId, 'q-child-1');
    expect(loaded.savedExercises.single.options, <String>['A. 1', 'B. 2']);
    expect(loaded.savedExercises.single.userAnswer, 'B');
    expect(loaded.savedExercises.single.isCorrect, isTrue);
    expect(loaded.aiTags, <String>['计算']);
    expect(loaded.aiKnowledgePoints, <String>['加法']);
    expect(loaded.customTags, <String>['课堂']);
    expect(loaded.isFavorite, isTrue);
    expect(loaded.lastReviewedAt, DateTime(2026, 4, 29));
  });

  test('preserves reflection note across save and reload', () async {
    final now = DateTime(2026, 7, 20);
    final record = QuestionRecord(
      id: 'q-reflection',
      imagePath: '/tmp/q-reflection.jpg',
      subject: Subject.math,
      extractedQuestionText: '反比例函数',
      normalizedQuestionText: '反比例函数',
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
      reflectionNote: '这道题考查反比例函数性质，易错点在符号判断。',
    );

    await repository.saveDraft(record);

    final loaded = await repository.getById('q-reflection');

    expect(loaded, isNotNull);
    expect(loaded!.reflectionNote,
        '这道题考查反比例函数性质，易错点在符号判断。');
  });

  test('persists null reflection note when not set', () async {
    final now = DateTime(2026, 7, 20);
    final record = QuestionRecord(
      id: 'q-no-reflection',
      imagePath: '/tmp/q-no-reflection.jpg',
      subject: Subject.math,
      extractedQuestionText: '一元二次方程',
      normalizedQuestionText: '一元二次方程',
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

    await repository.saveDraft(record);

    final loaded = await repository.getById('q-no-reflection');

    expect(loaded, isNotNull);
    expect(loaded!.reflectionNote, isNull);
  });

  test('preserves archivedAt across save and reload', () async {
    final now = DateTime(2026, 7, 20);
    final archivedAt = DateTime(2026, 6, 30, 10, 30);
    final record = QuestionRecord(
      id: 'q-archived',
      imagePath: '/tmp/q-archived.jpg',
      subject: Subject.math,
      extractedQuestionText: '上学期错题',
      normalizedQuestionText: '上学期错题',
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
      archivedAt: archivedAt,
    );

    await repository.saveDraft(record);

    final loaded = await repository.getById('q-archived');

    expect(loaded, isNotNull);
    expect(loaded!.archivedAt, archivedAt);
    expect(loaded.isArchived, isTrue);
  });

  test('preserves studentAnswer across save and reload', () async {
    final now = DateTime(2026, 7, 20);
    final record = QuestionRecord(
      id: 'q-student-answer',
      imagePath: '/tmp/q-student-answer.jpg',
      subject: Subject.math,
      extractedQuestionText: '解方程 \$x^2 - 1 = 0\$',
      normalizedQuestionText: '解方程 \$x^2 - 1 = 0\$',
      contentFormat: QuestionContentFormat.latexMixed,
      tags: const <String>[],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: null,
      studentAnswer:
          '由 \$x^2 - 1 = 0\$ 得 \$x^2 = 1\$，所以 \$x = \\pm 1\$。',
    );

    await repository.saveDraft(record);

    final loaded = await repository.getById('q-student-answer');

    expect(loaded, isNotNull);
    expect(loaded!.studentAnswer,
        '由 \$x^2 - 1 = 0\$ 得 \$x^2 = 1\$，所以 \$x = \\pm 1\$。');
  });

  test('persists needsConfirmation gate and pipeline snapshot', () async {
    final now = DateTime(2026, 7, 25);
    final record = QuestionRecord(
      id: 'q-needs-confirmation',
      imagePath: '/tmp/q-needs-confirmation.jpg',
      subject: Subject.math,
      extractedQuestionText: '解方程 x+1=4',
      normalizedQuestionText: '解方程 x+1=4',
      contentFormat: QuestionContentFormat.plain,
      tags: const <String>[],
      createdAt: now,
      updatedAt: now,
      lastReviewedAt: null,
      reviewCount: 0,
      isFavorite: false,
      contentStatus: ContentStatus.needsConfirmation,
      masteryLevel: MasteryLevel.newQuestion,
      analysisResult: const AnalysisResult(
        finalAnswer: '3',
        steps: <String>['移项得 x=3'],
        aiTags: <String>['方程'],
        knowledgePoints: <String>['一元一次方程'],
        mistakeReason: '',
        studyAdvice: '检查符号',
        reviewDecision: AiAnalysisReviewDecision(
          disposition: AiAnalysisReviewDisposition.needsConfirmation,
          fields: <String>['standardAnswer'],
          reasons: <String>['置信度低'],
        ),
        pipeline: AiAnalysisPipelineSnapshot(
          status: AiAnalysisPipelineStatus.waitingForConfirmation,
          currentStage: AiAnalysisPipelineStage.questionConfirmation,
          completedStages: <AiAnalysisPipelineStage>[
            AiAnalysisPipelineStage.solving,
          ],
        ),
      ),
    );

    await repository.saveDraft(record);
    final loaded = await repository.getById(record.id);

    expect(loaded?.contentStatus, ContentStatus.needsConfirmation);
    expect(loaded?.analysisResult?.reviewDecision.requiresConfirmation, isTrue);
    expect(
      loaded?.analysisResult?.pipeline.status,
      AiAnalysisPipelineStatus.waitingForConfirmation,
    );
  });

  test('persists null studentAnswer when not set', () async {
    final now = DateTime(2026, 7, 20);
    final record = QuestionRecord(
      id: 'q-no-student-answer',
      imagePath: '/tmp/q-no-student-answer.jpg',
      subject: Subject.math,
      extractedQuestionText: '一元二次方程',
      normalizedQuestionText: '一元二次方程',
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

    await repository.saveDraft(record);

    final loaded = await repository.getById('q-no-student-answer');

    expect(loaded, isNotNull);
    expect(loaded!.studentAnswer, isNull);
  });
}
