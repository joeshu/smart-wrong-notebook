import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/subject_radar_aggregator.dart';

QuestionRecord _question(
  String id, {
  required Subject subject,
  required MasteryLevel mastery,
}) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: subject,
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
    masteryLevel: mastery,
    analysisResult: null,
  );
}

void main() {
  group('aggregateSubjectRadarFromQuestions', () {
    test('empty question bank returns empty scores', () {
      final data = aggregateSubjectRadarFromQuestions(
        const <QuestionRecord>[],
        generatedAt: DateTime(2026, 7, 20, 10, 0, 0),
      );

      expect(data.scores, isEmpty);
      expect(data.totalQuestions, 0);
      expect(data.totalMastered, 0);
      expect(data.totalReviewing, 0);
      expect(data.totalNew, 0);
      expect(data.bySubjectTotals, isEmpty);
    });

    test('single math subject 3 questions yields abilityScore 50', () {
      // 1 mastered + 1 reviewing + 1 newQuestion => (1*1.0 + 1*0.5) / 3 * 100 = 50
      final data = aggregateSubjectRadarFromQuestions(
        <QuestionRecord>[
          _question('q-1', subject: Subject.math, mastery: MasteryLevel.mastered),
          _question('q-2', subject: Subject.math, mastery: MasteryLevel.reviewing),
          _question('q-3', subject: Subject.math, mastery: MasteryLevel.newQuestion),
        ],
        generatedAt: DateTime(2026, 7, 20, 10, 0, 0),
      );

      expect(data.scores, hasLength(1));
      final score = data.scores.single;
      expect(score.subject, Subject.math);
      expect(score.total, 3);
      expect(score.mastered, 1);
      expect(score.reviewing, 1);
      expect(score.newQuestions, 1);
      expect(score.abilityScore, closeTo(50.0, 1e-9));

      expect(data.totalQuestions, 3);
      expect(data.totalMastered, 1);
      expect(data.totalReviewing, 1);
      expect(data.totalNew, 1);
      expect(data.bySubjectTotals, {'数学': 3});
    });

    test('multiple subjects are sorted by abilityScore ascending', () {
      // 数学：2 mastered / 0 reviewing / 0 new => 100
      // 英语：0 mastered / 2 reviewing / 0 new => 50
      // 物理：0 mastered / 0 reviewing / 2 new => 0
      final data = aggregateSubjectRadarFromQuestions(
        <QuestionRecord>[
          _question('m-1', subject: Subject.math, mastery: MasteryLevel.mastered),
          _question('m-2', subject: Subject.math, mastery: MasteryLevel.mastered),
          _question('e-1', subject: Subject.english, mastery: MasteryLevel.reviewing),
          _question('e-2', subject: Subject.english, mastery: MasteryLevel.reviewing),
          _question('p-1', subject: Subject.physics, mastery: MasteryLevel.newQuestion),
          _question('p-2', subject: Subject.physics, mastery: MasteryLevel.newQuestion),
        ],
        generatedAt: DateTime(2026, 7, 20, 10, 0, 0),
      );

      expect(data.scores, hasLength(3));
      // 升序：物理(0) -> 英语(50) -> 数学(100)
      expect(data.scores[0].subject, Subject.physics);
      expect(data.scores[0].abilityScore, closeTo(0.0, 1e-9));
      expect(data.scores[1].subject, Subject.english);
      expect(data.scores[1].abilityScore, closeTo(50.0, 1e-9));
      expect(data.scores[2].subject, Subject.math);
      expect(data.scores[2].abilityScore, closeTo(100.0, 1e-9));

      expect(data.totalQuestions, 6);
      expect(data.totalMastered, 2);
      expect(data.totalReviewing, 2);
      expect(data.totalNew, 2);
      expect(data.bySubjectTotals, {'数学': 2, '英语': 2, '物理': 2});
    });

    test('subjects with total=0 do not appear in scores', () {
      // 仅数学有题；其它学科无题不应出现（按当前实现不会被加入 stats）。
      final data = aggregateSubjectRadarFromQuestions(
        <QuestionRecord>[
          _question('m-1', subject: Subject.math, mastery: MasteryLevel.mastered),
        ],
        generatedAt: DateTime(2026, 7, 20, 10, 0, 0),
      );

      expect(data.scores, hasLength(1));
      expect(data.scores.single.subject, Subject.math);
      expect(data.scores.single.total, 1);
      expect(data.bySubjectTotals.keys, contains('数学'));
      expect(data.bySubjectTotals.keys, isNot(contains('英语')));
      expect(data.bySubjectTotals.keys, isNot(contains('物理')));
    });

    test('weighted formula respects reviewing*0.5 contribution', () {
      // 2 mastered + 4 reviewing + 4 new => (2 + 2) / 10 * 100 = 40
      final records = <QuestionRecord>[
        _question('a-1', subject: Subject.math, mastery: MasteryLevel.mastered),
        _question('a-2', subject: Subject.math, mastery: MasteryLevel.mastered),
        _question('a-3', subject: Subject.math, mastery: MasteryLevel.reviewing),
        _question('a-4', subject: Subject.math, mastery: MasteryLevel.reviewing),
        _question('a-5', subject: Subject.math, mastery: MasteryLevel.reviewing),
        _question('a-6', subject: Subject.math, mastery: MasteryLevel.reviewing),
        _question('a-7', subject: Subject.math, mastery: MasteryLevel.newQuestion),
        _question('a-8', subject: Subject.math, mastery: MasteryLevel.newQuestion),
        _question('a-9', subject: Subject.math, mastery: MasteryLevel.newQuestion),
        _question('a-10', subject: Subject.math, mastery: MasteryLevel.newQuestion),
      ];
      final data = aggregateSubjectRadarFromQuestions(
        records,
        generatedAt: DateTime(2026, 7, 20, 10, 0, 0),
      );
      expect(data.scores.single.abilityScore, closeTo(40.0, 1e-9));
    });
  });

  group('aggregateSubjectRadar via ProviderContainer', () {
    test('reads questionListProvider and aggregates', () async {
      final repo = InMemoryQuestionRepository();
      await repo.saveDraft(
        _question('q-1', subject: Subject.math, mastery: MasteryLevel.mastered),
      );
      await repo.saveDraft(
        _question('q-2', subject: Subject.math, mastery: MasteryLevel.reviewing),
      );
      await repo.saveDraft(
        _question('q-3',
            subject: Subject.math, mastery: MasteryLevel.newQuestion),
      );

      final container = ProviderContainer(
        overrides: <Override>[
          questionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final questions = await container.read(questionListProvider.future);
      final data = aggregateSubjectRadarFromQuestions(questions);

      expect(data.scores, hasLength(1));
      expect(data.scores.single.subject, Subject.math);
      expect(data.scores.single.abilityScore, closeTo(50.0, 1e-9));
      expect(data.totalQuestions, 3);
    });

    test('empty repository yields empty scores', () async {
      final repo = InMemoryQuestionRepository();
      final container = ProviderContainer(
        overrides: <Override>[
          questionRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);

      final questions = await container.read(questionListProvider.future);
      final data = aggregateSubjectRadarFromQuestions(questions);

      expect(data.scores, isEmpty);
      expect(data.totalQuestions, 0);
    });
  });
}
