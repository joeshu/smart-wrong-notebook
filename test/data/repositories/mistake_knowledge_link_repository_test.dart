import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/mistake_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

void main() {
  late MistakeKnowledgeLinkRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = MistakeKnowledgeLinkRepository();
  });

  MistakeKnowledgeLink link(
    String qId,
    String kpId,
    MistakeCategory category, {
    LinkSource source = LinkSource.ai,
    String? errorStep,
  }) {
    return MistakeKnowledgeLink(
      questionId: qId,
      knowledgePointId: kpId,
      mistakeCategory: category,
      source: source,
      errorStep: errorStep,
      createdAt: DateTime(2026),
    );
  }

  group('MistakeKnowledgeLink', () {
    test('toJson / fromJson round-trip', () {
      final l = MistakeKnowledgeLink(
        questionId: 'q_1',
        knowledgePointId: 'kp_1',
        mistakeCategory: MistakeCategory.calculation,
        source: LinkSource.ai,
        confidence: 0.85,
        evidence: '第 2 步计算错误',
        errorStep: 'step_2',
        createdAt: DateTime(2026, 7, 21, 10),
      );
      final json = l.toJson();
      final restored = MistakeKnowledgeLink.fromJson(json);

      expect(restored.questionId, l.questionId);
      expect(restored.knowledgePointId, l.knowledgePointId);
      expect(restored.mistakeCategory, MistakeCategory.calculation);
      expect(restored.source, LinkSource.ai);
      expect(restored.confidence, closeTo(0.85, 0.001));
      expect(restored.evidence, l.evidence);
      expect(restored.errorStep, l.errorStep);
    });

    test('key is unique per (questionId, kpId, category)', () {
      final a = link('q_1', 'kp_1', MistakeCategory.calculation);
      final b = link('q_1', 'kp_1', MistakeCategory.concept);
      final c = link('q_1', 'kp_1', MistakeCategory.calculation);

      expect(a.key == b.key, isFalse);
      expect(a.key == c.key, isTrue);
      expect(a == c, isTrue);
    });
  });

  group('MistakeKnowledgeLinkRepository', () {
    test('addLink and linksForQuestion', () async {
      await repo.addLink(link('q_1', 'kp_1', MistakeCategory.calculation));
      await repo.addLink(link('q_1', 'kp_1', MistakeCategory.concept));

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 2);
    });

    test('addLink skips duplicates', () async {
      await repo.addLink(link('q_1', 'kp_1', MistakeCategory.calculation));
      await repo.addLink(link('q_1', 'kp_1', MistakeCategory.calculation));

      expect((await repo.linksForQuestion('q_1')).length, 1);
    });

    test('removeLink removes specific triple', () async {
      await repo.addLink(link('q_1', 'kp_1', MistakeCategory.calculation));
      await repo.addLink(link('q_1', 'kp_1', MistakeCategory.concept));

      final removed = await repo.removeLink(
          'q_1', 'kp_1', MistakeCategory.calculation);
      expect(removed, isTrue);

      final remaining = await repo.linksForQuestion('q_1');
      expect(remaining.length, 1);
      expect(remaining.first.mistakeCategory, MistakeCategory.concept);
    });

    test('linksForKnowledgePoint returns all links for KP', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_math', MistakeCategory.calculation),
        link('q_2', 'kp_math', MistakeCategory.concept),
        link('q_3', 'kp_phys', MistakeCategory.careless),
      ]);

      final links = await repo.linksForKnowledgePoint('kp_math');
      expect(links.length, 2);
    });

    test('questionIdsForKnowledgePoint deduplicates', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_1', MistakeCategory.calculation),
        link('q_1', 'kp_1', MistakeCategory.concept), // same question, different category
        link('q_2', 'kp_1', MistakeCategory.careless),
      ]);

      final ids = await repo.questionIdsForKnowledgePoint('kp_1');
      expect(ids.length, 2); // q_1 and q_2, not 3
      expect(ids.toSet(), <String>{'q_1', 'q_2'});
    });

    test('linksForCategory filters by mistake type', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_1', MistakeCategory.calculation),
        link('q_2', 'kp_2', MistakeCategory.calculation),
        link('q_3', 'kp_1', MistakeCategory.concept),
      ]);

      final calcLinks = await repo.linksForCategory(MistakeCategory.calculation);
      expect(calcLinks.length, 2);
    });

    test('categoryDistributionForKnowledgePoint', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_1', MistakeCategory.calculation),
        link('q_2', 'kp_1', MistakeCategory.calculation),
        link('q_3', 'kp_1', MistakeCategory.concept),
        link('q_4', 'kp_2', MistakeCategory.careless),
      ]);

      final dist =
          await repo.categoryDistributionForKnowledgePoint('kp_1');
      expect(dist[MistakeCategory.calculation], 2);
      expect(dist[MistakeCategory.concept], 1);
      expect(dist.containsKey(MistakeCategory.careless), isFalse);
    });

    test('globalCategoryDistribution', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_1', MistakeCategory.calculation),
        link('q_2', 'kp_1', MistakeCategory.concept),
        link('q_3', 'kp_2', MistakeCategory.calculation),
      ]);

      final dist = await repo.globalCategoryDistribution();
      expect(dist[MistakeCategory.calculation], 2);
      expect(dist[MistakeCategory.concept], 1);
    });

    test('replaceLinksForQuestion clears old and adds new', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_old', MistakeCategory.calculation),
      ]);

      await repo.replaceLinksForQuestion('q_1', <MistakeKnowledgeLink>[
        link('q_1', 'kp_new', MistakeCategory.concept),
      ]);

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 1);
      expect(links.first.knowledgePointId, 'kp_new');
      expect(links.first.mistakeCategory, MistakeCategory.concept);
    });

    test('persists across instances', () async {
      await repo.addLink(link('q_persist', 'kp_1', MistakeCategory.calculation));

      final newRepo = MistakeKnowledgeLinkRepository();
      final links = await newRepo.linksForQuestion('q_persist');
      expect(links.length, 1);
    });

    test('one question multiple categories same KP', () async {
      await repo.addLinks(<MistakeKnowledgeLink>[
        link('q_1', 'kp_1', MistakeCategory.calculation),
        link('q_1', 'kp_1', MistakeCategory.concept),
        link('q_1', 'kp_1', MistakeCategory.careless),
      ]);

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 3);
      final categories = links.map((l) => l.mistakeCategory).toSet();
      expect(categories.length, 3);
    });
  });
}
