import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

void main() {
  late QuestionKnowledgeLinkRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = QuestionKnowledgeLinkRepository();
  });

  QuestionKnowledgeLink link(
    String qId,
    String kpId, {
    LinkSource source = LinkSource.ai,
    double? confidence,
  }) {
    return QuestionKnowledgeLink(
      questionId: qId,
      knowledgePointId: kpId,
      source: source,
      confidence: confidence,
      createdAt: DateTime(2026),
    );
  }

  group('QuestionKnowledgeLinkRepository', () {
    test('addLink and linksForQuestion', () async {
      await repo.addLink(link('q_1', 'kp_1'));
      await repo.addLink(link('q_1', 'kp_2'));

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 2);
    });

    test('addLink skips duplicates', () async {
      await repo.addLink(link('q_1', 'kp_1'));
      await repo.addLink(link('q_1', 'kp_1')); // duplicate

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 1);
    });

    test('addLinks batch adds without duplicates', () async {
      await repo.addLinks(<QuestionKnowledgeLink>[
        link('q_1', 'kp_1'),
        link('q_1', 'kp_2'),
        link('q_1', 'kp_1'), // duplicate within batch
        link('q_2', 'kp_1'),
      ]);

      expect((await repo.linksForQuestion('q_1')).length, 2);
      expect((await repo.linksForQuestion('q_2')).length, 1);
    });

    test('removeLink removes and returns true', () async {
      await repo.addLink(link('q_1', 'kp_1'));

      final removed = await repo.removeLink('q_1', 'kp_1');
      expect(removed, isTrue);
      expect(await repo.linksForQuestion('q_1'), isEmpty);
    });

    test('removeLink returns false for non-existent link', () async {
      final removed = await repo.removeLink('q_1', 'kp_1');
      expect(removed, isFalse);
    });

    test('questionIdsForKnowledgePoint returns question IDs', () async {
      await repo.addLinks(<QuestionKnowledgeLink>[
        link('q_1', 'kp_math'),
        link('q_2', 'kp_math'),
        link('q_3', 'kp_phys'),
      ]);

      final questionIds = await repo.questionIdsForKnowledgePoint('kp_math');
      expect(questionIds.length, 2);
      expect(questionIds.toSet(), <String>{'q_1', 'q_2'});
    });

    test('linksForKnowledgePoint returns full link records', () async {
      await repo.addLink(link('q_1', 'kp_1', confidence: 0.9));

      final links = await repo.linksForKnowledgePoint('kp_1');
      expect(links.length, 1);
      expect(links.first.questionId, 'q_1');
      expect(links.first.confidence, closeTo(0.9, 0.001));
    });

    test('replaceLinksForQuestion clears old and adds new', () async {
      await repo.addLinks(<QuestionKnowledgeLink>[
        link('q_1', 'kp_old_1'),
        link('q_1', 'kp_old_2'),
      ]);

      await repo.replaceLinksForQuestion('q_1', <QuestionKnowledgeLink>[
        link('q_1', 'kp_new_1'),
      ]);

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 1);
      expect(links.first.knowledgePointId, 'kp_new_1');
    });

    test('replaceLinksForQuestion updates KP index correctly', () async {
      await repo.addLink(link('q_1', 'kp_old'));

      await repo.replaceLinksForQuestion('q_1', <QuestionKnowledgeLink>[
        link('q_1', 'kp_new'),
      ]);

      // Old KP should have no links
      expect(await repo.linksForKnowledgePoint('kp_old'), isEmpty);
      // New KP should have the link
      expect((await repo.linksForKnowledgePoint('kp_new')).length, 1);
    });

    test('allLinks returns all links across questions', () async {
      await repo.addLinks(<QuestionKnowledgeLink>[
        link('q_1', 'kp_1'),
        link('q_2', 'kp_2'),
        link('q_3', 'kp_3'),
      ]);

      final all = await repo.allLinks();
      expect(all.length, 3);
    });

    test('persists across instances (SharedPreferences)', () async {
      await repo.addLink(link('q_persist', 'kp_persist'));

      final newRepo = QuestionKnowledgeLinkRepository();
      final links = await newRepo.linksForQuestion('q_persist');
      expect(links.length, 1);
      expect(links.first.knowledgePointId, 'kp_persist');
    });
  });

  group('setPrimary (Phase 6-3)', () {
    test('promotes one link to primary and demotes others', () async {
      await repo.addLinks(<QuestionKnowledgeLink>[
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_1',
          source: LinkSource.ai,
          createdAt: DateTime(2026),
          isPrimary: true,
        ),
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_2',
          source: LinkSource.manual,
          createdAt: DateTime(2026),
        ),
      ]);

      await repo.setPrimary('q_1', 'kp_2');

      final links = await repo.linksForQuestion('q_1');
      final kp1 = links.firstWhere((l) => l.knowledgePointId == 'kp_1');
      final kp2 = links.firstWhere((l) => l.knowledgePointId == 'kp_2');
      expect(kp1.isPrimary, isFalse);
      expect(kp2.isPrimary, isTrue);
    });

    test('is a no-op when target link does not exist', () async {
      await repo.addLink(link('q_1', 'kp_1'));
      await repo.setPrimary('q_1', 'kp_missing');

      final links = await repo.linksForQuestion('q_1');
      expect(links.single.isPrimary, isFalse);
    });

    test('removeLink promotes remaining first link if primary was removed',
        () async {
      await repo.addLinks(<QuestionKnowledgeLink>[
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_primary',
          source: LinkSource.ai,
          createdAt: DateTime(2026),
          isPrimary: true,
        ),
        QuestionKnowledgeLink(
          questionId: 'q_1',
          knowledgePointId: 'kp_secondary',
          source: LinkSource.manual,
          createdAt: DateTime(2026),
        ),
      ]);

      await repo.removeLink('q_1', 'kp_primary');

      final links = await repo.linksForQuestion('q_1');
      expect(links.length, 1);
      expect(links.single.knowledgePointId, 'kp_secondary');
      expect(links.single.isPrimary, isTrue);
    });
  });
}
