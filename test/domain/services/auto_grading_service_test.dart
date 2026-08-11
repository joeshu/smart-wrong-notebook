import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/auto_grading_service.dart';

/// 可控的 [AiAnalysisService] 测试替身：按构造时给定的 [result] 返回判分结论，
/// 或在 [throwException] 为 true 时模拟判分失败。
class _StubAiAnalysisService extends AiAnalysisService {
  _StubAiAnalysisService({
    this.result = false,
    this.throwException = false,
  }) : super(settingsRepository: InMemorySettingsRepository());

  final bool result;
  final bool throwException;

  @override
  Future<bool> judgeAnswer({
    required String question,
    required String userAnswer,
    required String correctAnswer,
    List<String>? options,
  }) async {
    if (throwException) {
      throw Exception('AI 判分异常');
    }
    return result;
  }
}

QuestionRecord _question({
  String id = 'q-1',
  String? studentAnswer,
  String? expectedAnswer,
  bool? isCorrect,
}) {
  final createdAt = DateTime(2026, 7, 17, 9);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '1 + 1 = ?',
    normalizedQuestionText: '1 + 1 = ?',
    contentFormat: QuestionContentFormat.plain,
    tags: const [],
    createdAt: createdAt,
    updatedAt: createdAt,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
    studentAnswer: studentAnswer,
    expectedAnswer: expectedAnswer,
    isCorrect: isCorrect,
  );
}

void main() {
  group('AutoGradingService.gradeQuestion', () {
    test('成功判分时将 isCorrect 写入仓库', () async {
      final repo = InMemoryQuestionRepository();
      final service = AutoGradingService(
        _StubAiAnalysisService(result: true),
        repo,
      );
      final question = _question(
        studentAnswer: '2',
        expectedAnswer: '2',
      );

      final isCorrect = await service.gradeQuestion(question);

      expect(isCorrect, isTrue);
      final saved = await repo.getById(question.id);
      expect(saved, isNotNull);
      expect(saved!.isCorrect, isTrue);
    });

    test('AI 判错时 isCorrect 写入 false', () async {
      final repo = InMemoryQuestionRepository();
      final service = AutoGradingService(
        _StubAiAnalysisService(result: false),
        repo,
      );
      final question = _question(
        studentAnswer: '3',
        expectedAnswer: '2',
      );

      final isCorrect = await service.gradeQuestion(question);

      expect(isCorrect, isFalse);
      final saved = await repo.getById(question.id);
      expect(saved, isNotNull);
      expect(saved!.isCorrect, isFalse);
    });

    test('缺 studentAnswer 时抛 StateError 且不落库', () async {
      final repo = InMemoryQuestionRepository();
      final service = AutoGradingService(
        _StubAiAnalysisService(result: true),
        repo,
      );
      final question = _question(
        studentAnswer: null,
        expectedAnswer: '2',
      );

      await expectLater(
        service.gradeQuestion(question),
        throwsA(isA<StateError>()),
      );
      expect(await repo.getById(question.id), isNull);
    });

    test('缺 expectedAnswer 时抛 StateError 且不落库', () async {
      final repo = InMemoryQuestionRepository();
      final service = AutoGradingService(
        _StubAiAnalysisService(result: true),
        repo,
      );
      final question = _question(
        studentAnswer: '2',
        expectedAnswer: null,
      );

      await expectLater(
        service.gradeQuestion(question),
        throwsA(isA<StateError>()),
      );
      expect(await repo.getById(question.id), isNull);
    });
  });

  group('AutoGradingService.gradeBatch', () {
    test('跳过 studentAnswer 或 expectedAnswer 为空的题目', () async {
      final repo = InMemoryQuestionRepository();
      final service = AutoGradingService(
        _StubAiAnalysisService(result: true),
        repo,
      );
      final questions = <QuestionRecord>[
        _question(id: 'q-1', studentAnswer: '2', expectedAnswer: '2'),
        _question(id: 'q-2', studentAnswer: null, expectedAnswer: '2'),
        _question(id: 'q-3', studentAnswer: '2', expectedAnswer: null),
        _question(id: 'q-4', studentAnswer: '', expectedAnswer: '2'),
        _question(id: 'q-5', studentAnswer: '2', expectedAnswer: ''),
      ];

      final results = await service.gradeBatch(questions);

      expect(results, hasLength(1));
      expect(results.keys, contains('q-1'));
      expect(results['q-1'], isTrue);
      // 跳过的题目不应被写入仓库
      expect(await repo.getById('q-2'), isNull);
      expect(await repo.getById('q-3'), isNull);
      expect(await repo.getById('q-4'), isNull);
      expect(await repo.getById('q-5'), isNull);
    });

    test('单题判分失败不阻塞其他题目', () async {
      final repo = InMemoryQuestionRepository();
      // 通过抛异常的 stub 模拟 AI 失败：所有题目都会进入 catch
      // 这里用两个 service 串接验证：让 q-1 抛错、q-2 成功
      final failingService = AutoGradingService(
        _StubAiAnalysisService(throwException: true),
        repo,
      );
      final okService = AutoGradingService(
        _StubAiAnalysisService(result: true),
        repo,
      );

      // q-1 抛异常 -> 应被 catch，结果 Map 不含 q-1
      final results1 = await failingService.gradeBatch([
        _question(id: 'q-1', studentAnswer: '2', expectedAnswer: '2'),
      ]);
      expect(results1, isEmpty);
      expect(await repo.getById('q-1'), isNull);

      // q-2 仍能继续判分（不阻塞）
      final results2 = await okService.gradeBatch([
        _question(id: 'q-2', studentAnswer: '2', expectedAnswer: '2'),
      ]);
      expect(results2, hasLength(1));
      expect(results2['q-2'], isTrue);
      final saved = await repo.getById('q-2');
      expect(saved, isNotNull);
      expect(saved!.isCorrect, isTrue);
    });
  });
}
