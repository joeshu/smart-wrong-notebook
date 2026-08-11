import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/notebook/application/knowledge_point_practice_controller.dart';

QuestionRecord _question(String id, List<GeneratedExercise> exercises) {
  final now = DateTime(2026, 7, 18);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目 $id',
    normalizedQuestionText: '题目 $id',
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
    savedExercises: exercises,
  );
}

GeneratedExercise _exercise(String id, String questionId) => GeneratedExercise(
      id: id,
      questionId: questionId,
      generationMode: ExerciseGenerationMode.practice,
      difficulty: '同级',
      question: '练习 $id',
      options: const <String>['A. 1', 'B. 2'],
      answer: 'B',
      explanation: '解析',
      createdAt: DateTime(2026, 7, 18),
      order: 0,
    );

void main() {
  test('builds a normalized cross-question round from existing exercises',
      () async {
    final controller = KnowledgePointPracticeController(AiAnalysisService.fake());
    final first = _question('q-1', <GeneratedExercise>[_exercise('e-1', 'q-1')]);
    final second = _question('q-2', <GeneratedExercise>[_exercise('e-2', 'q-2')]);

    final prepared = await controller.buildRound(
      knowledgePoint: '一次方程',
      questions: <QuestionRecord>[first, second],
    );

    expect(prepared.id, 'q-1');
    expect(prepared.savedExercises, hasLength(3));
    final round = prepared.savedExercises.where((e) => e.roundIndex == 2).toList();
    expect(round, hasLength(2));
    expect(round.every((e) => e.questionId == 'q-1'), isTrue);
    expect(round.every((e) => e.userAnswer == null), isTrue);
    expect(round.map((e) => e.sourceExerciseId),
        containsAll(<String>['e-1', 'e-2']));
  });

  test('automatically generates a first round when no existing exercise exists',
      () async {
    final controller = KnowledgePointPracticeController(AiAnalysisService.fake());
    final prepared = await controller.buildRound(
      knowledgePoint: '一次方程',
      questions: <QuestionRecord>[
        _question('q-empty', const <GeneratedExercise>[]),
      ],
    );

    expect(prepared.savedExercises, isNotEmpty);
    expect(prepared.savedExercises.every((e) => e.roundIndex == 1), isTrue);
    expect(prepared.savedExercises.every((e) => e.questionId == 'q-empty'), isTrue);
  });
}
