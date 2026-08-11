import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

QuestionRecord _question() {
  final now = DateTime(2026, 7, 18);
  return QuestionRecord(
    id: 'q-1',
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目',
    normalizedQuestionText: '题目',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>['normal-tag'],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

void main() {
  test('persists selected mistake category in durable internal marker', () {
    final updated = _question().withMistakeCategory(MistakeCategory.calculation);

    expect(updated.mistakeCategory, MistakeCategory.calculation);
    expect(updated.tags, contains('normal-tag'));
    expect(updated.toJson()['tags'], contains('__system_mistake_category:calculation'));
  });

  test('changing and clearing category leaves no stale category marker', () {
    final categorized = _question().withMistakeCategory(MistakeCategory.concept);
    final changed = categorized.withMistakeCategory(MistakeCategory.careless);
    final cleared = changed.withMistakeCategory(null);

    expect(changed.mistakeCategory, MistakeCategory.careless);
    expect(changed.tags.where((tag) => tag.startsWith('__system_mistake_category:')),
        hasLength(1));
    expect(cleared.mistakeCategory, isNull);
    expect(cleared.tags, contains('normal-tag'));
  });
}
