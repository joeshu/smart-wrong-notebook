import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mastery_service.dart';

QuestionRecord _question(
  String id, {
  MasteryLevel mastery = MasteryLevel.newQuestion,
  DateTime? lastReviewedAt,
}) {
  final now = DateTime(2026, 7, 21);
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '',
    normalizedQuestionText: '',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: lastReviewedAt,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: mastery,
    analysisResult: null,
  );
}

ReviewStats _stats({
  int forgot = 0,
  int hard = 0,
  int easy = 0,
}) {
  return ReviewStats(
    forgotCount: forgot,
    hardCount: hard,
    easyCount: easy,
  );
}

void main() {
  late QuestionKnowledgeLinkRepository linkRepo;
  late KnowledgePointMasteryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    linkRepo = QuestionKnowledgeLinkRepository();
    service = KnowledgePointMasteryService(linkRepo);
  });

  group('KnowledgePointMasteryService.calculate', () {
    test('empty questions returns zero mastery', () async {
      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: const <QuestionRecord>[],
        reviewStatsByQuestion: const <String, ReviewStats>{},
      );

      expect(mastery.totalQuestions, 0);
      expect(mastery.masteryPercentage, 0);
      expect(mastery.level, MasteryLevel.newQuestion);
    });

    test('all mastered questions → high percentage', () async {
      // Link questions to single KP
      await linkRepo.addLinks(<QuestionKnowledgeLink>[
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_1',
          createdAt: DateTime(2026),
        ),
        QuestionKnowledgeLink(
          questionId: 'q_2',
          knowledgePointId: 'kp_1',
          createdAt: DateTime(2026),
        ),
      ]);

      final questions = <QuestionRecord>[
        _question('q_1', mastery: MasteryLevel.mastered, lastReviewedAt: DateTime(2026, 7, 20)),
        _question('q_2', mastery: MasteryLevel.mastered, lastReviewedAt: DateTime(2026, 7, 20)),
      ];

      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: questions,
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      expect(mastery.masteredCount, 2);
      // Phase 12-1 新算法：mastered+最近复习+无 forgot/hard 时约 85%
      // （基础 30% + 正确率 40% + recency 20% + 难度 10%），不再到 100。
      expect(mastery.masteryPercentage, greaterThan(80));
      expect(mastery.level, MasteryLevel.mastered);
    });

    test('all new questions → low percentage with penalty', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));

      final questions = <QuestionRecord>[
        _question('q_1', mastery: MasteryLevel.newQuestion),
      ];

      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: questions,
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      expect(mastery.newCount, 1);
      // newQuestion base = 0.1 = 10%, plus new question penalty = -10
      expect(mastery.masteryPercentage, lessThan(10));
    });

    test('review decay reduces mastery over time', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));

      final recentMastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_1', mastery: MasteryLevel.mastered, lastReviewedAt: DateTime(2026, 7, 14)),
        ],
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      final oldMastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_1', mastery: MasteryLevel.mastered, lastReviewedAt: DateTime(2026, 6, 1)),
        ],
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      // Old review should have lower mastery due to decay
      expect(oldMastery.masteryPercentage, lessThan(recentMastery.masteryPercentage));
    });

    test('forgot/hard counts reduce mastery', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));

      final noPenalty = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_1', mastery: MasteryLevel.reviewing, lastReviewedAt: DateTime(2026, 7, 20)),
        ],
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      final withPenalty = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_1', mastery: MasteryLevel.reviewing, lastReviewedAt: DateTime(2026, 7, 20)),
        ],
        reviewStatsByQuestion: <String, ReviewStats>{
          'q_1': _stats(forgot: 3, hard: 2),
        },
        now: DateTime(2026, 7, 21),
      );

      expect(withPenalty.masteryPercentage, lessThan(noPenalty.masteryPercentage));
      expect(withPenalty.forgotCount, 3);
      expect(withPenalty.hardCount, 2);
    });

    test('multi-KP question contributes weighted score', () async {
      // q_1 linked to 2 KPs → weight = 0.5 each
      await linkRepo.addLinks(<QuestionKnowledgeLink>[
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_1',
          createdAt: DateTime(2026),
        ),
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_2',
          createdAt: DateTime(2026),
        ),
      ]);

      final questions = <QuestionRecord>[
        _question('q_1', mastery: MasteryLevel.mastered, lastReviewedAt: DateTime(2026, 7, 20)),
      ];

      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: questions,
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      // Should still be high (mastered, recently reviewed)
      expect(mastery.masteryPercentage, greaterThan(80));
    });

    test('lastReviewedAt is the most recent among all questions', () async {
      await linkRepo.addLinks(<QuestionKnowledgeLink>[
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_1',
          createdAt: DateTime(2026),
        ),
        QuestionKnowledgeLink(
          questionId: 'q_2',
          knowledgePointId: 'kp_1',
          createdAt: DateTime(2026),
        ),
      ]);

      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_1', lastReviewedAt: DateTime(2026, 7, 10)),
          _question('q_2', lastReviewedAt: DateTime(2026, 7, 15)),
        ],
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      expect(mastery.lastReviewedAt, DateTime(2026, 7, 15));
    });

    test('factors map contains calculation breakdown', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));

      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_1', mastery: MasteryLevel.newQuestion),
        ],
        reviewStatsByQuestion: <String, ReviewStats>{
          'q_1': _stats(forgot: 1),
        },
        now: DateTime(2026, 7, 21),
      );

      // 兼容旧 UI 的 key。
      expect(mastery.factors.containsKey('baseScore'), isTrue);
      expect(mastery.factors.containsKey('forgotPenalty'), isTrue);
      expect(mastery.factors.containsKey('hardPenalty'), isTrue);
      expect(mastery.factors.containsKey('newQuestionPenalty'), isTrue);
      expect(mastery.factors['forgotPenalty'], 5.0);
      // Phase 12-1 新增因子子分数 + 权重 key。
      expect(mastery.factors.containsKey('accuracy'), isTrue);
      expect(mastery.factors.containsKey('recency'), isTrue);
      expect(mastery.factors.containsKey('difficulty'), isTrue);
      expect(mastery.factors.containsKey('accuracyWeight'), isTrue);
      expect(mastery.factors['accuracyWeight'], 40.0);
      expect(mastery.factors['recencyWeight'], 20.0);
      expect(mastery.factors['difficultyWeight'], 10.0);
      expect(mastery.factors['baseWeight'], 30.0);
    });

    // ── Phase 12-1 新算法单测 ───────────────────────────────────────────

    test('Phase 12-1：高难度题（challenge）难度因子接近满分', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_hard',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));
      // challenge 题难度权重 1.0 → 难度子分数 100。
      final hardQuestion = _question('q_hard',
              mastery: MasteryLevel.reviewing,
              lastReviewedAt: DateTime(2026, 7, 20))
          .withLearningContext(difficulty: QuestionDifficulty.challenge);

      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[hardQuestion],
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      expect(mastery.factors['difficulty'], closeTo(100, 0.1));
    });

    test('Phase 12-1：复习次数饱和到 10 次时 recency 接近满分', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_rev',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));
      final q = _question('q_rev',
          mastery: MasteryLevel.reviewing,
          lastReviewedAt: DateTime(2026, 7, 20));
      // 10 次 easy 复习 → recency 子分数 100（衰减后 1 天内 = 1.0）。
      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[q],
        reviewStatsByQuestion: <String, ReviewStats>{
          'q_rev': _stats(easy: 10),
        },
        now: DateTime(2026, 7, 21),
      );

      expect(mastery.factors['recency'], closeTo(100, 0.1));
      // accuracy 子分数 = easy/total = 10/10 = 100。
      expect(mastery.factors['accuracy'], closeTo(100, 0.1));
    });

    test('Phase 12-1：全部 forgot 时 accuracy 为 0', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_forgot',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));
      final q = _question('q_forgot',
          mastery: MasteryLevel.reviewing,
          lastReviewedAt: DateTime(2026, 7, 20));
      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[q],
        reviewStatsByQuestion: <String, ReviewStats>{
          'q_forgot': _stats(forgot: 5, hard: 2),
        },
        now: DateTime(2026, 7, 21),
      );

      expect(mastery.factors['accuracy'], 0.0);
    });

    test('Phase 12-1：权重之和为 100', () async {
      await linkRepo.addLink(QuestionKnowledgeLink(
        questionId: 'q_w',
        knowledgePointId: 'kp_1',
        createdAt: DateTime(2026),
      ));
      final mastery = await service.calculate(
        knowledgePointId: 'kp_1',
        questions: <QuestionRecord>[
          _question('q_w', mastery: MasteryLevel.mastered,
              lastReviewedAt: DateTime(2026, 7, 20)),
        ],
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );
      final sum = mastery.factors['accuracyWeight']! +
          mastery.factors['recencyWeight']! +
          mastery.factors['difficultyWeight']! +
          mastery.factors['baseWeight']!;
      expect(sum, closeTo(100, 0.01));
    });
  });

  group('KnowledgePointMasteryService.calculateBatch', () {
    test('calculates mastery for multiple knowledge points', () async {
      await linkRepo.addLinks(<QuestionKnowledgeLink>[
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_1',
          createdAt: DateTime(2026),
        ),
        QuestionKnowledgeLink(
          questionId: 'q_2',
          knowledgePointId: 'kp_2',
          createdAt: DateTime(2026),
        ),
      ]);

      final results = await service.calculateBatch(
        questionsByKp: <String, List<QuestionRecord>>{
          'kp_1': <QuestionRecord>[
            _question('q_1', mastery: MasteryLevel.mastered, lastReviewedAt: DateTime(2026, 7, 20)),
          ],
          'kp_2': <QuestionRecord>[
            _question('q_2', mastery: MasteryLevel.newQuestion),
          ],
        },
        reviewStatsByQuestion: const <String, ReviewStats>{},
        now: DateTime(2026, 7, 21),
      );

      expect(results.length, 2);
      final kp1Mastery = results.firstWhere((m) => m.knowledgePointId == 'kp_1');
      final kp2Mastery = results.firstWhere((m) => m.knowledgePointId == 'kp_2');
      expect(kp1Mastery.masteryPercentage, greaterThan(kp2Mastery.masteryPercentage));
    });
  });

  group('KnowledgePointMastery', () {
    test('level thresholds', () {
      final high = KnowledgePointMastery(
        knowledgePointId: 'kp_1',
        totalQuestions: 5,
        masteredCount: 4,
        reviewingCount: 1,
        newCount: 0,
        forgotCount: 0,
        hardCount: 0,
        easyCount: 5,
        lastReviewedAt: DateTime(2026),
        masteryPercentage: 85,
        calculatedAt: DateTime(2026),
      );
      expect(high.level, MasteryLevel.mastered);

      final mid = KnowledgePointMastery(
        knowledgePointId: 'kp_2',
        totalQuestions: 5,
        masteredCount: 1,
        reviewingCount: 3,
        newCount: 1,
        forgotCount: 2,
        hardCount: 1,
        easyCount: 2,
        lastReviewedAt: DateTime(2026),
        masteryPercentage: 50,
        calculatedAt: DateTime(2026),
      );
      expect(mid.level, MasteryLevel.reviewing);

      final low = KnowledgePointMastery(
        knowledgePointId: 'kp_3',
        totalQuestions: 5,
        masteredCount: 0,
        reviewingCount: 1,
        newCount: 4,
        forgotCount: 0,
        hardCount: 0,
        easyCount: 0,
        lastReviewedAt: null,
        masteryPercentage: 10,
        calculatedAt: DateTime(2026),
      );
      expect(low.level, MasteryLevel.newQuestion);
    });

    test('hasPendingReviews', () {
      final withPending = KnowledgePointMastery(
        knowledgePointId: 'kp_1',
        totalQuestions: 3,
        masteredCount: 1,
        reviewingCount: 1,
        newCount: 1,
        forgotCount: 0,
        hardCount: 0,
        easyCount: 0,
        lastReviewedAt: DateTime(2026),
        masteryPercentage: 50,
        calculatedAt: DateTime(2026),
      );
      expect(withPending.hasPendingReviews, isTrue);

      final allMastered = KnowledgePointMastery(
        knowledgePointId: 'kp_2',
        totalQuestions: 3,
        masteredCount: 3,
        reviewingCount: 0,
        newCount: 0,
        forgotCount: 0,
        hardCount: 0,
        easyCount: 5,
        lastReviewedAt: DateTime(2026),
        masteryPercentage: 95,
        calculatedAt: DateTime(2026),
      );
      expect(allMastered.hasPendingReviews, isFalse);
    });
  });
}
