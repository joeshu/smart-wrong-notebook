import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  late KnowledgePointRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = KnowledgePointRepository();
  });

  KnowledgePoint kp(String id, {String? parentId, String? name, Subject? subject, int sortOrder = 0}) {
    return KnowledgePoint(
      id: id,
      name: name ?? id,
      parentId: parentId,
      subject: subject,
      sortOrder: sortOrder,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }

  group('KnowledgePointRepository', () {
    test('loadAll returns empty list initially', () async {
      final result = await repo.loadAll();
      expect(result, isEmpty);
    });

    test('upsert and findById', () async {
      final point = kp('kp_1', name: '二次函数');
      await repo.upsert(point);

      final found = await repo.findById('kp_1');
      expect(found, isNotNull);
      expect(found!.name, '二次函数');
    });

    test('findById returns null for non-existent id', () async {
      final found = await repo.findById('nonexistent');
      expect(found, isNull);
    });

    test('saveAll replaces all points', () async {
      await repo.upsert(kp('kp_1'));
      await repo.upsert(kp('kp_2'));

      await repo.saveAll(<KnowledgePoint>[kp('kp_3')]);

      final all = await repo.loadAll();
      expect(all.length, 1);
      expect(all.first.id, 'kp_3');
    });

    test('upsertAll adds multiple points', () async {
      await repo.upsertAll(<KnowledgePoint>[
        kp('kp_1'),
        kp('kp_2'),
        kp('kp_3'),
      ]);

      final all = await repo.loadAll();
      expect(all.length, 3);
    });

    test('remove deletes point and returns true', () async {
      await repo.upsert(kp('kp_1'));
      final removed = await repo.remove('kp_1');
      expect(removed, isTrue);

      final found = await repo.findById('kp_1');
      expect(found, isNull);
    });

    test('remove returns false for non-existent id', () async {
      final removed = await repo.remove('nonexistent');
      expect(removed, isFalse);
    });

    test('findBySubject filters by subject', () async {
      await repo.upsertAll(<KnowledgePoint>[
        kp('kp_math_1', subject: Subject.math, sortOrder: 2),
        kp('kp_math_2', subject: Subject.math, sortOrder: 1),
        kp('kp_phys_1', subject: Subject.physics),
      ]);

      final mathPoints = await repo.findBySubject(Subject.math);
      expect(mathPoints.length, 2);
      // Sorted by sortOrder
      expect(mathPoints[0].id, 'kp_math_2');
      expect(mathPoints[1].id, 'kp_math_1');
    });

    test('childrenOf returns direct children sorted by sortOrder', () async {
      await repo.upsertAll(<KnowledgePoint>[
        kp('kp_parent'),
        kp('kp_child_a', parentId: 'kp_parent', sortOrder: 2),
        kp('kp_child_b', parentId: 'kp_parent', sortOrder: 1),
        kp('kp_grandchild', parentId: 'kp_child_a'),
      ]);

      final children = await repo.childrenOf('kp_parent');
      expect(children.length, 2);
      expect(children[0].id, 'kp_child_b');
      expect(children[1].id, 'kp_child_a');
    });

    test('ancestorPath returns path from node to root', () async {
      await repo.upsertAll(<KnowledgePoint>[
        kp('kp_root'),
        kp('kp_mid', parentId: 'kp_root'),
        kp('kp_leaf', parentId: 'kp_mid'),
      ]);

      final path = await repo.ancestorPath('kp_leaf');
      expect(path.length, 3);
      expect(path[0].id, 'kp_leaf');
      expect(path[1].id, 'kp_mid');
      expect(path[2].id, 'kp_root');
    });

    test('ancestorPath returns empty for non-existent id', () async {
      final path = await repo.ancestorPath('nonexistent');
      expect(path, isEmpty);
    });

    test('search matches name and aliases case-insensitively', () async {
      await repo.upsertAll(<KnowledgePoint>[
        kp('kp_1', name: '牛顿运动定律'),
        KnowledgePoint(
          id: 'kp_2',
          name: '运动学',
          aliases: <String>['匀速直线运动'],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        kp('kp_3', name: '化学反应'),
      ]);

      final results = await repo.search('运动');
      expect(results.length, 2);
      expect(results.map((kp) => kp.id).toSet(),
          containsAll(<String>['kp_1', 'kp_2']));
    });

    test('merge reassigns children and removes source', () async {
      await repo.upsertAll(<KnowledgePoint>[
        kp('kp_source'),
        kp('kp_target'),
        kp('kp_child', parentId: 'kp_source'),
      ]);

      await repo.merge('kp_source', 'kp_target');

      expect(await repo.findById('kp_source'), isNull);
      final child = await repo.findById('kp_child');
      expect(child!.parentId, 'kp_target');
    });

    test('persists across instances (SharedPreferences)', () async {
      await repo.upsert(kp('kp_persisted', name: '持久化测试'));

      // Create a new instance — should load from SharedPreferences
      final newRepo = KnowledgePointRepository();
      final found = await newRepo.findById('kp_persisted');
      expect(found, isNotNull);
      expect(found!.name, '持久化测试');
    });

    test('seed builtins can be saved and loaded', () async {
      final seeds = KnowledgePointSeed.builtins();
      await repo.saveAll(seeds);

      final newRepo = KnowledgePointRepository();
      final loaded = await newRepo.loadAll();
      expect(loaded.length, seeds.length);

      // Verify tree structure
      final mathRoots = loaded
          .where((kp) => kp.subject == Subject.math && kp.isRoot)
          .toList();
      expect(mathRoots.length, greaterThanOrEqualTo(3)); // 代数, 几何, 函数
    });
  });
}
