import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

class AutoGradingService {
  AutoGradingService(this._aiService, this._questionRepo);

  final AiAnalysisService _aiService;
  final QuestionRepository _questionRepo;

  /// 对单题判分。返回是否正确。
  ///
  /// 需要 [QuestionRecord.studentAnswer] 与 [QuestionRecord.expectedAnswer] 都非空，
  /// 否则抛 [StateError]。判分结果会写入 [QuestionRecord.isCorrect] 并落库。
  Future<bool> gradeQuestion(QuestionRecord question) async {
    if (question.studentAnswer == null || question.studentAnswer!.isEmpty) {
      throw StateError('学生答案为空，无法判分');
    }
    if (question.expectedAnswer == null || question.expectedAnswer!.isEmpty) {
      throw StateError('标准答案为空，无法判分；请先填写标准答案');
    }
    final isCorrect = await _aiService.judgeAnswer(
      question: question.extractedQuestionText,
      userAnswer: question.studentAnswer!,
      correctAnswer: question.expectedAnswer!,
    );
    await _questionRepo.saveDraft(question.withIsCorrect(isCorrect));
    return isCorrect;
  }

  /// 批量判分。返回 (题目 id, 是否正确) 的 Map。
  ///
  /// 跳过 [QuestionRecord.studentAnswer] 或 [QuestionRecord.expectedAnswer]
  /// 为空的题目；单题判分失败不阻塞其他题。
  Future<Map<String, bool>> gradeBatch(List<QuestionRecord> questions) async {
    final results = <String, bool>{};
    for (final q in questions) {
      if (q.studentAnswer == null || q.studentAnswer!.isEmpty) continue;
      if (q.expectedAnswer == null || q.expectedAnswer!.isEmpty) continue;
      try {
        results[q.id] = await gradeQuestion(q);
      } catch (_) {
        // 单题判分失败不阻塞其他题
      }
    }
    return results;
  }
}
