import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_import_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';

QuestionRecord _record(
  String id, {
  ContentStatus status = ContentStatus.ready,
}) {
  final now = DateTime(2026, 7, 21);
  return QuestionRecord(
    id: id,
    imagePath: '/tmp/$id.png',
    subject: Subject.math,
    extractedQuestionText: '题干 $id',
    normalizedQuestionText: '题干 $id',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

WorksheetImportSession _session({
  List<QuestionRecord> pages = const <QuestionRecord>[],
  Set<String> sourcePageIds = const <String>{},
  Set<String> processedSourcePageIds = const <String>{},
  String? lastProcessedId,
  bool autoAnalyze = false,
}) {
  return WorksheetImportSession(
    id: 'batch',
    pages: pages,
    sourcePageIds: sourcePageIds,
    createdAt: DateTime(2026, 7, 21),
    processedSourcePageIds: processedSourcePageIds,
    lastProcessedId: lastProcessedId,
    autoAnalyze: autoAnalyze,
  );
}

void main() {
  late WorksheetImportRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = WorksheetImportRepository();
  });

  group('WorksheetImportRepository 持久化扩展字段', () {
    test('save/load round-trip 保留 processedSourcePageIds、lastProcessedId、autoAnalyze',
        () async {
      final page1 = _record('page1');
      final page2 = _record('page2');
      final draft = _record('draft1');
      final session = _session(
        pages: <QuestionRecord>[page1, page2, draft],
        sourcePageIds: <String>{page1.id, page2.id},
        processedSourcePageIds: <String>{page1.id},
        lastProcessedId: page1.id,
        autoAnalyze: true,
      );

      await repo.save(session);
      final restored = await repo.load();

      expect(restored, isNotNull);
      expect(restored!.processedSourcePageIds, <String>{page1.id});
      expect(restored.lastProcessedId, page1.id);
      expect(restored.autoAnalyze, isTrue);
      expect(restored.sourcePageIds, <String>{page1.id, page2.id});
      expect(restored.pages.map((p) => p.id).toList(),
          <String>['page1', 'page2', 'draft1']);
    });

    test('老草稿（缺新字段）load 时回落到默认空集合与 false', () async {
      // 模拟 v0 草稿：只有 id/pages/sourcePageIds/createdAt 四项。
      final legacyJson = {
        'id': 'batch',
        'pages': <Map<String, dynamic>>[
          _record('p1').toJson(),
        ],
        'sourcePageIds': <String>['p1'],
        'createdAt': DateTime(2026, 7, 21).toIso8601String(),
      };
      SharedPreferences.setMockInitialValues(<String, Object>{
        'worksheet_import_session_v1': jsonEncode(legacyJson),
      });

      final restored = await repo.load();
      expect(restored, isNotNull);
      expect(restored!.processedSourcePageIds, isEmpty);
      expect(restored.lastProcessedId, isNull);
      expect(restored.autoAnalyze, isFalse);
    });
  });

  group('WorksheetImportRepository processing 兜底重置', () {
    test('load 时把 processing 页面统一改为 failed', () async {
      final page = _record('page', status: ContentStatus.ready);
      final processing1 =
          _record('draft1', status: ContentStatus.processing);
      final processing2 =
          _record('draft2', status: ContentStatus.processing);
      final failed = _record('draft3', status: ContentStatus.failed);

      await repo.save(_session(
        pages: <QuestionRecord>[page, processing1, processing2, failed],
        sourcePageIds: <String>{page.id},
      ));
      final restored = await repo.load();

      expect(restored, isNotNull);
      final byId = {for (final p in restored!.pages) p.id: p};
      expect(byId['page']!.contentStatus, ContentStatus.ready);
      expect(byId['draft1']!.contentStatus, ContentStatus.failed);
      expect(byId['draft2']!.contentStatus, ContentStatus.failed);
      expect(byId['draft3']!.contentStatus, ContentStatus.failed);
    });

    test('清空草稿后 load 返回 null', () async {
      await repo.save(_session(pages: <QuestionRecord>[_record('p1')]));
      await repo.clear();
      expect(await repo.load(), isNull);
    });
  });
}
