import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  group('KnowledgePoint', () {
    test('toJson / fromJson round-trip preserves all fields', () {
      final kp = KnowledgePoint(
        id: 'kp_test_1',
        name: '二次函数',
        aliases: <String>['抛物线', '顶点'],
        parentId: 'kp_math_functions',
        subject: Subject.math,
        grade: '初三',
        enabled: true,
        sortOrder: 3,
        createdAt: DateTime(2026, 7, 21),
        updatedAt: DateTime(2026, 7, 21),
      );

      final json = kp.toJson();
      final restored = KnowledgePoint.fromJson(json);

      expect(restored.id, kp.id);
      expect(restored.name, kp.name);
      expect(restored.aliases, kp.aliases);
      expect(restored.parentId, kp.parentId);
      expect(restored.subject, Subject.math);
      expect(restored.grade, kp.grade);
      expect(restored.enabled, isTrue);
      expect(restored.sortOrder, kp.sortOrder);
      expect(restored.createdAt, kp.createdAt);
      expect(restored.updatedAt, kp.updatedAt);
    });

    test('isRoot returns true when parentId is null', () {
      final root = KnowledgePoint(
        id: 'kp_root',
        name: '代数',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final child = KnowledgePoint(
        id: 'kp_child',
        name: '方程',
        parentId: 'kp_root',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(root.isRoot, isTrue);
      expect(child.isRoot, isFalse);
    });

    test('allNames includes name and aliases', () {
      final kp = KnowledgePoint(
        id: 'kp_1',
        name: '牛顿运动定律',
        aliases: <String>['牛顿第一定律', '惯性'],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(kp.allNames, <String>['牛顿运动定律', '牛顿第一定律', '惯性']);
    });

    test('copyWith updates only specified fields', () {
      final kp = KnowledgePoint(
        id: 'kp_1',
        name: '原名',
        enabled: true,
        sortOrder: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026, 1, 1),
      );

      final updated = kp.copyWith(
        name: '新名',
        enabled: false,
        updatedAt: DateTime(2026, 7, 21),
      );

      expect(updated.id, 'kp_1');
      expect(updated.name, '新名');
      expect(updated.enabled, isFalse);
      expect(updated.sortOrder, 1); // 未指定，保持原值
      expect(updated.updatedAt, DateTime(2026, 7, 21));
    });

    test('equality based on id only', () {
      final a = KnowledgePoint(
        id: 'kp_1',
        name: 'A',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final b = KnowledgePoint(
        id: 'kp_1',
        name: 'B',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final c = KnowledgePoint(
        id: 'kp_2',
        name: 'A',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('KnowledgePointSeed', () {
    test('builtins returns non-empty list with unique IDs', () {
      final seeds = KnowledgePointSeed.builtins();
      expect(seeds, isNotEmpty);

      final ids = seeds.map((kp) => kp.id).toSet();
      expect(ids.length, seeds.length, reason: 'IDs must be unique');
    });

    test('builtins covers math, physics, chemistry', () {
      final seeds = KnowledgePointSeed.builtins();
      final subjects = seeds.map((kp) => kp.subject).toSet();

      expect(subjects, contains(Subject.math));
      expect(subjects, contains(Subject.physics));
      expect(subjects, contains(Subject.chemistry));
    });

    test('builtins has parent-child structure', () {
      final seeds = KnowledgePointSeed.builtins();
      final ids = seeds.map((kp) => kp.id).toSet();

      // At least one node has a parentId that exists in the set
      final hasChildren = seeds.any((kp) =>
          kp.parentId != null && ids.contains(kp.parentId));
      expect(hasChildren, isTrue);
    });

    test('builtins all have enabled=true', () {
      final seeds = KnowledgePointSeed.builtins();
      for (final kp in seeds) {
        expect(kp.enabled, isTrue, reason: '${kp.id} should be enabled');
      }
    });
  });
}
