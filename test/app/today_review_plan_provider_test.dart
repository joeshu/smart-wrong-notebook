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

QuestionRecord _question(String id, {DateTime? nextReviewAt}) {
  final now = DateTime.now();
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目',
    normalizedQuestionText: '题目',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    nextReviewAt: nextReviewAt,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

void main() {
  test('today review plan deduplicates completed questions', () async {
    final questions = InMemoryQuestionRepository();
    final logs = InMemoryReviewLogRepository();
    await questions.saveDraft(_question('due'));
    await questions.saveDraft(
      _question('future', nextReviewAt: DateTime.now().add(const Duration(days: 1))),
    );
    await logs.insert(ReviewLog(
      id: '1',
      questionRecordId: 'done',
      reviewedAt: DateTime.now(),
      result: 'easy',
      masteryAfter: MasteryLevel.mastered,
    ));
    await logs.insert(ReviewLog(
      id: '2',
      questionRecordId: 'done',
      reviewedAt: DateTime.now(),
      result: 'hard',
      masteryAfter: MasteryLevel.reviewing,
    ));
    final container = ProviderContainer(overrides: <Override>[
      questionRepositoryProvider.overrideWithValue(questions),
      reviewLogRepositoryProvider.overrideWithValue(logs),
    ]);
    addTearDown(container.dispose);

    final plan = await container.read(todayReviewPlanProvider.future);

    expect(plan.dueCount, 1);
    expect(plan.completedCount, 1);
    expect(plan.targetCount, 2);
    expect(plan.estimatedMinutes, 3);
    expect(plan.streakDays, 1);
  });
}
