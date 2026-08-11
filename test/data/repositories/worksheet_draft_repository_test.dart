import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_draft_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';

WorksheetDraft _draft({
  required String id,
  required String name,
  List<String> questionIds = const <String>['q1', 'q2'],
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = createdAt ?? DateTime(2026, 7, 21);
  return WorksheetDraft(
    id: id,
    name: name,
    questionIds: questionIds,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  late WorksheetDraftRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = WorksheetDraftRepository();
  });

  group('WorksheetDraftRepository', () {
    test('save and loadAll round-trip', () async {
      await repo.save(_draft(id: 'd1', name: '期中卷'));
      await repo.save(_draft(id: 'd2', name: '期末卷'));

      final all = await repo.loadAll();
      expect(all, hasLength(2));
      expect(all.map((d) => d.id).toSet(), <String>{'d1', 'd2'});
    });

    test('loadAll returns empty list when no drafts', () async {
      expect(await repo.loadAll(), isEmpty);
    });

    test('save with existing id updates in place and preserves createdAt', () async {
      final original = _draft(
        id: 'd1',
        name: '期中卷',
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );
      await repo.save(original);

      // 稍后用相同 id 保存新内容
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repo.save(_draft(
        id: 'd1',
        name: '期中卷（修订）',
        questionIds: const <String>['q1', 'q2', 'q3'],
        createdAt: DateTime(2026, 7, 21),
        updatedAt: DateTime(2026, 7, 21),
      ));

      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.first.name, '期中卷（修订）');
      expect(all.first.questionIds, hasLength(3));
      // createdAt 应保留原始值
      expect(all.first.createdAt, DateTime(2026, 7, 1));
      // updatedAt 应刷新
      expect(all.first.updatedAt, DateTime(2026, 7, 21));
    });

    test('loadAll sorts by updatedAt descending (most recent first)', () async {
      await repo.save(_draft(
        id: 'old',
        name: '旧卷',
        updatedAt: DateTime(2026, 7, 1),
      ));
      await repo.save(_draft(
        id: 'new',
        name: '新卷',
        updatedAt: DateTime(2026, 7, 21),
      ));
      await repo.save(_draft(
        id: 'mid',
        name: '中卷',
        updatedAt: DateTime(2026, 7, 10),
      ));

      final all = await repo.loadAll();
      expect(all.map((d) => d.id).toList(), <String>['new', 'mid', 'old']);
    });

    test('delete removes only the targeted draft', () async {
      await repo.save(_draft(id: 'd1', name: '卷1'));
      await repo.save(_draft(id: 'd2', name: '卷2'));

      await repo.delete('d1');

      final all = await repo.loadAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'd2');
    });

    test('delete non-existent id is a no-op', () async {
      await repo.save(_draft(id: 'd1', name: '卷1'));
      await repo.delete('nonexistent');
      expect(await repo.loadAll(), hasLength(1));
    });

    test('clear removes all drafts', () async {
      await repo.save(_draft(id: 'd1', name: '卷1'));
      await repo.save(_draft(id: 'd2', name: '卷2'));

      await repo.clear();

      expect(await repo.loadAll(), isEmpty);
    });

    test('fromJson / toJson round-trip preserves all fields', () async {
      final original = _draft(
        id: 'd1',
        name: '测试卷',
        questionIds: const <String>['q1', 'q2', 'q3'],
        createdAt: DateTime(2026, 7, 1, 10),
        updatedAt: DateTime(2026, 7, 21, 15, 30),
      );
      await repo.save(original);

      final loaded = (await repo.loadAll()).first;
      expect(loaded.id, original.id);
      expect(loaded.name, original.name);
      expect(loaded.questionIds, original.questionIds);
      expect(loaded.createdAt, original.createdAt);
      expect(loaded.updatedAt, original.updatedAt);
    });

    test('corrupted data is cleared and returns empty list', () async {
      // 写入损坏的 JSON
      SharedPreferences.setMockInitialValues(<String, Object>{
        'worksheet_drafts_v1': 'not valid json',
      });
      expect(await repo.loadAll(), isEmpty);
      // 损坏数据应被清除
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('worksheet_drafts_v1'), isNull);
    });

    test('copyWith produces a modified copy without touching original', () {
      final original = _draft(id: 'd1', name: '原卷');
      final renamed = original.copyWith(name: '新名称');
      expect(renamed.name, '新名称');
      expect(renamed.id, 'd1');
      expect(original.name, '原卷');
    });
  });
}
