import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/recommendation.dart';
import 'package:smart_wrong_notebook/src/domain/services/recommendation_service.dart';

KnowledgePointMastery _mastery({
  required String kpId,
  double percentage = 50,
  int total = 5,
  int mastered = 2,
  int reviewing = 2,
  int newCount = 1,
  int forgot = 1,
  int hard = 1,
  int easy = 3,
  DateTime? lastReviewed,
}) {
  return KnowledgePointMastery(
    knowledgePointId: kpId,
    totalQuestions: total,
    masteredCount: mastered,
    reviewingCount: reviewing,
    newCount: newCount,
    forgotCount: forgot,
    hardCount: hard,
    easyCount: easy,
    lastReviewedAt: lastReviewed,
    masteryPercentage: percentage,
    calculatedAt: DateTime(2026, 7, 21),
  );
}

void main() {
  late RecommendationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = RecommendationService();
  });

  group('RecommendationService.generate', () {
    test('generates recommendations for weak knowledge points', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_weak',
          mastery: _mastery(kpId: 'kp_weak', percentage: 20, forgot: 3),
          questionIds: <String>['q_1', 'q_2'],
          errorQuestionIds: <String>['q_1'],
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );

      expect(recs, isNotEmpty);
      // Should have both review and practice recommendations
      expect(recs.any((r) => r.type == RecommendationType.review), isTrue);
      expect(recs.any((r) => r.type == RecommendationType.practice), isTrue);
    });

    test('skips knowledge points with no questions', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_empty',
          mastery: _mastery(kpId: 'kp_empty', total: 0, percentage: 0),
          questionIds: const <String>[],
          errorQuestionIds: const <String>[],
        ),
      ];

      final recs = await service.generate(inputs: inputs);
      expect(recs, isEmpty);
    });

    test('higher score for weaker knowledge points', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_weak',
          mastery: _mastery(kpId: 'kp_weak', percentage: 10, forgot: 5),
          questionIds: <String>['q_1'],
          errorQuestionIds: <String>['q_1'],
        ),
        RecommendationInput(
          knowledgePointId: 'kp_strong',
          mastery: _mastery(
            kpId: 'kp_strong',
            percentage: 90,
            forgot: 0,
            hard: 0,
            mastered: 4,
            reviewing: 1,
            newCount: 0,
          ),
          questionIds: <String>['q_2'],
          errorQuestionIds: const <String>[],
        ),
      ];

      final recs = await service.generate(inputs: inputs);
      expect(recs, isNotEmpty);

      // Weak KP should have higher score
      final weakRecs = recs.where((r) => r.knowledgePointId == 'kp_weak');
      final strongRecs = recs.where((r) => r.knowledgePointId == 'kp_strong');
      if (weakRecs.isNotEmpty && strongRecs.isNotEmpty) {
        expect(weakRecs.first.score, greaterThan(strongRecs.first.score));
      }
    });

    test('recommendations include reasons (explainability)', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(
            kpId: 'kp_1',
            percentage: 25,
            forgot: 2,
            newCount: 3,
          ),
          questionIds: <String>['q_1'],
          errorQuestionIds: <String>['q_1'],
        ),
      ];

      final recs = await service.generate(inputs: inputs);
      expect(recs, isNotEmpty);
      for (final rec in recs) {
        expect(rec.reasons, isNotEmpty);
      }
    });

    test('deduplicates by type + knowledgePointId', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 30),
          questionIds: <String>['q_1', 'q_2', 'q_3'],
          errorQuestionIds: <String>['q_1'],
        ),
      ];

      final recs = await service.generate(inputs: inputs);

      // Should not have duplicate types for same KP
      final reviewRecs =
          recs.where((r) => r.type == RecommendationType.review);
      final practiceRecs =
          recs.where((r) => r.type == RecommendationType.practice);
      expect(reviewRecs.length, lessThanOrEqualTo(1));
      expect(practiceRecs.length, lessThanOrEqualTo(1));
    });

    test('no practice recommendation for high mastery', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_strong',
          mastery: _mastery(
            kpId: 'kp_strong',
            percentage: 85,
            forgot: 0,
            mastered: 4,
            reviewing: 1,
            newCount: 0,
          ),
          questionIds: <String>['q_1'],
          errorQuestionIds: const <String>[],
        ),
      ];

      final recs = await service.generate(inputs: inputs);
      // Should not have practice recommendation for high mastery
      expect(
        recs.any((r) => r.type == RecommendationType.practice),
        isFalse,
      );
    });

    test('never-reviewed knowledge point gets highest recency score',
        () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_never',
          mastery: _mastery(
            kpId: 'kp_never',
            percentage: 40,
            lastReviewed: null,
          ),
          questionIds: <String>['q_1'],
          errorQuestionIds: <String>['q_1'],
        ),
        RecommendationInput(
          knowledgePointId: 'kp_recent',
          mastery: _mastery(
            kpId: 'kp_recent',
            percentage: 40,
            lastReviewed: DateTime(2026, 7, 20),
          ),
          questionIds: <String>['q_2'],
          errorQuestionIds: <String>['q_2'],
        ),
      ];

      final recs = await service.generate(inputs: inputs);
      final neverRecs =
          recs.where((r) => r.knowledgePointId == 'kp_never');
      final recentRecs =
          recs.where((r) => r.knowledgePointId == 'kp_recent');

      if (neverRecs.isNotEmpty && recentRecs.isNotEmpty) {
        expect(neverRecs.first.score, greaterThan(recentRecs.first.score));
      }
    });
  });

  group('RecommendationService difficulty ordering', () {
    test('relatedQuestionIds are sorted easy-to-hard by difficulty', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 20, forgot: 2),
          questionIds: <String>['q_challenge', 'q_foundation', 'q_advanced'],
          errorQuestionIds: <String>['q_challenge', 'q_foundation', 'q_advanced'],
          difficultyByQuestion: <String, QuestionDifficulty>{
            'q_foundation': QuestionDifficulty.foundation,
            'q_advanced': QuestionDifficulty.advanced,
            'q_challenge': QuestionDifficulty.challenge,
          },
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );

      final review = recs.firstWhere((r) => r.type == RecommendationType.review);
      expect(review.relatedQuestionIds,
          <String>['q_foundation', 'q_advanced', 'q_challenge']);
      expect(review.questionId, 'q_foundation');
    });

    test('questions without difficulty entry are treated as foundation',
        () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 20),
          questionIds: <String>['q_unknown', 'q_challenge'],
          errorQuestionIds: <String>['q_unknown', 'q_challenge'],
          difficultyByQuestion: <String, QuestionDifficulty>{
            'q_challenge': QuestionDifficulty.challenge,
          },
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );

      final review = recs.firstWhere((r) => r.type == RecommendationType.review);
      // Unknown difficulty → foundation → comes first
      expect(review.relatedQuestionIds.first, 'q_unknown');
    });

    test('reasons mention foundation-heavy knowledge point', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 25),
          questionIds: <String>['q_1', 'q_2', 'q_3'],
          errorQuestionIds: <String>['q_1'],
          difficultyByQuestion: <String, QuestionDifficulty>{
            'q_1': QuestionDifficulty.foundation,
            'q_2': QuestionDifficulty.foundation,
            'q_3': QuestionDifficulty.foundation,
          },
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );

      expect(recs, isNotEmpty);
      final allReasons = recs.expand((r) => r.reasons).join('\n');
      expect(allReasons, contains('基础题为主'));
    });

    test('reasons mention challenge-heavy knowledge point', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 25),
          questionIds: <String>['q_1', 'q_2'],
          errorQuestionIds: <String>['q_1'],
          difficultyByQuestion: <String, QuestionDifficulty>{
            'q_1': QuestionDifficulty.challenge,
            'q_2': QuestionDifficulty.advanced,
          },
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );

      expect(recs, isNotEmpty);
      final allReasons = recs.expand((r) => r.reasons).join('\n');
      expect(allReasons, contains('偏难'));
    });

    test('omits difficulty reason when no difficulty info available', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 25),
          questionIds: <String>['q_1', 'q_2'],
          errorQuestionIds: <String>['q_1'],
          // no difficultyByQuestion
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );

      expect(recs, isNotEmpty);
      final allReasons = recs.expand((r) => r.reasons).join('\n');
      expect(allReasons, isNot(contains('基础题为主')));
      expect(allReasons, isNot(contains('偏难')));
    });
  });

  group('RecommendationService ignore/markInvalid', () {
    test('ignored recommendations are excluded', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 20),
          questionIds: <String>['q_1'],
          errorQuestionIds: <String>['q_1'],
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );
      expect(recs, isNotEmpty);

      // Ignore the first recommendation
      await service.ignore(recs.first.id);

      final recsAfterIgnore = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );
      expect(
        recsAfterIgnore.any((r) => r.id == recs.first.id),
        isFalse,
      );
    });

    test('markInvalid excludes recommendation', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 20),
          questionIds: <String>['q_1'],
          errorQuestionIds: <String>['q_1'],
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );
      await service.markInvalid(recs.first.id);

      final recsAfter = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );
      expect(recsAfter.any((r) => r.id == recs.first.id), isFalse);
    });

    test('clearIgnored restores all recommendations', () async {
      final inputs = <RecommendationInput>[
        RecommendationInput(
          knowledgePointId: 'kp_1',
          mastery: _mastery(kpId: 'kp_1', percentage: 20),
          questionIds: <String>['q_1'],
          errorQuestionIds: <String>['q_1'],
        ),
      ];

      final recs = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );
      await service.ignore(recs.first.id);
      await service.clearIgnored();

      final recsAfter = await service.generate(
        inputs: inputs,
        now: DateTime(2026, 7, 21),
      );
      expect(recsAfter.any((r) => r.id == recs.first.id), isTrue);
    });
  });

  group('Recommendation model', () {
    test('toJson / fromJson round-trip', () {
      final rec = Recommendation(
        id: 'rec_1',
        type: RecommendationType.practice,
        knowledgePointId: 'kp_1',
        questionId: 'q_1',
        relatedQuestionIds: <String>['q_1', 'q_2'],
        score: 75.5,
        reasons: <String>['掌握度低', '忘记次数多'],
        createdAt: DateTime(2026, 7, 21, 10),
        ignored: false,
        markedInvalid: false,
      );

      final json = rec.toJson();
      final restored = Recommendation.fromJson(json);

      expect(restored.id, rec.id);
      expect(restored.type, RecommendationType.practice);
      expect(restored.knowledgePointId, rec.knowledgePointId);
      expect(restored.questionId, rec.questionId);
      expect(restored.relatedQuestionIds, rec.relatedQuestionIds);
      expect(restored.score, closeTo(75.5, 0.01));
      expect(restored.reasons, rec.reasons);
      expect(restored.ignored, isFalse);
      expect(restored.markedInvalid, isFalse);
    });

    test('isValid is false when ignored', () {
      final rec = Recommendation(
        id: 'rec_1',
        type: RecommendationType.review,
        knowledgePointId: 'kp_1',
        score: 50,
        reasons: <String>['test'],
        createdAt: DateTime(2026),
        ignored: true,
      );
      expect(rec.isValid, isFalse);
    });

    test('isValid is false when markedInvalid', () {
      final rec = Recommendation(
        id: 'rec_1',
        type: RecommendationType.review,
        knowledgePointId: 'kp_1',
        score: 50,
        reasons: <String>['test'],
        createdAt: DateTime(2026),
        markedInvalid: true,
      );
      expect(rec.isValid, isFalse);
    });

    test('copyWith updates ignored/markedInvalid', () {
      final rec = Recommendation(
        id: 'rec_1',
        type: RecommendationType.review,
        knowledgePointId: 'kp_1',
        score: 50,
        reasons: <String>['test'],
        createdAt: DateTime(2026),
      );

      final ignored = rec.copyWith(ignored: true);
      expect(ignored.ignored, isTrue);
      expect(ignored.markedInvalid, isFalse);

      final invalid = rec.copyWith(markedInvalid: true);
      expect(invalid.markedInvalid, isTrue);
      expect(invalid.ignored, isFalse);
    });
  });
}
