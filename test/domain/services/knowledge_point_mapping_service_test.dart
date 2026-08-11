import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mapping_service.dart';

void main() {
  late KnowledgePointRepository kpRepo;
  late QuestionKnowledgeLinkRepository linkRepo;
  late KnowledgePointMappingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    kpRepo = KnowledgePointRepository();
    linkRepo = QuestionKnowledgeLinkRepository();
    service = KnowledgePointMappingService(kpRepo, linkRepo);

    // Seed with built-in catalog
    await kpRepo.saveAll(KnowledgePointSeed.builtins());
  });

  group('KnowledgePointMappingService.mapStrings', () {
    test('exact match by name', () async {
      final matches = await service.mapStrings(<String>['二次函数']);
      expect(matches.length, 1);
      expect(matches.first.isMatched, isTrue);
      expect(matches.first.knowledgePointId, 'kp_math_functions_quadratic');
      expect(matches.first.confidence, 1.0);
    });

    test('exact match by alias', () async {
      final matches = await service.mapStrings(<String>['抛物线']);
      expect(matches.length, 1);
      expect(matches.first.isMatched, isTrue);
      expect(matches.first.knowledgePointId, 'kp_math_functions_quadratic');
    });

    test('case-insensitive match for English aliases', () async {
      // Add a knowledge point with an English alias
      await kpRepo.upsert(KnowledgePoint(
        id: 'kp_test_english',
        name: 'Newton\'s Laws',
        aliases: <String>['Newton', 'newton', 'F=ma'],
        subject: Subject.physics,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));

      final upper = await service.mapStrings(<String>['NEWTON']);
      expect(upper.first.isMatched, isTrue);
      expect(upper.first.knowledgePointId, 'kp_test_english');

      final lower = await service.mapStrings(<String>['newton']);
      expect(lower.first.isMatched, isTrue);
      expect(lower.first.knowledgePointId, 'kp_test_english');
    });

    test('contains match for longer text', () async {
      final matches = await service.mapStrings(<String>['二次函数的图像和性质']);
      expect(matches.length, 1);
      expect(matches.first.isMatched, isTrue);
      expect(matches.first.knowledgePointId, 'kp_math_functions_quadratic');
      expect(matches.first.confidence, lessThan(1.0));
    });

    test('unmatched text returns isMatched=false', () async {
      final matches = await service.mapStrings(<String>['量子力学基础']);
      expect(matches.length, 1);
      expect(matches.first.isMatched, isFalse);
      expect(matches.first.knowledgePointId, isNull);
    });

    test('mixed matched and unmatched', () async {
      final matches = await service.mapStrings(<String>[
        '二次函数',
        '量子力学',
        '牛顿运动定律',
        '不存在知识点',
      ]);
      expect(matches.length, 4);
      expect(matches.where((m) => m.isMatched).length, 2);
      expect(matches.where((m) => !m.isMatched).length, 2);
    });

    test('empty strings are skipped', () async {
      final matches = await service.mapStrings(<String>['', '  ', '二次函数']);
      expect(matches.length, 1);
    });

    test('disabled knowledge points are not matched', () async {
      final disabled = (await kpRepo.findById('kp_math_functions_quadratic'))!
          .copyWith(enabled: false);
      await kpRepo.upsert(disabled);

      final matches = await service.mapStrings(<String>['二次函数']);
      expect(matches.first.isMatched, isFalse);
    });
  });

  group('KnowledgePointMappingService.createLinksForQuestion', () {
    test('creates links for matched strings', () async {
      final unmatched = await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数', '抛物线'],
      );

      // Both match the same knowledge point, so 1 link (deduplicated by repo)
      final links = await linkRepo.linksForQuestion('q_1');
      expect(links.length, 1);
      expect(links.first.knowledgePointId, 'kp_math_functions_quadratic');
      expect(links.first.source, LinkSource.ai);
      expect(unmatched, isEmpty);
    });

    test('returns unmatched strings', () async {
      final unmatched = await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数', '量子力学'],
      );

      expect(unmatched, <String>['量子力学']);
      final links = await linkRepo.linksForQuestion('q_1');
      expect(links.length, 1);
    });

    test('replaceLinksForQuestion clears old links', () async {
      await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数'],
      );

      await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['牛顿运动定律'],
      );

      final links = await linkRepo.linksForQuestion('q_1');
      expect(links.length, 1);
      expect(links.first.knowledgePointId, 'kp_phys_mechanics_newton');
    });

    test('migrated source type', () async {
      await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数'],
        source: LinkSource.migrated,
      );

      final links = await linkRepo.linksForQuestion('q_1');
      expect(links.first.source, LinkSource.migrated);
    });

    test('first link is marked primary by default (Phase 6-3)', () async {
      await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数', '勾股定理'],
      );

      final links = await linkRepo.linksForQuestion('q_1');
      expect(links.length, 2);
      final primaryCount = links.where((l) => l.isPrimary).length;
      expect(primaryCount, 1);
    });

    test('primary is preserved when re-mapping (Phase 6-3)', () async {
      // First round: link 二次函数 (primary)
      await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数'],
      );
      // User manually promotes a different one via repo
      await linkRepo.setPrimary('q_1', 'kp_math_functions_quadratic');

      // Second round with a new set that still includes the old primary
      await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数', '勾股定理'],
      );

      final links = await linkRepo.linksForQuestion('q_1');
      final primary = links.firstWhere((l) => l.isPrimary);
      expect(primary.knowledgePointId, 'kp_math_functions_quadratic');
    });
  });

  group('KnowledgePointMappingService pending queue (Phase 4-C)', () {
    late PendingKnowledgePointMappingRepository pendingRepo;
    late KnowledgePointMappingService serviceWithPending;

    setUp(() {
      pendingRepo = PendingKnowledgePointMappingRepository();
      serviceWithPending = KnowledgePointMappingService(
        kpRepo,
        linkRepo,
        pendingRepo: pendingRepo,
      );
    });

    test('unmatched strings are written to pending queue', () async {
      await serviceWithPending.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数', '量子力学'],
      );

      final pending = await pendingRepo.pendingForQuestion('q_1');
      expect(pending.length, 1);
      expect(pending.first.questionId, 'q_1');
      expect(pending.first.originalText, '量子力学');
      expect(pending.first.isPending, isTrue);
    });

    test('matched strings are not written to pending queue', () async {
      await serviceWithPending.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['二次函数'],
      );

      final pending = await pendingRepo.pendingForQuestion('q_1');
      expect(pending, isEmpty);
    });

    test('without pendingRepo does not throw on unmatched', () async {
      // service (no pendingRepo) should still work as before
      final unmatched = await service.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['量子力学'],
      );
      expect(unmatched, <String>['量子力学']);
    });

    test('resolve removes mapping from pending list', () async {
      await serviceWithPending.createLinksForQuestion(
        questionId: 'q_1',
        knowledgePointTexts: <String>['量子力学'],
      );

      final pending = await pendingRepo.pendingForQuestion('q_1');
      expect(pending.length, 1);

      await pendingRepo.resolve(pending.first.id,
          resolution: PendingKnowledgePointResolution.ignored);

      final afterResolve = await pendingRepo.pendingForQuestion('q_1');
      expect(afterResolve, isEmpty);
    });
  });

  group('KnowledgePointMappingService.migrateFromQuestionRecords', () {
    test('batch migration creates links and returns unmatched', () async {
      final questions = <({String id, List<String> aiKnowledgePoints})>[
        (id: 'q_1', aiKnowledgePoints: <String>['二次函数', '勾股定理']),
        (id: 'q_2', aiKnowledgePoints: <String>['量子力学']),
        (id: 'q_3', aiKnowledgePoints: <String>[]),
      ];

      final unmatched = await service.migrateFromQuestionRecords(questions);

      // q_1: both matched (勾股定理 is alias of 三角形)
      // q_2: 量子力学 unmatched
      // q_3: empty, skipped
      expect(unmatched.length, 1);
      expect(unmatched.containsKey('q_2'), isTrue);
      expect(unmatched['q_2'], <String>['量子力学']);

      // Verify links were created
      final q1Links = await linkRepo.linksForQuestion('q_1');
      expect(q1Links.length, 2);
      expect(q1Links.every((l) => l.source == LinkSource.migrated), isTrue);
    });

    test('skips questions with empty aiKnowledgePoints', () async {
      final questions = <({String id, List<String> aiKnowledgePoints})>[
        (id: 'q_1', aiKnowledgePoints: <String>[]),
      ];

      final unmatched = await service.migrateFromQuestionRecords(questions);
      expect(unmatched, isEmpty);
    });
  });
}
