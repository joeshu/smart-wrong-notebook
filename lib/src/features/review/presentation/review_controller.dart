import 'package:uuid/uuid.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';

class ReviewController {
  ReviewController({
    required QuestionRepository repository,
    ReviewLogRepository? logRepository,
    ReviewScheduleService scheduleService = const ReviewScheduleService(),
  })  : _repository = repository,
        _logRepository = logRepository,
        _scheduleService = scheduleService;

  factory ReviewController.fake() => ReviewController(
        repository: InMemoryQuestionRepository(),
        logRepository: InMemoryReviewLogRepository(),
      );

  final QuestionRepository _repository;
  final ReviewLogRepository? _logRepository;
  final ReviewScheduleService _scheduleService;

  Future<QuestionRecord> markMastered(String id) =>
      _applyRating(id, ReviewRating.easy, 'mastered', forceMastered: true);

  Future<QuestionRecord> markReviewing(String id) =>
      _applyRating(id, ReviewRating.hard, 'reviewing');

  Future<QuestionRecord> markForgot(String id) =>
      _applyRating(id, ReviewRating.forgot, 'forgot');

  Future<QuestionRecord> _applyRating(
    String id,
    ReviewRating rating,
    String logResult, {
    bool forceMastered = false,
  }) async {
    final question = await _repository.getById(id);
    if (question == null) throw ArgumentError('Question not found: $id');

    final reviewedAt = DateTime.now();
    final updated = _scheduleService.apply(
      question,
      rating,
      reviewedAt: reviewedAt,
      forceMastered: forceMastered,
    );
    await _repository.update(updated);
    await _writeLog(id, logResult, updated.masteryLevel, reviewedAt);
    return updated;
  }

  Future<QuestionRecord> resetToNew(String id) async {
    final question = await _repository.getById(id);
    if (question == null) {
      throw ArgumentError('Question not found: $id');
    }
    final now = DateTime.now();
    final updated = _scheduleService.reset(question, now: now);
    await _repository.update(updated);
    await _writeLog(id, 'reset', MasteryLevel.newQuestion, now);
    return updated;
  }

  Future<List<QuestionRecord>> getDueQuestions({DateTime? now}) async {
    final all = await _repository.listAll();
    return all.where((q) => _scheduleService.isDue(q, now: now)).toList();
  }

  Future<void> _writeLog(
    String questionId,
    String result,
    MasteryLevel masteryAfter,
    DateTime reviewedAt,
  ) async {
    final repo = _logRepository;
    if (repo == null) return;
    final log = ReviewLog(
      id: const Uuid().v4(),
      questionRecordId: questionId,
      reviewedAt: reviewedAt,
      result: result,
      masteryAfter: masteryAfter,
    );
    await repo.insert(log);
  }
}
