import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_management_service.dart';

void main() {
  late KnowledgePointRepository repo;
  late KnowledgePointManagementService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = KnowledgePointRepository();
    service = KnowledgePointManagementService(repo);
  });

  group('KnowledgePointManagementService.ensureSeeded', () {
    test('seeds on first call', () async {
      final seeded = await service.ensureSeeded();
      expect(seeded, isTrue);

      final all = await service.all();
      expect(all.length, KnowledgePointSeed.builtins().length);
    });

    test('skips on second call (idempotent)', () async {
      await service.ensureSeeded();
      final seeded = await service.ensureSeeded();
      expect(seeded, isFalse);
    });

    test('skips if knowledge points already exist', () async {
      await repo.upsert(KnowledgePoint(
        id: 'kp_existing',
        name: '已存在',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));

      final seeded = await service.ensureSeeded();
      expect(seeded, isFalse);

      final all = await service.all();
      expect(all.length, 1);
      expect(all.first.id, 'kp_existing');
    });
  });

  group('KnowledgePointManagementService CRUD', () {
    setUp(() async {
      await service.ensureSeeded();
    });

    test('create adds a new knowledge point', () async {
      final kp = await service.create(
        name: '概率论',
        aliases: <String>['概率', '统计'],
        subject: Subject.math,
        sortOrder: 10,
      );

      expect(kp.name, '概率论');
      expect(kp.aliases, <String>['概率', '统计']);
      expect(kp.enabled, isTrue);

      final found = await repo.findById(kp.id);
      expect(found, isNotNull);
      expect(found!.name, '概率论');
    });

    test('create with parentId creates child node', () async {
      final parent = await service.create(name: '电学', subject: Subject.physics);
      final child = await service.create(
        name: '欧姆定律',
        parentId: parent.id,
        subject: Subject.physics,
      );

      expect(child.parentId, parent.id);
      final children = await service.childrenOf(parent.id);
      expect(children.length, 1);
      expect(children.first.id, child.id);
    });

    test('rename updates name', () async {
      final kp = await service.create(name: '原名');
      final renamed = await service.rename(kp.id, '新名');
      expect(renamed.name, '新名');
    });

    test('rename throws for non-existent id', () async {
      expect(
        () => service.rename('nonexistent', '新名'),
        throwsStateError,
      );
    });

    test('updateAliases replaces aliases', () async {
      final kp = await service.create(
        name: '测试',
        aliases: <String>['别名1'],
      );
      final updated = await service.updateAliases(kp.id, <String>['别名2', '别名3']);
      expect(updated.aliases, <String>['别名2', '别名3']);
    });

    test('setEnabled toggles enabled state', () async {
      final kp = await service.create(name: '测试');
      expect(kp.enabled, isTrue);

      final disabled = await service.setEnabled(kp.id, false);
      expect(disabled.enabled, isFalse);

      final enabled = await service.setEnabled(kp.id, true);
      expect(enabled.enabled, isTrue);
    });

    test('delete removes knowledge point', () async {
      final kp = await service.create(name: '待删除');
      final deleted = await service.delete(kp.id);
      expect(deleted, isTrue);

      final found = await repo.findById(kp.id);
      expect(found, isNull);
    });
  });

  group('KnowledgePointManagementService tree operations', () {
    setUp(() async {
      await service.ensureSeeded();
    });

    test('roots returns only root nodes', () async {
      final roots = await service.roots();
      expect(roots, isNotEmpty);
      for (final kp in roots) {
        expect(kp.isRoot, isTrue);
      }
    });

    test('childrenOf returns direct children', () async {
      // kp_math_algebra is a root in seed data
      final children = await service.childrenOf('kp_math_algebra');
      expect(children.length, 2); // 方程与不等式, 多项式
      expect(children[0].id, 'kp_math_algebra_equations');
      expect(children[1].id, 'kp_math_algebra_polynomials');
    });

    test('move changes parent', () async {
      final kp = await service.create(name: '移动测试', subject: Subject.math);
      final moved = await service.move(kp.id, 'kp_math_algebra');
      expect(moved.parentId, 'kp_math_algebra');

      final children = await service.childrenOf('kp_math_algebra');
      expect(children.any((c) => c.id == kp.id), isTrue);
    });

    test('move to null makes it a root', () async {
      final kp = await service.create(
        name: '子节点',
        parentId: 'kp_math_algebra',
      );
      final moved = await service.move(kp.id, null);
      expect(moved.parentId, isNull);
      expect(moved.isRoot, isTrue);
    });

    test('move throws on cycle (moving under descendant)', () async {
      final root = await service.create(name: '根');
      final child = await service.create(name: '子', parentId: root.id);
      final grandchild = await service.create(name: '孙', parentId: child.id);

      expect(
        () => service.move(root.id, grandchild.id),
        throwsArgumentError,
      );
    });

    test('merge reassigns children and deletes source', () async {
      final source = await service.create(name: '源');
      final target = await service.create(name: '目标');
      final child = await service.create(name: '子', parentId: source.id);

      await service.merge(source.id, target.id);

      expect(await repo.findById(source.id), isNull);
      final movedChild = await repo.findById(child.id);
      expect(movedChild!.parentId, target.id);
    });

    test('merge throws when source equals target', () async {
      final kp = await service.create(name: '测试');
      expect(
        () => service.merge(kp.id, kp.id),
        throwsArgumentError,
      );
    });
  });

  group('KnowledgePointManagementService filtering', () {
    setUp(() async {
      await service.ensureSeeded();
    });

    test('enabled returns only enabled knowledge points', () async {
      // Disable one
      await service.setEnabled('kp_math_algebra', false);

      final enabled = await service.enabled();
      expect(enabled.every((kp) => kp.enabled), isTrue);
      expect(enabled.any((kp) => kp.id == 'kp_math_algebra'), isFalse);
    });

    test('enabledBySubject filters by subject and enabled', () async {
      await service.setEnabled('kp_math_algebra', false);

      final mathEnabled = await service.enabledBySubject(Subject.math);
      expect(mathEnabled.every((kp) => kp.subject == Subject.math), isTrue);
      expect(mathEnabled.every((kp) => kp.enabled), isTrue);
      expect(mathEnabled.any((kp) => kp.id == 'kp_math_algebra'), isFalse);
    });
  });
}
