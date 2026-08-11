import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// Builds one practice round from all questions sharing a knowledge point.
/// The round is stored on a representative source question so the existing
/// practice screen can persist answers without introducing a second session DB.
class KnowledgePointPracticeController {
  KnowledgePointPracticeController(this._aiService);

  final AiAnalysisService _aiService;

  Future<QuestionRecord> buildRound({
    required String knowledgePoint,
    required List<QuestionRecord> questions,
  }) async {
    if (questions.isEmpty) throw ArgumentError('No questions for knowledge point');
    final representative = questions.first;
    var seeds = _collectExistingExercises(questions);

    if (seeds.isEmpty) {
      final prompt = _generationPrompt(knowledgePoint, questions);
      final analysis = await _aiService.analyzeQuestion(
        correctedText: prompt,
        subjectName: representative.subject.name,
      );
      seeds = _aiService.extractGeneratedExercises(
        analysis,
        questionId: representative.id,
        sourceQuestionText: prompt,
      );
    }
    if (seeds.isEmpty) throw StateError('AI did not return practice exercises');

    final nextRound = _nextRound(representative.savedExercises);
    final groupId = '${representative.id}-knowledge-$nextRound';
    final normalized = seeds.asMap().entries.map((entry) {
      final seed = entry.value;
      return seed.copyWith(
        id: '$groupId-exercise-${entry.key + 1}',
        questionId: representative.id,
        order: entry.key,
        isCorrect: null,
        userAnswer: null,
        roundIndex: nextRound,
        roundTotal: seeds.length,
        roundGroupId: groupId,
        sourceExerciseId: seed.sourceExerciseId ?? seed.id,
      );
    }).toList();

    return representative.copyWith(
      savedExercises: <GeneratedExercise>[
        ...representative.savedExercises,
        ...normalized,
      ],
    );
  }

  List<GeneratedExercise> _collectExistingExercises(
      List<QuestionRecord> questions) {
    final seeds = <GeneratedExercise>[];
    for (final question in questions) {
      final exercises = question.savedExercises;
      if (exercises.isEmpty) continue;
      final latestRound = exercises
          .map((exercise) => exercise.roundIndex ?? 1)
          .reduce((a, b) => a > b ? a : b);
      seeds.addAll(exercises
          .where((exercise) => (exercise.roundIndex ?? 1) == latestRound)
          .take(3));
    }
    return seeds;
  }

  int _nextRound(List<GeneratedExercise> exercises) {
    if (exercises.isEmpty) return 1;
    final highest = exercises
        .map((exercise) => exercise.roundIndex ?? 1)
        .reduce((a, b) => a > b ? a : b);
    return highest + 1;
  }

  String _generationPrompt(
    String knowledgePoint,
    List<QuestionRecord> questions,
  ) {
    final samples = questions
        .take(3)
        .map((question) => question.normalizedQuestionText)
        .join('\n---\n');
    return '为知识点“$knowledgePoint”生成 3 道由易到难的选择练习题。'
        '题目应围绕同一核心方法，提供 A/B/C/D 选项、答案和解析。'
        '以下是学生的关联错题，仅供确定范围：\n$samples';
  }
}
