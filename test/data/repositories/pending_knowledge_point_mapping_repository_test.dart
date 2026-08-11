import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

void main() {
  late PendingKnowledgePointMappingRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = PendingKnowledgePointMappingRepository();
  });

  PendingKnowledgePointMapping mapping({
    required String id,
    required String questionId,
    required String text,
  }) {
    return PendingKnowledgePointMapping(
      id: id,
      questionId: questionId,
      originalText: text,
      createdAt: DateTime(2026),
    );
  }

  group('PendingKnowledgePointMappingRepository', () {
    test('add and pendingForQuestion', () async {
      await repo.add(mapping(
        id: 'p_1',
        questionId: 'q_1',
        text: '量子力学',
      ));

      final pending = await repo.pendingForQuestion('q_1');
      expect(pending.length, 1);
      expect(pending.first.id, 'p_1');
      expect(pending.first.originalText, '量子力学');
      expect(pending.first.isPending, isTrue);
    });

    test('pendingForQuestion only returns pending (not resolved)', () async {
      await repo.add(mapping(id: 'p_1', questionId: 'q_1', text: 'A'));
      await repo.add(mapping(id: 'p_2', questionId: 'q_1', text: 'B'));

      await repo.resolve('p_1',
          resolution: PendingKnowledgePointResolution.ignored);

      final pending = await repo.pendingForQuestion('q_1');
      expect(pending.length, 1);
      expect(pending.first.id, 'p_2');
    });

    test('pendingForQuestion filters by questionId', () async {
      await repo.add(mapping(id: 'p_1', questionId: 'q_1', text: 'A'));
      await repo.add(mapping(id: 'p_2', questionId: 'q_2', text: 'B'));

      expect((await repo.pendingForQuestion('q_1')).length, 1);
      expect((await repo.pendingForQuestion('q_2')).length, 1);
      expect((await repo.pendingForQuestion('q_3')).length, 0);
    });

    test('addMany adds multiple mappings', () async {
      await repo.addMany(<PendingKnowledgePointMapping>[
        mapping(id: 'p_1', questionId: 'q_1', text: 'A'),
        mapping(id: 'p_2', questionId: 'q_1', text: 'B'),
        mapping(id: 'p_3', questionId: 'q_2', text: 'C'),
      ]);

      expect((await repo.allPending()).length, 3);
      expect((await repo.pendingForQuestion('q_1')).length, 2);
    });

    test('dedup: same questionId + same text is not added twice', () async {
      await repo.add(mapping(id: 'p_1', questionId: 'q_1', text: '量子力学'));
      // 同题目同文本（不同 ID）应被去重
      await repo.add(mapping(id: 'p_2', questionId: 'q_1', text: '量子力学'));

      final pending = await repo.pendingForQuestion('q_1');
      expect(pending.length, 1);
      expect(pending.first.id, 'p_1');
    });

    test('dedup is case-insensitive and trims whitespace', () async {
      await repo.add(mapping(id: 'p_1', questionId: 'q_1', text: '量子力学'));
      await repo.add(mapping(id: 'p_2', questionId: 'q_1', text: '  量子力学  '));
      await repo.add(mapping(id: 'p_3', questionId: 'q_1', text: 'QUANTUM'));
      await repo.add(mapping(id: 'p_4', questionId: 'q_1', text: 'quantum'));

      final pending = await repo.pendingForQuestion('q_1');
      expect(pending.length, 2);
      final texts = pending.map((m) => m.originalText).toSet();
      expect(texts, <String>{'量子力学', 'QUANTUM'});
    });

    test('resolve with mapped resolution', () async {
      await repo.add(mapping(id: 'p_1', questionId: 'q_1', text: 'A'));
      await repo.resolve('p_1',
          resolution: PendingKnowledgePointResolution.mapped);

      final pending = await repo.pendingForQuestion('q_1');
      expect(pending, isEmpty);
    });

    test('resolve unknown id is a no-op', () async {
      await repo.resolve('nonexistent',
          resolution: PendingKnowledgePointResolution.ignored);
      // 不抛异常即视为通过
      expect((await repo.allPending()), isEmpty);
    });

    test('allPending returns pending across all questions', () async {
      await repo.addMany(<PendingKnowledgePointMapping>[
        mapping(id: 'p_1', questionId: 'q_1', text: 'A'),
        mapping(id: 'p_2', questionId: 'q_2', text: 'B'),
      ]);
      await repo.add(mapping(id: 'p_3', questionId: 'q_3', text: 'C'));
      await repo.resolve('p_2',
          resolution: PendingKnowledgePointResolution.ignored);

      final all = await repo.allPending();
      expect(all.length, 2);
      final ids = all.map((m) => m.id).toSet();
      expect(ids, <String>{'p_1', 'p_3'});
    });

    test('source is preserved from input', () async {
      await repo.add(PendingKnowledgePointMapping(
        id: 'p_1',
        questionId: 'q_1',
        originalText: 'A',
        source: LinkSource.migrated,
        createdAt: DateTime(2026),
      ));

      final pending = await repo.pendingForQuestion('q_1');
      expect(pending.first.source, LinkSource.migrated);
    });
  });
}
