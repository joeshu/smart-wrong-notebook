import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';

QuestionRecord _question({
  DateTime? nextReviewAt,
  ContentStatus status = ContentStatus.ready,
  List<String> tags = const [],
  MasteryLevel mastery = MasteryLevel.newQuestion,
  int reviewCount = 0,
}) {
  final createdAt = DateTime(2026, 7, 17, 9);
  return QuestionRecord(
    id: 'q-1',
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: 'x',
    normalizedQuestionText: 'x',
    contentFormat: QuestionContentFormat.plain,
    tags: tags,
    createdAt: createdAt,
    updatedAt: createdAt,
    lastReviewedAt: null,
    nextReviewAt: nextReviewAt,
    reviewCount: reviewCount,
    isFavorite: false,
    contentStatus: status,
    masteryLevel: mastery,
    analysisResult: null,
  );
}

void main() {
  const service = ReviewScheduleService();
  final now = DateTime(2026, 7, 17, 10);

  // --- isDue 行为（保留 legacy 兼容性）---

  test('legacy question without a schedule is immediately due', () {
    expect(service.isDue(_question(), now: now), isTrue);
  });

  test('legacy mastered question without a schedule stays out of queue', () {
    final question =
        _question(mastery: MasteryLevel.mastered);
    expect(service.isDue(question, now: now), isFalse);
  });

  test('legacy JSON keeps mastered questions unscheduled', () {
    final legacy = _question(mastery: MasteryLevel.mastered).toJson()
      ..remove('nextReviewAt');
    final restored = QuestionRecord.fromJson(legacy);
    expect(restored.nextReviewAt, isNull);
    expect(service.isDue(restored, now: now), isFalse);
  });

  test('future and unfinished questions are excluded from due queue', () {
    expect(
      service.isDue(
          _question(nextReviewAt: now.add(const Duration(minutes: 1))),
          now: now),
      isFalse,
    );
    expect(
      service.isDue(_question(status: ContentStatus.processing), now: now),
      isFalse,
    );
    expect(
      service.isDue(
        _question(status: ContentStatus.needsConfirmation),
        now: now,
      ),
      isFalse,
    );
  });

  // --- FSRS-4.5 行为 ---

  test('first forgot review → Learning 态，10 分钟后重学', () {
    final updated = service.apply(_question(), ReviewRating.forgot, reviewedAt: now);
    expect(updated.masteryLevel, MasteryLevel.reviewing);
    expect(updated.reviewCount, 1);
    expect(updated.lastReviewedAt, now);
    // FSRS Again 在 Learning 阶段 = 10 分钟（非旧实现的 1 小时）。
    expect(updated.nextReviewAt, now.add(const Duration(minutes: 10)));

    // tags 应包含 FSRS 状态。
    final state = LearningContextCodec.fsrsState(updated.tags);
    expect(state, FsrsState.learning);
    final lapses = LearningContextCodec.fsrsLapses(updated.tags);
    expect(lapses, 1);
    final reps = LearningContextCodec.fsrsReps(updated.tags);
    expect(reps, 1);
  });

  test('first hard review → Learning 态，1 天后复习', () {
    final updated = service.apply(_question(), ReviewRating.hard, reviewedAt: now);
    expect(updated.masteryLevel, MasteryLevel.reviewing);
    expect(updated.nextReviewAt, now.add(const Duration(days: 1)));
    expect(LearningContextCodec.fsrsState(updated.tags), FsrsState.learning);
  });

  test('first easy review → Review 态，间隔 = initial stability 2.4 天', () {
    final updated = service.apply(_question(), ReviewRating.easy, reviewedAt: now);
    // easy(Good) 初始 stability = 2.4，毕业到 Review，间隔 = round(2.4×1.0) = 2 天。
    expect(updated.nextReviewAt, now.add(const Duration(days: 2)));
    expect(LearningContextCodec.fsrsState(updated.tags), FsrsState.review);
    // stability < 21 天 → reviewing（非 mastered）。
    expect(updated.masteryLevel, MasteryLevel.reviewing);
  });

  test('consecutive easy reviews increase stability progressively', () {
    var question = _question();
    // 第 1 次 easy：毕业到 Review，S=2.4，间隔 2 天。
    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    final s1 = LearningContextCodec.fsrsStability(question.tags)!;
    expect(s1, closeTo(2.4, 0.01));

    // 第 2 次 easy：S 应增长（growth 公式 0.4 + 0.4×df，df=(10-D)/10）。
    question = service.apply(question, ReviewRating.easy,
        reviewedAt: now.add(const Duration(days: 2)));
    final s2 = LearningContextCodec.fsrsStability(question.tags)!;
    expect(s2, greaterThan(s1));

    // 第 3 次 easy：S 继续增长。
    question = service.apply(question, ReviewRating.easy,
        reviewedAt: now.add(const Duration(days: 30)));
    final s3 = LearningContextCodec.fsrsStability(question.tags)!;
    expect(s3, greaterThan(s2));
  });

  test('forgot in Review state → Relearning 态，stability 大幅衰减', () {
    // 先 easy 两次进入 Review 态并积累 stability。
    var question = _question();
    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    final sBefore = LearningContextCodec.fsrsStability(question.tags)!;
    question = service.apply(question, ReviewRating.easy,
        reviewedAt: now.add(const Duration(days: 2)));
    final sStable = LearningContextCodec.fsrsStability(question.tags)!;
    expect(sStable, greaterThan(sBefore));
    expect(LearningContextCodec.fsrsState(question.tags), FsrsState.review);

    // 再 forgot：进入 Relearning，stability 衰减到 0.4×oldS。
    question = service.apply(question, ReviewRating.forgot,
        reviewedAt: now.add(const Duration(days: 10)));
    final sAfter = LearningContextCodec.fsrsStability(question.tags)!;
    expect(LearningContextCodec.fsrsState(question.tags), FsrsState.relearning);
    expect(sAfter, lessThan(sStable));
    expect(sAfter, closeTo(sStable * 0.4, 0.5));
    expect(LearningContextCodec.fsrsLapses(question.tags), 1);
  });

  test('high difficulty reduces stability growth rate', () {
    // 构造两道题，一道难度 1.0（简单），一道难度 10.0（最难）。
    final easyTags = LearningContextCodec.writeFsrs(
      tags: const [],
      stability: 5.0,
      difficulty: 1.0,
      state: FsrsState.review,
      reps: 3,
      lapses: 0,
      lastReview: now.subtract(const Duration(days: 5)),
    );
    final hardTags = LearningContextCodec.writeFsrs(
      tags: const [],
      stability: 5.0,
      difficulty: 10.0,
      state: FsrsState.review,
      reps: 3,
      lapses: 0,
      lastReview: now.subtract(const Duration(days: 5)),
    );
    final easyQ = _question(tags: easyTags, mastery: MasteryLevel.reviewing);
    final hardQ = _question(tags: hardTags, mastery: MasteryLevel.reviewing);

    final easyUpdated = service.apply(easyQ, ReviewRating.easy, reviewedAt: now);
    final hardUpdated = service.apply(hardQ, ReviewRating.easy, reviewedAt: now);

    final easyS = LearningContextCodec.fsrsStability(easyUpdated.tags)!;
    final hardS = LearningContextCodec.fsrsStability(hardUpdated.tags)!;
    // 难度低（D=1.0）的题 stability 增长应高于难度高（D=10.0）的题。
    expect(easyS, greaterThan(hardS));
  });

  test('stability > 21 天时映射为 mastered', () {
    // 构造 stability = 30 天的 Review 态题目。
    final tags = LearningContextCodec.writeFsrs(
      tags: const [],
      stability: 30.0,
      difficulty: 5.0,
      state: FsrsState.review,
      reps: 5,
      lapses: 0,
      lastReview: now.subtract(const Duration(days: 30)),
    );
    final question = _question(tags: tags, mastery: MasteryLevel.reviewing);
    final updated = service.apply(question, ReviewRating.easy, reviewedAt: now);
    expect(updated.masteryLevel, MasteryLevel.mastered);
  });

  test('reset clears FSRS state but keeps reviewCount', () {
    var question = _question();
    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    expect(LearningContextCodec.fsrsState(question.tags), isNotNull);

    final reset = service.reset(question, now: now);
    expect(reset.masteryLevel, MasteryLevel.newQuestion);
    expect(reset.reviewCount, 1); // 保留 reviewCount
    expect(reset.nextReviewAt, now);
    expect(LearningContextCodec.fsrsState(reset.tags), isNull);
    expect(LearningContextCodec.fsrsStability(reset.tags), isNull);
    expect(service.isDue(reset, now: now), isTrue);
  });

  test('reviewCount increments across multiple reviews', () {
    var question = _question(reviewCount: 0);
    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    expect(question.reviewCount, 1);
    question = service.apply(question, ReviewRating.hard,
        reviewedAt: now.add(const Duration(days: 1)));
    expect(question.reviewCount, 2);
    question = service.apply(question, ReviewRating.forgot,
        reviewedAt: now.add(const Duration(days: 5)));
    expect(question.reviewCount, 3);
  });

  test('Learning 阶段再次 forgot 仍留在 Learning，lapses 不增', () {
    // 第一次 forgot：进 Learning，lapses=1。
    var question = service.apply(_question(), ReviewRating.forgot, reviewedAt: now);
    expect(LearningContextCodec.fsrsState(question.tags), FsrsState.learning);
    expect(LearningContextCodec.fsrsLapses(question.tags), 1);

    // Learning 阶段再次 forgot：留在 Learning，lapses 不增（仅 Review→Again 才增）。
    question = service.apply(question, ReviewRating.forgot,
        reviewedAt: now.add(const Duration(minutes: 10)));
    expect(LearningContextCodec.fsrsState(question.tags), FsrsState.learning);
    expect(LearningContextCodec.fsrsLapses(question.tags), 1);
  });

  test('Learning 阶段 easy 毕业到 Review', () {
    // 先 forgot 进 Learning。
    var question = service.apply(_question(), ReviewRating.forgot, reviewedAt: now);
    expect(LearningContextCodec.fsrsState(question.tags), FsrsState.learning);

    // 再 easy：毕业到 Review。
    question = service.apply(question, ReviewRating.easy,
        reviewedAt: now.add(const Duration(minutes: 10)));
    expect(LearningContextCodec.fsrsState(question.tags), FsrsState.review);
  });

  test('FSRS tags 序列化进 QuestionRecord.toJson 并能反序列化', () {
    var question = _question();
    question = service.apply(question, ReviewRating.easy, reviewedAt: now);
    final json = question.toJson();
    final restored = QuestionRecord.fromJson(json);
    expect(LearningContextCodec.fsrsState(restored.tags), FsrsState.review);
    expect(LearningContextCodec.fsrsStability(restored.tags), closeTo(2.4, 0.01));
    expect(LearningContextCodec.fsrsReps(restored.tags), 1);
  });
}
